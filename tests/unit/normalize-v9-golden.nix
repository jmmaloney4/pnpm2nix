{ root }:

let
  pkgs = import <nixpkgs> {};
  lib = pkgs.lib;
  normalize = import (root + "/lockfile/normalize.nix") { inherit pkgs lib; };
  raw = builtins.fromJSON (builtins.readFile (root + "/tests/unit/fixtures/v9-minimal.json"));
  ir = normalize raw;
  # Keep only a stable subset for golden
  golden = {
    lockfileVersionMajor = ir.lockfileVersionMajor;
    rootDependencies = builtins.attrNames (ir.dependencies or {});
    packages = lib.mapAttrs (k: v: {
      pname = v.pname or v.rawPname or null;
      version = v.version or null;
      dependencies = v.dependencies or {};
      optionalDependencies = v.optionalDependencies or {};
      peerDependencies = v.peerDependencies or {};
      constituentsLen = (builtins.length (v.constituents or []));
    }) ir.packages;
  };
in builtins.toJSON golden


