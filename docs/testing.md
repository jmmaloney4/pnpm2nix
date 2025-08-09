### Testing strategy redesign

#### Goals
- Fast feedback for lockfile format work (v5 and v9) without flakiness
- Deterministic, hermetic tests that don’t rely on host toolchain quirks
- Keep a small set of real builds for end-to-end assurance, but isolate their cost

#### Problems in current tests
- Depend on an old nixpkgs pin and Python 2
- Native Node modules compile against whatever Node is on PATH, failing as Node/V8 evolve
- Network and registry assumptions lead to nondeterminism
- All tests run as one monolith, making failures slow and hard to triage

#### Tiered test design
1) Unit (eval-only, fast, pure)
   - Normalize tests: feed minimal lockfiles (v5, v9) into `lockfile/normalize.nix`; assert IR fields
   - Rewrite tests: feed IR into graph rewrite; assert resolved deps/peers, cycle-breaking, root deps
   - Golden JSON snapshots for IR and rewritten graph to catch regressions

2) Integration (small builds, hermetic)
   - Small fixtures with pure-JS dependencies only (no native addons)
   - Exercises: peer deps, link:, git/tarball resolution, optional deps
   - Pin Node LTS and nixpkgs; avoid live network when practical (prefer integrity pins)

3) Legacy (optional, slow/real-world)
   - Keep representative existing tests that build larger graphs or native addons
   - Run behind an opt-in target or separate CI job (can be allow-failure)

#### Golden testing
- Produce JSON for normalized IR and rewritten graph and compare with files in `tests/golden/`
- Add a “regenerate” target to update goldens intentionally
- Keep goldens tiny and focused (one for v5 minimal, one for v9 minimal, plus peer/link cases)

#### Environment pinning
- Prefer a flake (recommended): pin `nixpkgs` and expose devShells and checks
- Non-flake fallback: use `fetchTarball` pin in tests and Makefile includes
- Always force Node LTS for builds. In `derivation.nix` build phases:
  - prepend `${nodejs}/bin` to PATH
  - export `NODE=${nodejs}/bin/node`
  - keep `npm_config_nodedir=${nodejs}` to point headers

#### Network determinism
- Prefer registry downloads with integrity hashes or explicit tarball URLs
- Allow `allowImpure = true` only in tests that need to exercise impure paths, and isolate them

#### Makefile targets
- `test`: run unit + integration
- `test:unit`: eval-only golden checks
- `test:integration`: small builds with pure-JS fixtures
- `test:legacy`: run legacy suite (opt-in)

#### CI plan
- Matrix jobs (via flake checks or CI config):
  - unit (eval only, required)
  - integration (required)
  - legacy (optional/allow-failure)
- Cache: enable Nix binary caches for speed; avoid compiling large native stacks in critical jobs

#### Migration steps
1) Add unit goldens for normalize v5/v9 and rewrite graph
2) Create `tests/integration/` fixtures (pure-JS) and hook `test:integration`
3) Move native-heavy tests to `tests/legacy/` and add `test:legacy`
4) Pin environment: introduce `flake.nix` (or pin in tests), and enforce Node LTS in build phases
5) Wire Makefile targets and CI matrix

#### Rationale
- Most regressions we care about are structural (parsing/normalizing/rewrite) → caught by unit goldens
- Integration confirms we still produce runnable builds in a modern toolchain without native churn
- Legacy coverage remains available without blocking day-to-day development


