{ pkgs ? import <nixpkgs> {} }:
let
  pnpm2nix = import ../.. { inherit pkgs; nodejs = pkgs.nodejs_20 or pkgs.nodejs; };
  root = ./.;
in
  # This evaluates the derivations for both importers ("." and "pkg-a").
  pnpm2nix.mkPnpmPackage { src = root; }


