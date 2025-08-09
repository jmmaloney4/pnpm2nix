{ pkgs, lib ? pkgs.lib }:

# Normalize a pnpm v9 lockfile JSON to the internal IR used by the
# rewrite graph. Single-importer (".") only for the initial support.

raw:
let
  die = msg: throw ("pnpm2nix v9 normalize: " + msg);

  # Extract importer "." only
  importers = if (lib.hasAttr "importers" raw) then raw.importers else die "missing importers";
  root = if (lib.hasAttr "." importers) then importers."." else die "only single importer (.) is supported";

  # Root dependency maps (default to empty attrsets)
  rootDeps = attr: if (lib.hasAttr attr root && root."${attr}" != null) then root."${attr}" else {};

  # Convert a snapshot key like "@scope/name@1.2.3(react@18)" to base "@scope/name@1.2.3"
  stripPeerQualifiers = s:
    let m = builtins.match "([^\(]+).*" s; in if m == null then s else builtins.elemAt m 0;

  # Split "name@version" at the last '@'
  splitAtLastAt = s:
    let parts = lib.splitString "@" s;
        version = builtins.elemAt parts (lib.length parts - 1);
        nameParts = lib.sublist 0 (lib.length parts - 1) parts;
        name = lib.concatStringsSep "@" nameParts;
    in { inherit name version; };

  # Turn name/version into "/name/version" key
  keyFor = name: version: "/" + name + "/" + version;

  # Build initial IR packages from raw.packages (keys are name@version)
  rawPackages = if (lib.hasAttr "packages" raw) then raw.packages else {};
  packages0 = lib.mapAttrs (k: v:
    let sv = splitAtLastAt k; in v // { constituents = [ (keyFor sv.name sv.version) ]; }
  ) rawPackages;

  # Aggregate dependency maps from snapshots onto packages
  rawSnapshots = if (lib.hasAttr "snapshots" raw) then raw.snapshots else {};
  aggregated = lib.foldl' (
    acc: nameWithPeers:
      let base = stripPeerQualifiers nameWithPeers;
          sv = splitAtLastAt base;
          k = keyFor sv.name sv.version;
          snap = rawSnapshots."${nameWithPeers}";
          deps = if (lib.hasAttr "dependencies" snap) then snap.dependencies else {};
          opt = if (lib.hasAttr "optionalDependencies" snap) then snap.optionalDependencies else {};
          peers = if (lib.hasAttr "peerDependencies" snap) then snap.peerDependencies else {};
          current = acc."${k}" or { dependencies = {}; optionalDependencies = {}; peerDependencies = {}; };
      in acc // {
        "${k}" = {
          dependencies = current.dependencies // deps;
          optionalDependencies = current.optionalDependencies // opt;
          peerDependencies = current.peerDependencies // peers;
        };
      }
  ) {} (lib.attrNames rawSnapshots);

  # Merge aggregated deps into packages; ensure all keys exist that appear in snapshots
  packages = let
    withSnapshotKeys = lib.foldl' (p: k:
      if lib.hasAttr k p then p else p // {
        "${k}" = { constituents = [ k ]; };
      }
    ) packages0 (lib.attrNames aggregated);
  in lib.mapAttrs (k: v:
    let add = aggregated."${k}" or { dependencies = {}; optionalDependencies = {}; peerDependencies = {}; };
    in v // add
  ) withSnapshotKeys;

  lockfileVersionMajor = 9;

in {
  inherit lockfileVersionMajor packages;

  # Keep registry if present
  registry = if (lib.hasAttr "registry" raw) then raw.registry else null;

  # Root dependency maps (resolved later by rewrite stage)
  dependencies = rootDeps "dependencies";
  devDependencies = rootDeps "devDependencies";
  optionalDependencies = rootDeps "optionalDependencies";
}


