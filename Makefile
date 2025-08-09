.PHONY: all test

test:
	nix-shell -p nixVersions.latest --run "nix-build --no-out-link ./tests/default.nix --show-trace"

all: test
