# GitHub / CI

## Status as of Sprint 0.5

* Repository: `https://github.com/abdullawagih1/NOOR` — public, `main` is
  the default branch.
* Pushed for the first time this session (it was confirmed empty
  beforehand via `git ls-remote`).
* `.github/workflows/pr.yml` triggers on `pull_request` (main/develop) and
  `push` (main) — the push trigger was added this session specifically so
  a direct push to `main` (no PR) still produces a real CI run to point to.
* **CI has actually run and passed on GitHub Actions** — not just
  YAML-validated locally. Confirmed green runs:
  `https://github.com/abdullawagih1/NOOR/actions/runs/29998063629`
  (commit `e13d4682`) and
  `https://github.com/abdullawagih1/NOOR/actions/runs/30000512766`
  (commit `e635adbc`, includes the Next.js 15 upgrade), both 5/5 jobs:
  `Web`, `Clinical schemas`, `Worker`, `Supabase (migrations + RLS)`,
  `Secret scan`.

## Jobs

| Job | What it proves |
|---|---|
| `secret-scan` | gitleaks over the full git history — added this session |
| `web` | `npm ci` (root) → lint/typecheck/test/build for `apps/web`, workspace-scoped |
| `clinical-schemas` | typecheck + contract tests for `packages/clinical-schemas` |
| `worker` | `py_compile` + pytest for `apps/worker` |
| `database` | applies all 3 migrations + seed to a plain `postgres:16` service container, runs both RLS test files (11 assertions) |

## The npm-workspaces lockfile fix (this session)

`npm ci` run with `working-directory: apps/web` silently resolves to the
**root** `package-lock.json` (npm walks up to find the `workspaces` field
regardless of cwd) — the per-app lockfiles that existed before this session
were never actually read by npm. Fixed: removed them, changed both Node
jobs to `npm ci` once at the repo root, then use `--workspace=<path>` for
every subsequent script. `cache-dependency-path` in `actions/setup-node`
now correctly points at the root lockfile too.

## Branch protection (recommendation, not yet applied)

Not configured this session — recommend, once a second contributor exists:

* Require the 5 CI jobs above to pass before merge.
* Require at least one review before merge to `main`.
* Disallow force-push to `main`.

This wasn't applied because it's a repository-settings change beyond code,
and there's currently one contributor — revisit when that changes.
