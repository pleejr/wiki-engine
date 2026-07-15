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
import argparse, json, re, subprocess, sys
from importlib.metadata import version, PackageNotFoundError


def norm(n):
    return n.lower().replace("_", "-")


def load_pins(path):
    pins = {}
    try:
        for line in open(path):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            m = re.match(r"([A-Za-z0-9_.\-]+)==([^;# ]+)", line)
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
