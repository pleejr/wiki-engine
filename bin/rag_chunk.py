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
# the entire budget. That last cut prefers a SENTENCE end within a window below the cap,
# and falls back to the cap exactly when the window holds none.
import hashlib, os, re

from rag_embed import MAX_CHARS

# Bump when the split changes shape. Records carry it and rag-build refuses to reuse
# vectors produced by an older chunker — without that, this fix would be inert on
# every existing vault until each file happened to change for some other reason.
CHUNKER_VERSION = 4

# The hard slice is the one cut that cannot fall on a line boundary, and it used to fall
# on a character count — mid-sentence, often mid-word, with the remainder becoming its own
# embedding of a fragment that means nothing on its own. Look back from the cap for a
# sentence end and cut there instead.
#
# SLICE_BACKOFF is a FRACTION of the budget, not a character count, so the window scales
# with `limit` rather than needing a second number kept in step with it. A tenth of a
# 6,000-character cap is 600 — long enough to contain a sentence end in ordinary prose,
# short enough that the chunk before it stays near full.
SLICE_BACKOFF = 0.1

# A terminator, any closing quotes or brackets that belong to it, then whitespace. The
# trailing `\s` is what makes this a SENTENCE end rather than a decimal point or an
# abbreviation followed by more of the same word.
_SENTENCE_END = re.compile(r'[.!?]["\')\]]*\s')


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


# LIST_PACK is deliberately well below MAX_CHARS. A flat list page — an append-only log of
# dated entries, one `# ` title and no sections — has no structure for the two heading levels
# to find, so it fell through to size packing and filled every chunk to the embedder's cap.
# Measured on a real log: 187 self-contained entries, median 1,475 characters, packed ~2.9 to
# a chunk at a median 5,115. Nothing was lost — every character was embedded — but one vector
# then had to represent three unrelated days, and the lead entry dominated it, so a query
# phrased from memory ranked the diluted chunk below shorter topical pages. Present in the
# index, unreachable in practice.
#
# The entries were already the right retrieval unit; the splitter had no rule that saw them.
# Packing to a smaller budget rather than one-item-per-chunk keeps a page of many tiny bullets
# from exploding into a chunk each, while an ordinary long entry still stands alone.
LIST_PACK = 2000

_LIST_START = ("- ", "* ", "+ ")


def _is_item_start(line):
    if line.startswith(_LIST_START):
        return True
    # ordered items: "1. " / "12) "
    head = line.split(" ", 1)[0]
    return len(head) > 1 and head[:-1].isdigit() and head[-1] in ".)"


def _split_items(pairs):
    """Split a flat list into runs, each beginning at a TOP-LEVEL item.

    Returns None when the block is not a flat list, so the caller falls through to
    size packing unchanged. A continuation — an indented line, a nested bullet, a
    fenced block, a blank line inside an item — stays with the item it belongs to,
    which is why this tracks fences rather than splitting on every matching line.
    """
    runs, cur, seen, fenced = [], [], 0, False
    for p in pairs:
        line = p[1]
        stripped = line.strip()
        if stripped.startswith("```"):
            fenced = not fenced
        starts = (not fenced) and (not line[:1].isspace()) and _is_item_start(line)
        if starts:
            seen += 1
            if cur:
                runs.append(cur)
            cur = [p]
        else:
            if not cur:
                cur = [p]       # preamble before the first item rides with it
            else:
                cur.append(p)
    if cur:
        runs.append(cur)
    # Not a list unless it is mostly items: two or more, and no huge non-item preamble.
    if seen < 2:
        return None
    return runs


def _pack_runs(runs, limit):
    """Greedy-pack whole runs up to `limit`, never splitting a run."""
    out, cur, n = [], [], 0
    for r in runs:
        size = sum(len(t) + 1 for _, t in r)
        if cur and n + size > limit:
            out.append(cur); cur, n = list(r), size
        else:
            cur.extend(r); n += size
    if cur:
        out.append(cur)
    return out

def _hard_slice(text, limit):
    """Yield pieces of `text`, each <= limit, preferring a sentence end to the bare cap.

    Concatenating the yielded pieces reproduces `text` EXACTLY — the cut is an index, and
    nothing is dropped, trimmed or normalised. That invariant is what lets the caller keep
    claiming every character of the page is indexed.
    """
    window = max(1, int(limit * SLICE_BACKOFF))
    while len(text) > limit:
        cut = limit
        # The LAST sentence end that finishes at or before the cap. `endpos` bounds the
        # match itself, so a terminator whose trailing whitespace falls past the cap is
        # correctly not a candidate.
        for m in _SENTENCE_END.finditer(text, limit - window, limit):
            cut = m.end()
        yield text[:cut]
        text = text[cut:]
    if text:
        yield text


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

    # A flat list splits on ITEM boundaries before it splits on size: the item is the
    # self-contained unit a reader would break the page at, and the size fallback below
    # cannot see it.
    runs = _split_items(pairs)
    pieces = _pack_runs(runs, min(LIST_PACK, limit)) if runs else _split_size(pairs, limit)

    out = []
    for i, piece in enumerate(pieces):
        piece = _trim(piece)
        if not piece:
            continue
        t, ln = _text(piece), piece[0][0]
        h = heading if i == 0 else "%s (cont. %d)" % (heading, i + 1)
        if len(t) <= limit:
            out.append((h, ln, t))
            continue
        # An over-cap piece must fall back to LINE packing before it is ever sliced.
        # A list run is never split by _pack_runs, so a single enormous item arrives
        # here as many lines — and hard-slicing it would break mid-line where the old
        # size fallback would not have. Measured: one page's largest chunk went 4,021
        # -> 6,000 characters before this, i.e. the list level made a chunk WORSE.
        if len(piece) > 1:
            for j, sub in enumerate(_split_size(piece, limit)):
                sub = _trim(sub)
                if not sub:
                    continue
                st, sln = _text(sub), sub[0][0]
                sh = h if j == 0 else "%s (cont. %d)" % (h, j + 1)
                if len(st) <= limit:
                    out.append((sh, sln, st))
                else:
                    for k, part in enumerate(_hard_slice(st, limit)):
                        out.append((sh if k == 0 else "%s (cont.)" % sh, sln, part))
            continue
        # A single line longer than the whole budget: the only case where a chunk
        # boundary cannot fall on a line boundary. Every slice keeps that line's
        # number, because that is genuinely where the text is. A one-line-per-entry log
        # reaches here with no boundary left to try — `##` and `###` are absent, the item
        # IS the unit, and LINE packing cannot reduce a single line — so this is where the
        # sentence-end backoff earns its place.
        for k, part in enumerate(_hard_slice(t, limit)):
            out.append((h if k == 0 else "%s (cont.)" % h, ln, part))
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
