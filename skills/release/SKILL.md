---
name: release
description: This skill should be used when cutting a wiki-engine release in the engine repository — deciding whether a change earns a tag, choosing the SemVer level, bumping `plugin.json` and `marketplace.json` together, writing the CHANGELOG section, merging, pushing the annotated tag, and confirming the GitHub Release and the consuming vault's pin. Produces a released, adopted version with its evidence, or a docs-only change left untagged under `[Unreleased]`. Triggers: "cut a release", "release the engine", "tag and release", "ship 2.9.0", "bump the engine version", "is this worth a tag", "write the changelog entry", "the release didn't publish", "release workflow didn't fire". Distinct from `drain` (the outer queue loop, which calls this for its ship step) and `update` (advances a machine and vault to an already-released tag) — this one creates the tag. NOT for a consumer vault's own release, and NOT for a MAJOR/breaking bump, which needs a reviewed migration first.
status: active
summary: cut one engine release — tag decision, SemVer level, paired version bump, CHANGELOG, merge, annotated tag, GitHub Release, vault pin.
updated: 2026-10-06
---

# release — cut one engine release, and prove it landed

The engine is consumed by installing a **tag**: the marketplace pins the latest release tag and a vault's `.engine-version` names the tag its CI checks out. A release is therefore not done at merge. It is done when the tag exists on the remote, the GitHub Release exists, and a consumer resolves to it.

**Where it runs**: the engine repository, `gh` authenticated, `main` clean. In-session and human-initiated — never from a lifecycle hook (engine `CLAUDE.md`, Hard safety rule). Solo repo: ship without asking, except at the MAJOR stop in §2.

## 1. Does this change earn a tag?

Tag only when the diff touches what a consumer runs: `skills/`, `bin/`, `hooks/`, `SCHEMA.md`, `scaffold/`, the `CLAUDE.md` router, `LICENSE`. Docs-only changes (`README`, `USAGE`, comments, `CHANGELOG` prose) and CI-only changes land on `main` untagged, noted under `## [Unreleased]`, and ride into the next functional release.

```sh
git diff --stat "$(git describe --tags --abbrev=0)"..main   # what a consumer would newly run
```

A tag with nothing consumer-visible makes every vault see an update that changes nothing.

## 2. Choose the level

Use the CHANGELOG header's own rules.

- **PATCH** — backwards-compatible fix to a consumed component.
- **MINOR** — additive: a new skill, tool, knob, or a component that changes what it does.
- **MAJOR** — a node removed or renamed, or a frontmatter-schema change. **Stop and report**: it needs a dedicated idempotent migration shipped with it, and `update.sh` refuses to cross a MAJOR silently.

When a change is both a fix and a feature, take the higher level. `engine-version.sh` classifies bumps from the tag names, so a wrong level misleads every consumer's report.

## 3. Prepare the release commit

Work on a branch, in a worktree. One commit carries all of:

1. **`.claude-plugin/plugin.json`** — `version`.
2. **`.claude-plugin/marketplace.json`** — `version` **and** `source.ref` (`vX.Y.Z`). Bumping one without the other leaves the marketplace advertising a tag that is not the one the plugin claims. Confirm all three agree:
   ```sh
   jq -r .version .claude-plugin/plugin.json
   jq -r '.plugins[0].version, .plugins[0].source.ref' .claude-plugin/marketplace.json
   ```
3. **`CHANGELOG.md`** — a new `## [X.Y.Z] — YYYY-MM-DD` section above the newest, opening with one prose line `Patch|Minor — <summary>.` (`release-title.sh` takes the GitHub Release title from that first prose line, cut at the first clause boundary outside a code span, so lead with the summary, not a bullet or a bold lead-in). Then `### Added / Changed / Fixed`, each entry naming the **mechanism** and its measured evidence. Fold any `## [Unreleased]` items into the section and remove the heading.
4. **Drift the release itself causes** — counts and tables in `SCHEMA.md` / `USAGE.md` / `README.md`, and a `PROPOSALS.md` ledger regenerated with `bin/gen-proposals-ledger.sh` when a proposal's status changed. Fold these in now; leaving them to be found next cycle is how one release becomes three.
5. **A `Proposal: <slug>` line** in the commit body for each proposal the release resolves.

Run the gates before pushing: `bin/lint-docs.sh && bin/lint-proposals.sh && bin/lint-changelog-tags.sh`.

Commit title: `<type>(<scope>): <what changed> (X.Y.Z)`. Stage explicit paths — never `git add -A`.

## 4. Merge, then tag the merge commit

1. Open the pull request; wait for CI **by run status** (`gh run list --branch <branch>`), not by `gh pr checks`, which reports "no checks" during dispatch lag.
2. Squash-merge. Pull `main` and confirm `HEAD` is the merge commit and its tree carries the bumped `plugin.json`.
3. Tag **that commit**, annotated, then push the tag **by itself**:
   ```sh
   git tag -a vX.Y.Z -m vX.Y.Z
   git push origin vX.Y.Z
   ```
   Never `git push --tags` or push several tags together. GitHub runs no workflows for a push carrying more than three tags, so `release.yml` silently never fires; every tag exists, nothing is red, and the Releases page falls behind.

## 5. Verify the release exists — accepted is not live

A pushed tag is an acknowledgment, not a release. Read each surface from its own source:

```sh
gh run list --workflow release --limit 1                 # fired for this tag, and succeeded
gh release view vX.Y.Z --json tagName,name,body          # exists; title and notes from the CHANGELOG section
git ls-remote --tags origin vX.Y.Z                       # tag on the remote, not just local
bin/engine-version.sh --latest-tag                       # the engine's own answer: X.Y.Z
```

If the release workflow did not fire, recover with `gh workflow run release.yml -f tag=vX.Y.Z`. It is idempotent and skips an existing release. Do not create the release by hand: the hand-written one drifts from `release-title.sh`.

If the title reads wrong, the fault is in the CHANGELOG's first prose line, not the workflow. Fix the line in a follow-up; do not retag.

## 6. Adopt into the consuming vault

A release is finished when a consumer has it. With `$WIKI_PATH` pointing at the vault, run the `update` skill (`bin/update.sh`), commit the new `.engine-version` pin, then `bin/doctor.sh` to confirm the vault is current and `bin/verify-status.sh` for pages the release made verified-stale. Re-verify those; the version bump demotes their stamps.

## Rules

- **Never move a published tag.** A consumer may already have installed it. A bad release gets a new PATCH, not a force-push.
- **One release at a time.** Finish §6 before starting the next version.
- **Never weaken a gate to land a release.** A red lint is a finding; fix the cause.
- **State the result with the commands' output**: tag, release URL, `--latest-tag`, `doctor.sh` line. A release reported from memory of having pushed is a claim, not a result.
