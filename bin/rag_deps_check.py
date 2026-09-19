# rag_deps_check.py — RAG dependency freshness/health, shared by doctor.sh and the
# freshness CI cron so both agree on what counts as "actionable".
#
# Actionable (exit 1): a PINNED dep (rag-requirements.txt) has drifted from its pin or
# has a newer release, OR pip-audit finds a known vulnerability anywhere in the tree.
# Transitive "newer available" with no vuln is INFORMATIONAL only — shown, never alerts,
# so the signal doesn't rot into steady-state noise.
#
# Exit: 0 healthy · 1 actionable · 2 could-not-check (offline / pip error).
# Usage: python rag_deps_check.py --requirements PATH
import argparse, json, os, re, subprocess, sys
from importlib.metadata import version, PackageNotFoundError


def installed_copy(req_path):
    """True when the requirements file is the plugin's INSTALLED copy, not an engine checkout.

    Both callers print the same drift, and only one of them can act on it. In an engine
    checkout `rag-requirements.txt` is an ordinary tracked file and "bump it" is the whole
    remedy; in the plugin cache (`.../plugins/cache/...`, not a git repo) an edit has no
    durable home — the next plugin update replaces the whole tree, and no other machine
    ever sees it. Detected from the path rather than configured, so the CI cron (an engine
    checkout) keeps the wording that is right for it without either caller passing a flag.
    """
    d = os.path.dirname(os.path.realpath(req_path))
    return "%splugins%scache%s" % (os.sep, os.sep, os.sep) in d + os.sep


def norm(n):
    return n.lower().replace("_", "-")


def _marker_ok(marker):
    """Evaluate a `python_version <op> "X.Y"` environment marker against the running
    interpreter (doctor.sh runs this with the vault's venv Python). Only the operators
    we use in rag-requirements.txt are supported; an unrecognized marker is not filtered
    (conservative — better a spurious check than a silently dropped pin)."""
    if not marker:
        return True
    m = re.match(r'python_version\s*(<=|>=|==|!=|<|>)\s*["\']([0-9]+(?:\.[0-9]+)*)["\']',
                 marker.strip())
    if not m:
        return True
    op, want = m.group(1), tuple(int(x) for x in m.group(2).split("."))
    cur = tuple(sys.version_info[:len(want)])
    return {"<": cur < want, "<=": cur <= want, ">": cur > want,
            ">=": cur >= want, "==": cur == want, "!=": cur != want}[op]


def load_pins(path):
    pins = {}
    try:
        for line in open(path):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            req, _, marker = line.partition(";")
            if not _marker_ok(marker):
                continue  # pin for a different Python bucket — skip on this interpreter
            m = re.match(r"([A-Za-z0-9_.\-]+)==([^;# ]+)", req)
            if m:
                pins[norm(m.group(1))] = m.group(2)
    except FileNotFoundError:
        pass
    return pins


def pip_outdated():
    r = subprocess.run([sys.executable, "-m", "pip", "list", "--outdated", "--format=json"],
                       capture_output=True, text=True)
    if r.returncode != 0:
        return None
    try:
        return json.loads(r.stdout or "[]")
    except Exception:
        return None


def run_audit(req):
    """Return (available, [vuln strings]). Audits the requirements closure (the RAG
    stack), not the whole environment — so it never reports vulns in the audit tool's
    own deps, only in what the vault actually runs."""
    if subprocess.run([sys.executable, "-c", "import pip_audit"],
                      capture_output=True).returncode != 0:
        return (False, [])
    r = subprocess.run([sys.executable, "-m", "pip_audit", "-r", req, "--format", "json"],
                       capture_output=True, text=True)
    try:
        data = json.loads(r.stdout or "{}")
    except Exception:
        return (True, [])
    deps = data.get("dependencies", data) if isinstance(data, dict) else data
    vulns = []
    for d in deps or []:
        for v in (d.get("vulns") or d.get("vulnerabilities") or []):
            vulns.append("%s %s (%s)" % (d.get("name"), d.get("version"), v.get("id", "?")))
    return (True, vulns)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--requirements", required=True)
    args = ap.parse_args()
    pins = load_pins(args.requirements)
    actionable = False

    # 1. drift: installed != pinned (you bumped the pin but didn't re-provision)
    drift = []
    for name, want in pins.items():
        try:
            have = version(name)
        except PackageNotFoundError:
            have = None
        if have != want:
            drift.append("  %s: pinned %s, installed %s" % (name, want, have))
    if drift:
        actionable = True
        print("pinned deps drifted from rag-requirements.txt (run rag-setup.sh):")
        print("\n".join(drift))
    else:
        print("pinned deps: installed versions match the pins")

    # 2. newer releases — split pinned (actionable) vs transitive (informational)
    data = pip_outdated()
    if data is None:
        print("could not reach PyPI (offline?) — skipped the newer-release check")
        return 2 if not actionable else 1
    mine, other = [], []
    for p in data:
        line = "  %s: %s -> %s" % (p["name"], p["version"], p["latest_version"])
        (mine if norm(p["name"]) in pins else other).append(line)
    if mine:
        actionable = True
        if installed_copy(args.requirements):
            print("pinned deps with newer releases (raise upstream — see below):")
            print("\n".join(mine))
            print("  rag-requirements.txt here is the wiki-engine plugin's installed copy, so editing it")
            print("  has no durable home: the next plugin update replaces it and no other machine gets it.")
            print("  Route it upstream instead (the engine-proposal skill), or bump it in an engine")
            print("  checkout and cut a release; the plugin update then brings it here.")
        else:
            print("pinned deps with newer releases (bump rag-requirements.txt):")
            print("\n".join(mine))
    else:
        print("pinned deps: current (no newer releases)")
    if other:
        print("transitive newer releases (informational — not pinned, no action needed):")
        print("\n".join(other))

    # 3. security — a vuln anywhere is actionable, pinned or transitive
    available, vulns = run_audit(args.requirements)
    if not available:
        print("security: pip-audit not installed — skipped (the CI cron runs it)")
    elif vulns:
        actionable = True
        print("SECURITY — known vulnerabilities (fix regardless of pin):")
        for v in vulns:
            print("  " + v)
    else:
        print("security: no known vulnerabilities")

    return 1 if actionable else 0


if __name__ == "__main__":
    sys.exit(main())
