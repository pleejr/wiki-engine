---
name: release
description: This skill should be used to cut a wiki-engine release from the engine repository — decide whether the change earns a tag, choose the SemVer level, write the CHANGELOG section, move the four version pins together, merge through CI, push the tag, and confirm the GitHub Release and marketplace pin landed. Consumers install a tag, so a bump that misses a pin ships a stale or unreleased tree under the new number. Triggers: "release the engine", "cut a release", "tag v2.9.0", "bump the engine version", "ship and tag this", "publish the new version", "the release workflow didn't run", "is this docs-only or does it get a tag". Distinct from `drain` (the outer loop over the whole queue; it calls this for its ship step) and `update` (consumer side — records a release in a vault; never cuts one). NOT for a docs-only change (lands untagged under Unreleased), NOT for a consumer vault's own versioning.
status: active
summary: cut an engine release — level, CHANGELOG, four pins, CI merge, tag, GitHub Release, verified.
updated: 2026-10-06
---

# release — cut one engine release

The engine reaches consumers as a **tag**: the marketplace pins the latest release tag, and a vault's `.engine-version` names the tag its CI checks out. So a release is only real when the tag, the manifests, the CHANGELOG and the GitHub Release all name one version. Deterministic steps only; never spawns `claude`.

**Where it runs**: the engine repository, `gh` authenticated, `main` clean and current, the change already on a branch or merged.

## 1. Decide whether it gets a tag

Tag only when the change touches what a consumer runs: `skills/`, `bin/`, `hooks/`, `SCHEMA.md`, `scaffold/`, the `CLAUDE.md` router, `LICENSE`. Anything else (`README`, `USAGE`, comments, CHANGELOG prose) lands on `main` untagged under `## [Unreleased]` and rides into the next functional release. Stop here for docs-only.

## 2. Choose the level

Use the CHANGELOG header's own rules. Take the current version from `bin/engine-version.sh --latest-tag`, not from memory.

- **PATCH** — backwards-compatible fix to a consumed component.
- **MINOR** — additive: a new skill, tool, knob, or changed behaviour. Consumers adopt with `bin/adopt.sh`.
- **MAJOR** — node removed or renamed, frontmatter schema change; needs a reviewed migration. Ask before proceeding; `update.sh` refuses it.

## 3. Write the CHANGELOG section

Add `## [X.Y.Z] — YYYY-MM-DD` above the previous release and fold any `[Unreleased]` entries into it.

- The first prose line opens `Patch —`, `Minor —` or `Major —` and is also the **release title**: `bin/release-title.sh` cuts it at the first clause boundary outside backticks, capped at 80 characters. Put the summary clause first. Preview with `printf '%s' "$section" | bin/release-title.sh`.
- Pass the prose through `bin/reflow.sh`: the soft-wrap lint is the usual first-push CI failure.
- Group under `### Added` / `### Changed` / `### Fixed`. State the failure shape for a fix (fail-closed, fail-open, data-loss) and what CI asserts, with the check that is red against the previous release.

## 4. Move the four pins together

`bin/lint-docs.sh` fails unless these name one release:

1. `.claude-plugin/plugin.json` — `version`
2. `.claude-plugin/marketplace.json` — `version`
3. `.claude-plugin/marketplace.json` — `source.ref`, as `vX.Y.Z`
4. the newest `## [X.Y.Z]` heading in `CHANGELOG.md`

The tag must land on the commit that carries all four, because a consumer installs that tag's tree and reads that tag's marketplace.

## 5. Fold this release's drift into this release

A release changes counts and docs. Update them now: a new skill needs a `USAGE.md` mention (a lint gate) and its `SCHEMA.md`/README listing; a changed script needs its description refreshed. Drift left for "next round" becomes the next release's defect.

## 6. Run the gates, then open the pull request

```bash
bin/lint-docs.sh && bin/lint-changelog-tags.sh && bin/lint-proposals.sh
```

Then push the branch and open a pull request. Commit subject: `type(scope): summary (X.Y.Z) (#N)`. If the work answers a proposal, cite `Proposal: <slug>` in the body. Stage explicit paths; never `git add -A`.

Wait for CI **by run status** (`gh run list --branch <branch>`, then `gh run watch`). `gh pr checks` printing "no checks reported" is usually dispatch lag, not an absent run. Merge only on green.

## 7. Tag the merged commit, one tag at a time

```bash
git switch main && git pull --ff-only
git tag -a vX.Y.Z -m vX.Y.Z
git push origin vX.Y.Z
```

Push tags singly. A push carrying more than three tags runs no workflows at all, with no error, and the Releases page silently falls behind. Confirm the tag points at the merge commit (`git rev-parse vX.Y.Z^{commit}` against `git rev-parse HEAD`) before pushing: a tag on the pre-merge branch tip omits the squash.

## 8. Verify the release is live

An accepted push is not a published release. Read each surface:

```bash
gh run list --workflow release --limit 1        # the workflow ran for this tag
gh release view vX.Y.Z --json name,body | head  # title and notes came from the CHANGELOG
bin/engine-version.sh --latest-tag              # the remote's newest tag is vX.Y.Z
```

Never `gh release create` after the push. The workflow skips a release that already exists, so a hand-made one wins the race and keeps a bare title instead of the derived `vX.Y.Z — <summary>`. If no release exists, dispatch it: `gh workflow run release.yml -f tag=vX.Y.Z`. It skips an existing release, so a rerun is harmless. If `lint-changelog-tags.sh` reds on a later PR, a heading shipped without its tag; cut that tag before anything else.

## 9. Hand the adoption off

Cutting the release does not move any consumer. In the consuming vault, `$WIKI_PATH`, run the `update` skill (`update.sh` records the new tag in `.engine-version`), commit the pin, and re-verify pages the release made stale (`verify-status.sh`). A MAJOR stops there for a reviewed migration.

## Boundaries

- In-session and human-initiated; the loop merges, tags and publishes, so it never runs from a lifecycle hook (engine `CLAUDE.md`, Hard safety rule).
- Never retag a published version. A bad release gets a new PATCH, because consumers and the Releases page have already recorded the old tag.
- Never force-push `main` or move a tag.
