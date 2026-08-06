# rag_chunk.py — the single chunker for the RAG layer (used by rag-build.sh).
#
# Splits a markdown page into embeddable chunks, each carrying the 1-based line it
# starts at, so recall returns a pointer back into the real page.
#
# Why this is a module and not inline in rag-build.sh: the old split assumed every
# page carries `##` headings. A page that does not — a flat `log.md`, one `# Log`
# and 233k characters of bullets — became ONE chunk, which the embedder then
# truncated to MAX_CHARS. So ~97% of the page was unindexed while the record still
# carried the whole file's sha and the reuse check reported it current: recall
# claimed coverage it did not have. The split is now recursive and bounded by the
# embedder's own limit, and it lives here so CI can exercise it with plain python3,
# no model and no network.
#
# Split order, widest structure first, so a chunk boundary lands somewhere a reader
# would also have broken the page:
#   `## ` section  ->  `### ` subsection  ->  whole-line size packing  ->  hard slice
# Only the last of those can split mid-line, and only for a single line longer than
# the entire budget.
import hashlib, os

from rag_embed import MAX_CHARS

# Bump when the split changes shape. Records carry it and rag-build refuses to reuse
# vectors produced by an older chunker — without that, this fix would be inert on
# every existing vault until each file happened to change for some other reason.
CHUNKER_VERSION = 2


def _trim(pairs):
    """Drop leading/trailing blank lines so a recorded line points at real content."""
    i, j = 0, len(pairs)
    while i < j and not pairs[i][1].strip():
        i += 1
    while j > i and not pairs[j - 1][1].strip():
        j -= 1
    return pairs[i:j]


def _text(pairs):
    return "\n".join(t for _, t in pairs).strip()


def _split_heading(pairs, prefix):
    """Split into runs beginning at each line starting with `prefix`.

    Returns [(heading_or_None, pairs)]. The run before the first heading keeps
    heading None so the caller can fall back to the page title.
    """
    out, cur, head = [], [], None
    for p in pairs:
        if p[1].startswith(prefix):
            if cur:
                out.append((head, cur))
            cur, head = [p], p[1][len(prefix):].strip()
        else:
            cur.append(p)
    if cur:
        out.append((head, cur))
    return out


def _split_size(pairs, limit):
    """Greedy-pack whole lines into runs of at most `limit` characters.

    Never splits mid-line, so every recorded line number names a real line.
    """
    out, cur, n = [], [], 0
    for p in pairs:
        add = len(p[1]) + (1 if cur else 0)          # +1 for the joining newline
        if cur and n + add > limit:
            out.append(cur)
            cur, n = [p], len(p[1])
        else:
            cur.append(p)
            n += add
    if cur:
        out.append(cur)
    return out


def _chunk(pairs, heading, limit):
    pairs = _trim(pairs)
    if not pairs:
        return []
    text = _text(pairs)
    if not text:
        return []
    if len(text) <= limit:
        return [(heading, pairs[0][0], text)]

    subs = _split_heading(pairs, "### ")
    if len(subs) > 1:
        out = []
        for sub_head, sub in subs:
            out.extend(_chunk(sub, sub_head or heading, limit))
        return out
    if subs and subs[0][0]:
        heading = subs[0][0]     # one `###` covering the whole section — keep its name

    out = []
    for i, piece in enumerate(_split_size(pairs, limit)):
        piece = _trim(piece)
        if not piece:
            continue
        t, ln = _text(piece), piece[0][0]
        h = heading if i == 0 else "%s (cont. %d)" % (heading, i + 1)
        if len(t) <= limit:
            out.append((h, ln, t))
            continue
        # A single line longer than the whole budget: the only case where a chunk
        # boundary cannot fall on a line boundary. Every slice keeps that line's
        # number, because that is genuinely where the text is.
        for k in range(0, len(t), limit):
            out.append((h if k == 0 else "%s (cont.)" % h, ln, t[k:k + limit]))
    return out


def parse_file(path, limit=MAX_CHARS):
    """Return (sha256 of the raw text, declared boundary or None, [(heading, line, text)])."""
    raw = open(path, encoding="utf-8", errors="replace").read()
    sha = hashlib.sha256(raw.encode("utf-8")).hexdigest()
    lines = raw.splitlines()

    i, boundary = 0, None
    if lines and lines[0].strip() == "---":
        i = 1
        while i < len(lines) and lines[i].strip() != "---":
            s = lines[i].strip()
            if s.startswith("boundary:"):
                boundary = s.split(":", 1)[1].strip()
            i += 1
        i += 1

    title = None
    for ln in lines[i:]:
        if ln.startswith("# "):
            title = ln[2:].strip()
            break
    fallback = title or os.path.basename(path)

    pairs = [(n + 1, lines[n]) for n in range(i, len(lines))]
    chunks = []
    for head, part in _split_heading(pairs, "## "):
        chunks.extend(_chunk(part, head or fallback, limit))
    return sha, boundary, chunks
