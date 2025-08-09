{ pkgs, lib ? pkgs.lib }:

# Normalize a pnpm v9 lockfile JSON to the internal IR used by the
# rewrite graph. Multi-importer workspaces supported.

raw:
let
  die = msg: throw ("pnpm2nix v9 normalize: " + msg);

  # Importers map (all importers)
  importersRaw = if (lib.hasAttr "importers" raw) then raw.importers else die "missing importers";
  sanitizeRoot = imp: attr: if (lib.hasAttr attr imp && imp."${attr}" != null) then imp."${attr}" else {};
  importers = lib.mapAttrs (n: imp: {
    dependencies = sanitizeRoot imp "dependencies";
    devDependencies = sanitizeRoot imp "devDependencies";
    optionalDependencies = sanitizeRoot imp "optionalDependencies";
  }) importersRaw;

  # Convenience accessor for top-level single-importer behavior
  root = if (lib.hasAttr "." importers) then importers."." else { dependencies = {}; devDependencies = {}; optionalDependencies = {}; };

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

  # Build initial IR packages from raw.packages; re-key to "/name/version"
  rawPackages = if (lib.hasAttr "packages" raw) then raw.packages else {};
  packages0 = lib.foldl' (acc: k:
    let
      v = rawPackages."${k}";
      sv = splitAtLastAt k;
      newKey = keyFor sv.name sv.version;
    in acc // { "${newKey}" = v // { constituents = [ newKey ]; } }
  ) {} (lib.attrNames rawPackages);

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
  inherit lockfileVersionMajor packages importers;

  # Keep registry if present
  registry = if (lib.hasAttr "registry" raw) then raw.registry else null;

  # Root dependency maps (resolved later by rewrite stage)
  dependencies = root.dependencies;
  devDependencies = root.devDependencies;
  optionalDependencies = root.optionalDependencies;
}


