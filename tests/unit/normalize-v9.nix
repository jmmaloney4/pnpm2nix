{ }:

let
  pkgs = import <nixpkgs> {};
  lib = pkgs.lib;
  normalize = import ../../lockfile/normalize.nix { inherit pkgs lib; };
  raw = {
    lockfileVersion = "9.0";
    importers = { "." = {
      dependencies = { leftpad = "1.3.0"; };
    }; };
    packages = {
      "leftpad@1.3.0" = { resolution = { integrity = "sha512-..."; }; };
    };
    snapshots = {
      "leftpad@1.3.0" = { };
    };
  };
  ir = normalize raw;
  hasPkg = builtins.hasAttr "/leftpad/1.3.0" ir.packages;
  constituentsLen = if hasPkg then (builtins.length ir.packages."/leftpad/1.3.0".constituents) else 0;
  depLeftpad = ir.dependencies.leftpad or null;
in assert (ir.lockfileVersionMajor == 9);
assert hasPkg;
assert (builtins.isInt constituentsLen);
assert (builtins.isString depLeftpad);
true


