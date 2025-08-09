{ root }:

let
  pkgs = import <nixpkgs> {};
  lib = pkgs.lib;
  normalize = import (root + "/lockfile/normalize.nix") { inherit pkgs lib; };
  rewriteGraph = import (root + "/pnpmlock.nix") { inherit pkgs; nodejs = pkgs.nodejs; nodePackages = pkgs.nodePackages; };

  raw = builtins.fromJSON (builtins.readFile (root + "/tests/unit/fixtures/v9-workspace.json"));
  ir = normalize raw;
  rg = rewriteGraph ir;

  leftpadKey = "/leftpad/1.3.0";
  depAKey = "/dep-a/1.0.0";
  leftpadDeps = rg.packages.${leftpadKey}.dependencies or [];

  rootsDot = rg.importersResolved."." or null;
  rootsA = rg.importersResolved."pkg-a" or null;
in
  assert (builtins.hasAttr leftpadKey rg.packages);
  assert (builtins.hasAttr depAKey rg.packages);
  assert (lib.elem depAKey leftpadDeps);
  assert (rootsDot != null && (lib.elem leftpadKey rootsDot.dependencies));
  assert (rootsA != null && (lib.elem depAKey rootsA.dependencies));
  true


