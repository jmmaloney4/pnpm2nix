{ root }:

let
  pkgs = import <nixpkgs> {};
  lib = pkgs.lib;
  normalize = import (root + "/lockfile/normalize.nix") { inherit pkgs lib; };
  raw = builtins.fromJSON (builtins.readFile (root + "/tests/unit/fixtures/v9-workspace.json"));
  ir = normalize raw;
in
  assert (ir.lockfileVersionMajor == 9);
  assert (builtins.hasAttr "importers" ir);
  assert (builtins.hasAttr "." ir.importers);
  assert (builtins.hasAttr "pkg-a" ir.importers);
  assert (builtins.hasAttr "/leftpad/1.3.0" ir.packages);
  assert (builtins.hasAttr "/dep-a/1.0.0" ir.packages);
  true


