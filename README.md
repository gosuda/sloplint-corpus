# sloplint-corpus (public)

Shared stability corpus for sloplint. This repository holds copied source
subsets of permissive-licensed open source projects, plus the tooling that
keeps the copies honest.

## What lives here

- `projects/<language>/<name>/`: one copied subset per project. Each holds
  the copied source files, the verbatim upstream `LICENSE` (or `COPYING`),
  the verbatim upstream `NOTICE` when the upstream ships one, and an
  `UPSTREAM.md` file with the source URL, pinned commit, retrieval date,
  license, subset, and reason for inclusion.
- `corpus.toml`: the index. One `[[project]]` entry per project with the
  pinned 40-hex commit, SPDX expression, storage mode, path subset, content
  hash, curator, date, and reason.
- `budgets.toml`: per-language stabilization gates (parse-error rates,
  wall time, zero panics).
- `reports/<language>.json`: the last measurement output, regenerated.
- `tools/corpus/corpus`: the tool. Python 3.11 or newer, standard library
  only, no network access in `verify`.

## License policy

Only these licenses may enter this repository: `MIT`, `Apache-2.0`, and OR
combinations whose every member is one of those two (for example
`MIT OR Apache-2.0`). Everything else is rejected here, including BSD,
ISC, Unlicense, CC0, MPL, EPL, GPL, LGPL, AGPL, source-available licenses,
and projects with no license. Those belong in the private corpus repository
`gosuda/sloplint-corpus-private`, never here in any form.

Each project directory keeps its own upstream license file. The license of
this repository's own files (tooling, manifests, workflows, this README) is
MIT; see `LICENSE`. Third-party code under `projects/` keeps its own
license and is not covered by that file.

## Adding a project

```sh
python3 tools/corpus/corpus add \
  --url https://github.com/example/libfoo \
  --rev 8f3c1a2b3c4d5e6f708192a3b4c5d6e7f8090a1b2 \
  --lang rust --spdx MIT --name libfoo \
  --paths 'src/**,tests/**' \
  --reason 'mid-size async runtime, pre-2020, library'
```

`add` clones at the pinned commit into scratch space, runs the gate on the
subset, copies only source files with allowlisted extensions, writes
`UPSTREAM.md`, copies the upstream license, records the content hash, appends
the entry to `corpus.toml`, and re-runs `verify`. Nothing is committed by the
tool. Open a pull request afterwards and paste the `verify` report into it.

## The gate

Every pull request runs `corpus verify --offline`. It fails closed on:

- an SPDX expression outside the allowlist, or a `storage = "pinned"` entry;
- a missing or unidentified project license (askalono 0.5.0, score below
  0.95, or a detected license outside the declared SPDX);
- a per-file header that names a license outside the allowlist, including
  GPL, AGPL, LGPL, MPL, EPL, and Creative Commons text;
- a missing `UPSTREAM.md`, `LICENSE`/`COPYING`, or a required `NOTICE`;
- nested license files that differ from the project license (vendored code);
- submodules, symlinks, binaries, generated files, secret patterns
  (token and key shapes), files above 1 MiB, projects above 50 MiB,
  languages above 500 MiB;
- a content hash mismatch, a non-40-hex rev, or a non-https URL.

If the `askalono` binary is missing from `PATH` (or `CORPUS_ASKALONO`), the
gate fails instead of skipping the license check.

## Measuring

```sh
python3 tools/corpus/corpus fetch --check
python3 tools/corpus/corpus measure rust
python3 tools/corpus/corpus seeds rust --out /path/to/seeds
python3 tools/corpus/corpus stats
```

`measure` runs the sloplint binary (`PATH` or `CORPUS_SLOPLINT`) with JSON
output over the language directory and writes an aggregate report with file
and byte counts, parse-error files and rates, panics, wall time, per-rule
finding counts, and deterministic samples for human review. Budget comparison
is skipped with a warning until a language has 3 projects.

## License detection

Primary detector: askalono 0.5.0, confidence threshold 0.95. Below the
threshold the license counts as unknown and the gate fails. The detector sits
behind one function (`detect_license_file` in `tools/corpus/corpus`) so a
second backend can be added later. ScanCode is the optional cross-check for
promotion reviews, not part of this gate. The corpus repository itself is
REUSE compliant (`reuse lint` passes); run the check with
`corpus verify --reuse` when the `reuse` binary is installed.
