## Design: Modular, backwards-compatible support for pnpm lockfile 9.0

### Context and goals

- Goal: add support for pnpm lockfile version 9.0 while preserving current behavior for v5/v5.1, with a modular internal architecture to ease future lockfile upgrades.
- Scope: parsing and normalizing pnpm lockfiles, resolving dependencies and peers, and integrating with existing derivation/build logic without breaking existing users/tests.

### What the code does today (v5/v5.1)

The pipeline is:
- `default.nix` reads `pnpm-lock.yaml` (via `yaml2json`), then calls `rewritePnpmLock` from `pnpmlock.nix` and asserts lockfile version 5/5.1.
- `pnpmlock.nix` expects a pnpm v5-shaped object with top-level `dependencies`, `devDependencies`, `optionalDependencies`, and a `packages` map keyed like `"/name/version"`. It computes a normalized DAG, resolves peers and dependencies to these package keys, flattens cycles, then returns a structure used by `mkPnpmPackage` to build derivations.

Key references in the current code:

```201:206:default.nix
  in
    assert (pnpmlock.lockfileVersion == 5 || pnpmlock.lockfileVersion == 5.1);
  (mkPnpmDerivation {
    deps = (builtins.map
      (attrName: packages."${attrName}")
      (pnpmlock.dependencies ++ pnpmlock.optionalDependencies));
```

```251:260:pnpmlock.nix
    # Recursive workspaces are currently unsupported
    (pnpmlock: (
      if lib.hasAttr "importers" pnpmlock
      then (throw "Workspaces currently unsupported. This is a regression from pnpm 2.x.")
      else pnpmlock))

    # A bare bones project might not have the packages attribute
    (pnpmlock: pnpmlock // {
      packages = if (lib.hasAttr "packages" pnpmlock) then pnpmlock.packages else {};
    })
```

For clarity, `pnpmlock.nix` itself documents the expected internal shape (v5 era):

```11:19:pnpmlock.nix
# After rewriting you end up with a datastructure that looks like (JSON):
# {
#   "dependencies": [ "/yargs/8.0.2" ],
#   "devDependencies": [],
#   "optionalDependencies": [],
#   "packages": {
#     "/camelcase/4.1.0": {
```

### What changes in pnpm lockfile v9

Based on pnpm’s v9 lockfile spec and ecosystem notes:
- `lockfileVersion` is ComVer starting with `9` (commonly `"9.0"`). Treat as string.
- `importers` is always present. For single-project repos, the importer is `"."` and holds `dependencies`, `devDependencies`, `optionalDependencies` for the root project.
- `packages` contains package metadata and `resolution` info (integrity, tarball, git info). Keys are canonical package IDs (generally `name@version`), not v5-style `"/name/version"` paths.
- `snapshots` contains the dependency graph. Keys are dependency paths, which can include peer qualifiers, e.g. `react-dom@18.2.0(react@18.2.0)`. Each snapshot lists `dependencies`, `optionalDependencies`, `peerDependencies`, etc., per edge context.

Implications:
- Root deps must be read from `importers["."]` instead of top-level fields.
- The dependency graph must be constructed from `snapshots` entries instead of reading static `dependencies` embedded on `packages` entries.
- Package metadata (including `resolution`) should come from `packages`.
- Peer-qualifier suffixes in snapshot keys should inform context-specific dependency edges but should not create distinct package metadata objects.

### Proposed architecture: introduce a versioned lockfile normalizer to a common IR

Introduce a small, focused layer that converts any supported pnpm lockfile version into a single internal representation (IR) consumed by the existing graph-rewrite code. Keep all non-format-specific logic (peer resolution, DAGification, cycle breaking) unchanged as much as possible.

Target IR (backed by current expectations in `pnpmlock.nix`):
- `packages`: attrset keyed by normalized package keys `"/name/version"`, each value containing at least:
  - `pname`, `version`, `name` (derivation name, kept as today),
  - `resolution` (with `integrity` or `tarball`/git fields),
  - `dev` (if available), `engines`, and raw maps `peerDependencies`, `dependencies`, `optionalDependencies` (later resolved to attribute names),
  - `constituents` initially set to `[ key ]`.
- `dependencies`, `devDependencies`, `optionalDependencies`: lists of normalized package attribute names representing root selections (after version resolution against available packages as today).
- `registry` if stated.
- `lockfileVersionMajor` and optionally `rawLockfileVersion`.

Files/modules to add:
- `lockfile/normalize-v5.nix`: identity-ish adapter from v5/v5.1 to IR.
- `lockfile/normalize-v9.nix`: adapter from v9 to IR (details below).
- `lockfile/normalize.nix`: dispatcher that inspects `raw.lockfileVersion` and calls the appropriate normalizer.

Minimal integration changes:
- Replace direct use of `import ./pnpmlock.nix` in `default.nix` with a two-step pipeline: normalize to IR, then run the existing `rewriteGraph` from `pnpmlock.nix` (which can be factored to accept the IR).
- Relax the version assertion in `default.nix` to accept the normalized IR’s `lockfileVersionMajor` in a supported set.
- In `pnpmlock.nix`, remove the workspace hard-fail guard and instead make it the responsibility of the normalizer to either:
  - reject multi-importer projects for now, or
  - select/importer `"."` only (single-project mode) and embed an explanatory field (see “Workspaces” below).

### normalize-v9: mapping details

1) Version detection and roots
- Read `raw.lockfileVersion` as string. Compute `lockfileVersionMajor` by taking the substring before the first `.` (if present) and converting to int; accept `9`.
- Read root dependencies from `raw.importers.".".{dependencies,devDependencies,optionalDependencies}`. If multiple importers exist, see “Workspaces”.

2) Package metadata
- Iterate `raw.packages` and build a map from canonical package IDs to metadata. For IR key stability and compatibility with today’s code, compute a normalized key `"/name/version"` per entry:
  - Parse `name` and `version` from the package ID (left of the first `@` that separates the name from version; keep scopes, e.g. `@scope/pkg`).
  - Populate IR package object: `rawPname` (original), `pname` (respect `name` override if present), `version`, `name` (derivation name `pname-version`), `resolution`, `engines`, etc. Set `constituents = [ key ]` and initialize `dependencies = []`, `optionalDependencies = []`, `peerDependencies = {}` (to be filled from snapshots).

3) Dependency graph (snapshots)
- Iterate `raw.snapshots` (the dependency paths). For each snapshot:
  - Compute the corresponding IR package key by stripping peer qualifiers from the snapshot key to get `name@version`, then normalize to `"/name/version"`.
  - Merge dependency edge information from the snapshot into the IR package entry:
    - Record raw dependency maps: `dependencies`, `optionalDependencies` (by name -> spec). Do not pre-resolve here.
    - Keep `peerDependencies` (and consider `peerDependenciesMeta.optional` to mark optional peers; optional peers should not cause resolution failures).
  - Note: a single package may have multiple snapshots with different peer contexts. For IR, persist the union of dependency name/spec constraints; disambiguation to actual attribute-name edges happens in the existing peer/dependency resolution step using semver and the package set.

4) Top-level dependency specifiers
- The IR expects top-level lists of resolved attribute names, but the current code already resolves maps to lists later. Keep the IR root dependency maps as read from the importer and let the existing `resolveDependencies` pipeline transform them (or implement a small helper mirroring v5 behavior).

5) Special sources
- Preserve `link:` specifiers unchanged (existing code already treats `link:` specially in cycle breaking and linking logic).
- Preserve git and tarball info exactly under `resolution`.

6) Registry
- Pass through `raw.registry` if present. If missing, default to `https://registry.npmjs.org/` at the same point the v5 path does today.

### Adjustments in existing modules

Small, targeted changes only:

- `default.nix`
  - Replace strict v5 assertion with: assert `(pnpmlock.lockfileVersionMajor == 5 || pnpmlock.lockfileVersionMajor == 9)`; store both the raw and major version in passthru for debugging.
  - Introduce `normalize = import ./lockfile/normalize.nix { inherit pkgs lib; };` and compute `normalized = normalize lock;` before calling the graph rewrite step.
  - Keep the remainder (derivation creation, wrapping, fetching, etc.) unchanged.

- `pnpmlock.nix`
  - Factor the pipeline into a pure function `rewriteGraph` that takes the IR shape described above. Most of the current content already operates on the expected IR; only the initial “workspace unsupported” guard should be removed. The normalizer will handle importers.
  - Keep: `injectNameVersionAttrs`, `resolvePackagePeerDependencies`, `resolvePackageDependencies`, `resolveDependencies`, and `breakCircular` logic. These operate on the IR equally for v5 and v9.

No functional changes in:
- `derivation.nix`, `overrides.nix`, `semver.nix`, or build/link phases; they operate after normalization/rewrite.

### Workspaces (importers)

Short-term (initial v9 support):
- Support single-importer projects only. If `raw.importers` contains more than `"."`, the normalizer should fail with a clear error: multiple importers/workspaces are not yet supported by pnpm2nix vX.Y.
- This matches current behavior (which already throws on `importers` presence) but upgrades single-project v9 lockfiles from hard-fail to supported.

Medium-term (optional follow-up):
- Extend the normalizer to emit a list of importers and their root dependency sets in the IR, and teach `default.nix` to build a derivation per importer or a meta-derivation that wires them together. This will unlock multi-package workspaces on both v5/v9 with near-identical logic.

### Peer dependency handling in v9

The existing `resolvePackagePeerDependencies` uses `semver.satisfies` to match peers across the package set, then stores resolved attribute-name edges. This remains valid for v9 because:
- Snapshot keys encode peer contexts, but package metadata remains peer-agnostic. Using the union of peer dependency specs per package and resolving by semver against the package set yields stable resolutions identical to what v5 produced.
- Optional peers (`peerDependenciesMeta`) should be ignored if no satisfying package exists. Add a small guard in normalization to mark optional peers (e.g., store a `peerOptional` set per package) so that `resolvePackagePeerDependencies` can skip failing when no match is found for optional peers.

### Backward compatibility and defaults

- v5/v5.1 lockfiles should continue to parse through `normalize-v5` as a no-op adapter and produce the same IR as today.
- Default registry behavior and `allowImpure` semantics remain unchanged.
- Top-level `dependencies`/`devDependencies`/`optionalDependencies` lists after rewrite should match existing tests.

### Testing plan

Add new fixtures under `tests/` for v9:
- Minimal single-package project with `importers: { ".": { dependencies } }`, a couple of dependencies, and a small `snapshots` graph.
- Peer-dependency scenario where a package has peers and a peer-qualified snapshot path exists.
- `link:` local dependency project.
- Git/tarball resolution case.

Tests to add:
- A normalization golden test (serialize IR to JSON and compare) for one or two fixtures to lock down the mapping.
- Existing test suites should run unchanged; add parallel v9 versions where relevant (e.g., `test-peerdependencies`).

### Implementation checklist

- Create `lockfile/normalize.nix` with version dispatch and helpers to parse `lockfileVersion` (string/number robustness).
- Create `lockfile/normalize-v5.nix` as an identity-ish adapter that:
  - Copies `packages` and top-level dep maps as-is; ensures all required IR fields exist; sets `lockfileVersionMajor = 5`.
- Create `lockfile/normalize-v9.nix` that:
  - Reads importer roots from `importers."."`.
  - Builds IR `packages` by transforming `raw.packages` keys to `"/name/version"` and passing through `resolution` and metadata.
  - Merges dependency maps from `snapshots` into per-package raw dependency maps.
  - Optionally extracts `peerDependenciesMeta` to note optional peers.
  - Sets `registry` and version fields.
- Refactor `pnpmlock.nix` to expose `rewriteGraph` and remove the importers guard.
- Update `default.nix` to call normalize → rewrite, and relax the version assertion to operate on `lockfileVersionMajor`.
- Add tests and fixtures.

### Risks and mitigations

- Snapshot key parsing (peer-qualified paths) can be tricky. Mitigate by keeping parsing minimal: strip peer suffix `(…)` when creating the metadata key, but do not attempt to fully interpret the peer context in the normalizer. Let the existing semver-based peer resolver pick winners.
- Mixed importer/workspace projects: explicitly unsupported initially, with a clear error and a tracked follow-up task to add support.
- Integrity/URL fields: preserve exactly; keep current fetching logic and `allowImpure` behavior.

### Suggested cleanups and reorganizations (non-functional)

- Split `pnpmlock.nix` into:
  - `lockfile/rewrite-graph.nix` (current `rewriteGraph` pipeline),
  - `lockfile/keys.nix` (small helpers for key normalization like `"/name/version"`),
  - `lockfile/resolve.nix` (peer/dependency resolution helpers),
  for readability and to decouple version-specific from version-agnostic logic.
- Introduce a lightweight logging/diagnostic toggle to dump the IR when an error occurs, easing debugging for new lockfile versions.
- Document the IR in `docs/ir.md` with examples (small JSON snippets) to make future upgrades straightforward.

### Acceptance criteria

- Projects with pnpm `pnpm-lock.yaml` v5/v5.1 continue to build unchanged.
- Projects with pnpm `pnpm-lock.yaml` v9.0 (single importer) build successfully, including cases with peers, `link:`, and git/tarball packages.
- New tests cover normalization for v9 and pass in CI.

### Appendix: Implementation plan

Step 0: Repo scaffolding
- Create directory `lockfile/`.
- Add placeholders for `lockfile/normalize.nix`, `lockfile/normalize-v5.nix`, `lockfile/normalize-v9.nix` and wire them in `default.nix` later.

Step 1: Factor pnpmlock rewrite into a callable function
- In `pnpmlock.nix`, export a function `rewriteGraph` that takes the IR (as described) and returns the rewritten object; this is already the file’s return value, so only ensure it doesn’t throw on `importers`.
- Remove the importers guard; it will be handled by the normalizers.

Step 2: Implement normalize-v5
- Input: raw v5/v5.1 lockfile JSON.
- Output IR:
  - Copy `packages` into IR `packages`, ensuring each entry minimally has `pname`, `version`, `resolution`, and `constituents = [ key ]`.
  - Copy top-level dependency maps; compute `lockfileVersionMajor = 5`.
  - Pass through `registry` when present.
- Add unit test: feed current test fixtures through normalize-v5 and assert the IR shape matches what `pnpmlock.nix` expects today.

Step 3: Implement normalize-v9
- Input: raw v9 lockfile JSON.
- Validate `importers` contains exactly `"."`; otherwise, throw a clear error (temporary workspace limitation).
- Build IR `packages` by transforming `raw.packages` keys from `name@version` to `"/name/version"` and copying metadata including `resolution`.
- Iterate `snapshots` and merge dependency maps into the corresponding IR package entries. When the snapshot key has peer qualifiers `(…)`, strip them to identify the base `name@version` for mapping to the IR key.
- Read root dependency maps from `importers."."`.
- Set `lockfileVersionMajor = 9`, pass `registry` when present.
- Add unit tests with small v9 fixtures validating mapping and a case with peer-qualified snapshot keys.

Step 4: Version dispatcher
- Implement `lockfile/normalize.nix` that inspects `raw.lockfileVersion` (string or number), derives `major`, and delegates to v5 or v9 normalizers. Include a helpful error for unsupported versions.

Step 5: Wire into default.nix
- Replace direct `rewritePnpmLock lock` with `normalize lock` followed by invoking `rewriteGraph`.
- Relax the assertion to the normalized IR: assert major in `{5,9}`.
- Expose `rawLockfileVersion`/`lockfileVersionMajor` in passthru for debugging if useful.

Step 6: Tests and fixtures
- Duplicate a few existing v5 tests as v9 versions by regenerating minimal `pnpm-lock.yaml` v9 fixtures that correspond semantically to the v5 ones (peers, link, git/tarball).
- Add a golden test that dumps the normalized IR for a small v9 project to ensure stability.
- Ensure existing v5 tests pass unchanged.

Step 7: Follow-ups (optional)
- Workspace support: extend normalize-v5/v9 to handle multiple importers; teach `default.nix` to build per-importer outputs.
- Diagnostics: add a `PNPM2NIX_DEBUG_IR` toggle to dump IR on failure.
- Refactors: split `pnpmlock.nix` into `rewrite-graph.nix`, `resolve.nix`, `keys.nix` per “Suggested cleanups”.

### Appendix: relevant code citations

Assertion on v5/v5.1 only in `default.nix`:

```200:206:default.nix
  in
    assert (pnpmlock.lockfileVersion == 5 || pnpmlock.lockfileVersion == 5.1);
  (mkPnpmDerivation {
    deps = (builtins.map
      (attrName: packages."${attrName}")
      (pnpmlock.dependencies ++ pnpmlock.optionalDependencies));
```

Workspace/importers hard-fail in `pnpmlock.nix`:

```251:255:pnpmlock.nix
    # Recursive workspaces are currently unsupported
    (pnpmlock: (
      if lib.hasAttr "importers" pnpmlock
      then (throw "Workspaces currently unsupported. This is a regression from pnpm 2.x.")
      else pnpmlock))
```

Internal shape used by the graph rewrite:

```11:21:pnpmlock.nix
# After rewriting you end up with a datastructure that looks like (JSON):
# {
#   "dependencies": [ "/yargs/8.0.2" ],
#   "devDependencies": [],
#   "optionalDependencies": [],
#   "packages": {
#     "/camelcase/4.1.0": {
#       "constituents": [ "/camelcase/4.1.0" ],
#       "dependencies": [],
```


