{ root }:

let
  pkgs = import <nixpkgs> {};
  lib = pkgs.lib;
  normalize = import (root + "/lockfile/normalize.nix") { inherit pkgs lib; };
  rewriteGraph = import (root + "/pnpmlock.nix") { inherit pkgs; nodejs = pkgs.nodejs; nodePackages = pkgs.nodePackages; };

  raw = {
    lockfileVersion = "9.0";
    importers = { "." = {
      dependencies = { leftpad = "1.3.0"; };
    }; };
    packages = {
      "leftpad@1.3.0" = { resolution = {}; };
      "dep-a@1.0.0" = { resolution = {}; };
    };
    snapshots = {
      "leftpad@1.3.0" = { dependencies = { "dep-a" = "1.0.0"; }; };
      "dep-a@1.0.0" = { };
    };
  };

  ir = normalize raw;
  rg = rewriteGraph ir;

  leftpadKey = "/leftpad/1.3.0";
  depAKey = "/dep-a/1.0.0";
  leftpadDeps = rg.packages.${leftpadKey}.dependencies or [];

assert (builtins.hasAttr leftpadKey rg.packages);
assert (builtins.hasAttr depAKey rg.packages);
assert (lib.elem depAKey leftpadDeps);
true


