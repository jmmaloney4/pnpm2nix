with (import ((import <nixpkgs> {}).fetchFromGitHub {
  repo = "nixpkgs-channels";
  owner = "NixOS";
  sha256 = "1bjq5gl08pni6q2nqv9w98ym3kybzf7qc6cx4js0388vg8zfgf2k";
  rev = "49a16a290e68ebb1ef5acadf25cf149d0d530d05";
}) { });
with lib.attrsets;
with lib;

let
  importTest = testFile: (import testFile { inherit pkgs; });

  pnpm2nix = ../..;

  lolcatjs = importTest ../lolcatjs;
  test-sharp = importTest ../test-sharp;
  test-impure = importTest ../test-impure;
  nested-dirs = importTest ../nested-dirs;
  test-peerdependencies = importTest ../test-peerdependencies;
  test-devdependencies = importTest ../test-devdependencies;
  web3 = importTest ../web3;
  issue-1 = importTest ../issues/1;
  test-falsy-script = importTest ../test-falsy-script;
  test-filedeps = importTest ../file-dependencies;
  test-circular = importTest ../test-circular;
  test-scoped = importTest ../test-scoped;
  test-recursive-link = importTest ../recursive-link/packages/a;

  mkTest = (name: test: pkgs.runCommandNoCC "${name}" { } (''
    mkdir $out

  '' + test));

in
lib.listToAttrs (map (drv: nameValuePair drv.name drv) [

  (mkTest "assert-version" ''
    if test $(${lolcatjs}/bin/lolcatjs --version | grep "${lolcatjs.version}" | wc -l) -ne 1; then
      echo "Incorrect version attribute! Was: ${lolcatjs.version}, got:"
      ${lolcatjs}/bin/lolcatjs --version
      exit 1
    fi
  '')

  (mkTest "assert-optionaldependencies" ''
    if test $(${lolcatjs}/bin/lolcatjs --help |& grep "Unable to load" | wc -l) -ne 0; then
      echo "Optional dependency missing"
      exit 1
    fi
  '')

  (mkTest "native-overrides" "${test-sharp}/bin/testsharp")

  (mkTest "impure" "${test-impure}/bin/testapn")

  (mkTest "python-lint" ''
    echo ${(python2.withPackages (ps: [ ps.flake8 ]))}/bin/flake8 ${pnpm2nix}/
  '')

  (mkTest "nested-dirs" ''
    test -e ${lib.getLib nested-dirs}/node_modules/@types/node || (echo "Nested directory structure does not exist"; exit 1)
  '')

  (mkTest "peerdependencies" ''
    winstonPeer=$(readlink -f ${lib.getLib test-peerdependencies}/node_modules/winston-logstash/../winston)
    winstonRoot=$(readlink -f ${lib.getLib test-peerdependencies}/node_modules/winston)

    test "''${winstonPeer}" = "''${winstonRoot}" || (echo "Different versions in root and peer dependency resolution"; exit 1)
  '')

  (let
    web3Drv = lib.elemAt (lib.filter (x: x.name == "web3-1.0.0-beta.55") web3.buildInputs) 0;
  in mkTest "test-beta-names" ''
    test "${web3Drv.name}" = "web3-1.0.0-beta.55" || (echo "web3 name mismatch"; exit 1)
    test "${web3Drv.version}" = "1.0.0-beta.55" || (echo "web3 version mismatch"; exit 1)
  '')

  (mkTest "devdependencies" ''
    for testScript in "pretest" "test" "posttest"; do
      test -f ${lib.getLib test-devdependencies}/node_modules/test-devdependencies/build/''${testScript}
    done
  '')

  (mkTest "issue-1" ''
    echo ${issue-1}
  '')

  (mkTest "test-falsy-scripts" ''
    echo ${test-falsy-script}
  '')

  (mkTest "test-filedeps" ''
    ${test-filedeps}/bin/test-module
  '')

  (mkTest "test-circular" ''
    HOME=$(mktemp -d) ${test-circular}/bin/test-circular
  '')

  (mkTest "test-scoped" ''
    ${test-scoped}/bin/test-scoped
  '')
])


