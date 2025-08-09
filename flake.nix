{
  description = "pnpm2nix flake: devShells and checks (unit/integration)";

  inputs.nixpkgs.url = "nixpkgs";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system:
        let pkgs = import nixpkgs { inherit system; }; in f pkgs);
    in {
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          buildInputs = [ pkgs.nodejs pkgs.nodePackages.node-gyp pkgs.jq pkgs.yaml2json pkgs.git ];
        };
      });

      checks = forAllSystems (pkgs: {
        unit-normalize-v5 = pkgs.runCommand "unit-normalize-v5" {} ''
          export HOME=$TMPDIR
          export XDG_CACHE_HOME=$TMPDIR
          ${pkgs.nix}/bin/nix-instantiate --eval --json -E 'import ${./tests/unit/normalize-v5.nix} { root = ${./.}; }' >/dev/null
          mkdir $out; echo ok > $out/result
        '';
        unit-normalize-v9 = pkgs.runCommand "unit-normalize-v9" {} ''
          export HOME=$TMPDIR
          export XDG_CACHE_HOME=$TMPDIR
          ${pkgs.nix}/bin/nix-instantiate --eval --json -E 'import ${./tests/unit/normalize-v9.nix} { root = ${./.}; }' >/dev/null
          mkdir $out; echo ok > $out/result
        '';
        unit-rewrite-v9 = pkgs.runCommand "unit-rewrite-v9" {} ''
          export HOME=$TMPDIR
          export XDG_CACHE_HOME=$TMPDIR
          ${pkgs.nix}/bin/nix-instantiate --eval --json -E 'import ${./tests/unit/rewrite-v9.nix} { root = ${./.}; }' >/dev/null
          mkdir $out; echo ok > $out/result
        '';
        unit-normalize-v9-golden = pkgs.runCommand "unit-normalize-v9-golden" {} ''
          export HOME=$TMPDIR
          export XDG_CACHE_HOME=$TMPDIR
          ${pkgs.nix}/bin/nix-instantiate --eval --json -E 'import ${./tests/unit/normalize-v9-golden.nix} { root = ${./.}; }' | ${pkgs.jq}/bin/jq . > $out
        '';
        unit-normalize-v9-workspace = pkgs.runCommand "unit-normalize-v9-workspace" {} ''
          export HOME=$TMPDIR
          export XDG_CACHE_HOME=$TMPDIR
          ${pkgs.nix}/bin/nix-instantiate --eval --json -E 'import ${./tests/unit/normalize-v9-workspace.nix} { root = ${./.}; }' >/dev/null
          mkdir $out; echo ok > $out/result
        '';
        unit-rewrite-v9-workspace = pkgs.runCommand "unit-rewrite-v9-workspace" {} ''
          export HOME=$TMPDIR
          export XDG_CACHE_HOME=$TMPDIR
          ${pkgs.nix}/bin/nix-instantiate --eval --json -E 'import ${./tests/unit/rewrite-v9-workspace.nix} { root = ${./.}; }' >/dev/null
          mkdir $out; echo ok > $out/result
        '';
        integ-workspace-v9 = pkgs.runCommand "integ-workspace-v9" {} ''
          export HOME=$TMPDIR
          export XDG_CACHE_HOME=$TMPDIR
          drv=$(${pkgs.nix}/bin/nix-instantiate -E 'let pkgs=import <nixpkgs>{}; in import ${./tests/workspace-v9} { inherit pkgs; root = ${./.}; }')
          ${pkgs.nix}/bin/nix-store --realise "$drv" >/dev/null
          mkdir $out; echo ok > $out/result
        '';
        integ-v9-single = pkgs.runCommand "integ-v9-single" {} ''
          export HOME=$TMPDIR
          export XDG_CACHE_HOME=$TMPDIR
          drv=$(${pkgs.nix}/bin/nix-instantiate -E 'let pkgs=import <nixpkgs>{}; in import ${./tests/single-v9} { inherit pkgs; root = ${./.}; }')
          ${pkgs.nix}/bin/nix-store --realise "$drv" >/dev/null
          mkdir $out; echo ok > $out/result
        '';
      });
    };
}


