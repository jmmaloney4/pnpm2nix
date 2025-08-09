{ pkgs ? import <nixpkgs> {}, root ? ./. }:
let
  pnpm2nix = import (root + "/.") { inherit pkgs; nodejs = pkgs.nodejs_20 or pkgs.nodejs; };
  src = ./.;
in
  pnpm2nix.mkPnpmPackage { inherit src; }


