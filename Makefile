.PHONY: all test test-unit test-legacy

test-unit:
	nix flake check

test-legacy:
	nix-shell -p nixVersions.latest --run "nix-build --no-out-link ./tests/legacy/default.nix --show-trace"

test: test-unit

all: test
