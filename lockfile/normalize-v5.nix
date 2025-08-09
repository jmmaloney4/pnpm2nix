{ pkgs, lib ? pkgs.lib }:

# Normalize a pnpm v5/v5.1 lockfile JSON to the internal IR used by the
# rewrite graph. This adapter preserves the current behavior and synthesizes
# an `importers` map for compatibility with workspaces logic.

raw: let
  # Ensure we have a packages attrset
  packages = if (lib.hasAttr "packages" raw) then raw.packages else {};

  # Ensure each package has constituents and pass through metadata as-is
  withConstituents = lib.mapAttrs (k: v: (v // {
    constituents = [ k ];
  })) packages;

  # Top-level dependency maps may be missing; default to {}
  rootDeps = attr:
    if (lib.hasAttr attr raw && raw."${attr}" != null) then raw."${attr}" else {};

  lockfileVersionMajor = 5;

in {
  inherit lockfileVersionMajor;

  # Keep registry if present
  registry = if (lib.hasAttr "registry" raw) then raw.registry else null;

  # Root dependency maps (resolved to attr names later by the rewrite stage)
  dependencies = rootDeps "dependencies";
  devDependencies = rootDeps "devDependencies";
  optionalDependencies = rootDeps "optionalDependencies";

  # Synthesize importers – for v5, treat top-level as importer "."
  importers = if (lib.hasAttr "importers" raw)
    then raw.importers
    else {
      "." = {
        dependencies = rootDeps "dependencies";
        devDependencies = rootDeps "devDependencies";
        optionalDependencies = rootDeps "optionalDependencies";
      };
    };

  # Package set for the resolver
  packages = withConstituents;
}


