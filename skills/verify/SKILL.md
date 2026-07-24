---
name: verify
description: Run a verification pass on the vault's repo pages — confirm a page's content is actually CORRECT against the repo at its recorded sha (freshness only proves nothing changed since ingest, never that the page was right), fix any drift found (and the SOURCE repo if the drift originated there), then stamp the `verified:` correctness signal. Use when the user says "run a verification pass", "verify the <X> repo page", "verify the repo pages", "drain the verify queue", "confirm this page is still accurate/correct", or after `verify-status.sh` / `upkeep.sh` flags unverified or verified-stale pages. Distinct from `wiki-repo` (which re-ingests when the sha MOVED — a freshness refresh) and `checkpoint` (session curation): verify confirms CORRECTNESS at the current sha and records who checked it, on what date.
status: active
summary: verification pass — confirm a repo page correct against its sha, fix drift at the source, stamp verified.
updated: 2026-07-24
used_by: []
---

# verify — run a verification pass

Freshness and correctness are different axes. A repo page is *fresh* when its recorded `sources.sha` still matches the repo's `HEAD` — but that only proves **nothing changed since ingest**, not that the page was **ever accurate**. A page can be perfectly fresh and wrong. This skill closes that gap: read the actual repo, confirm the page's claims, fix what drifted, and record that a human or agent confirmed it — the `verified:` signal (see `engine/SCHEMA.md`).

## When to use — and when not

- **Use** for a `repos/` page flagged unverified or verified-stale (by `verify-status.sh`), for the `verify:*` items in the upkeep queue, or for a direct "is this page still right?" request.
- **Not** for a page whose sha has *moved* (recorded `sources.sha` ≠ repo `HEAD`) — that is a **freshness** problem: run **`wiki-repo`** to re-ingest first. If a page is *both* stale and wrong, refresh with `wiki-repo`, then verify the refreshed content.
- **Not** for project/memory/concept pages — verification targets version-keyed `repos/` pages, which have an objective sha to check against. (A non-repo page may carry a `verified:` block opt-in, but it's not queue work.)

## Inputs

- **Target**: a repo page slug, or nothing → drain the whole verify work-list.
- **`$WIKI_PATH`** (the vault) and a **local clone** of the repo (default `$UPKEEP_REPOS_ROOT/<repo>`, i.e. the vault's sibling repos dir).

## Steps

1. **Find the work** — `engine/bin/verify-status.sh --todo` (or `upkeep.sh scan` then `upkeep.sh next`). Each line is a `repos/<slug>.md` needing a pass.
2. **Confirm the anchor sha** — compare the page's `sources.sha` with the clone's `git rev-parse --short HEAD` (tagged repos: `git describe --tags`).
   - **sha moved** → freshness, not verification: run **`wiki-repo`** to refresh (bumps the sha), *then* verify the refreshed page.
   - **sha matches** → verify at that sha; you're confirming the page against exactly what it claims to describe.
3. **Read the page and the real repo** at that sha. Check every substantive, checkable claim: directory/path structure, version pins, commands, counts, config keys, group/app/role names, external interfaces. Read the README, manifests, and the dirs the page describes; sample deeper as needed — do **not** dump file contents.
4. **On drift, fix it — and fix the source.** Correct the vault page to match reality. If the drift originated in the **source repo** (e.g. the repo's own README is wrong), fix the source too and open a PR — otherwise the next `wiki-repo` re-ingests the same error (the *fix-at-source* rule). A correction that only re-aligns the page to the **same** sha keeps `sources.sha` unchanged; only a genuine re-ingest of newer content bumps it (that's `wiki-repo`, not this).
5. **Stamp `verified:`** in the page frontmatter — **only after genuine confirmation**:
   ```yaml
   verified:
     date: <today>
     by:   <preston | claude | whoever confirmed>
     against: <sources.sha>   # MUST equal sources.sha, or it reads as stale
   ```
6. **Close out** — `engine/bin/upkeep.sh done verify:<slug>`; run `verify-status.sh` to confirm the page now shows ✓; run `engine/bin/lint.sh` (the gate). Commit the changed page(s) with a `log.md` entry stating **what was checked** and **any drift fixed** (link the source-repo PR if you opened one).

## Rules (non-negotiable)

- **Only stamp what you actually confirmed.** An unchecked stamp is worse than no stamp — it launders a guess as evidence and poisons the signal. If you can't confirm a page (no context, can't reach the repo), **leave it unverified and say so**.
- **`against` must equal `sources.sha`.** A later `wiki-repo` refresh that bumps the sha auto-demotes the stamp to *stale* — invalidation-by-provenance, the intended behavior; don't work around it.
- **Fix drift at the source.** Correcting only the vault page leaves the repo's own docs wrong, so the next re-ingest reintroduces it — see the *ingest-drift-fix-at-source* lesson.
- **Judgment is yours; mechanics are the tools'.** `verify-status.sh` / `upkeep.sh` / `lint.sh` find the work and record the result deterministically (no `claude`, no network); deciding *is it correct?* is the human/agent's job.

## Example — homelab (2026-07-24)

`verify-status` said the `homelab` page was fresh (clone HEAD == recorded `abebc5d`), but reading the repo showed the page listed a **nonexistent `kubesystem` Argo app** and **omitted the `kube_vip`/`longhorn` roles** — both inherited from the repo's own stale README. Fixed the vault page *and* opened a PR on the source README, then stamped `verified: against abebc5d`. Textbook case: fresh, yet wrong — the exact gap this pass exists to catch.
