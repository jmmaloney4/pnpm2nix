{ }:

let
  pkgs = import <nixpkgs> {};
  lib = pkgs.lib;
  normalize = import ../../lockfile/normalize.nix { inherit pkgs lib; };
  raw = {
    lockfileVersion = 5;
    packages = {
      "/camelcase/4.1.0" = {};
    };
    dependencies = { camelcase = "4.1.0"; };
  };
  ir = normalize raw;
  hasPkg = builtins.hasAttr "/camelcase/4.1.0" ir.packages;
  constituentsLen = if hasPkg then (builtins.length ir.packages."/camelcase/4.1.0".constituents) else 0;
  depCamelcase = ir.dependencies.camelcase or null;
in {
  lockfileVersionMajor = ir.lockfileVersionMajor;
  hasPkg = hasPkg;
  constituentsLenIsInt = builtins.isInt constituentsLen;
  depCamelcaseIsString = builtins.isString depCamelcase;
}


