# rag_embed.py — the single embedding backend for the RAG layer (shared by
# rag-build.sh and recall.sh). Kept in one place so build-time and query-time
# embeddings always agree on backend + model.
#
# Backends (Embedder picks in this order): env RAG_EMBED_API, then the vault's
# .rag/config.json, else "local".
#   local  — in-process CPU model, no server: model2vec (default) / fastembed /
#            sentence-transformers, whichever is importable. Provisioned into the
#            vault's .rag/venv by rag-setup.sh; fully offline after one fetch.
#   ollama — POST {model,prompt} -> {embedding}    (local HTTP endpoint)
#   openai — POST {model,input}  -> {data:[{embedding}]}  (RAG_API_KEY bearer)
#
# Config precedence: env var > .rag/config.json > built-in default.
#
# Model weights live in an engine-chosen cache (see _prepare_cache), not wherever
# each library happens to default — resolved here because this module is the one
# seam all three entry points (rag-setup, rag-build, recall) share.
import os, sys, json, shutil, tempfile, urllib.request, urllib.error

DEFAULT_MODEL = "BAAI/bge-base-en-v1.5"


def default_cache_root():
    """Machine-global cache root for local model weights.

    Machine-scoped rather than vault-local: the weights are identical across vaults,
    so two vaults on one host share one copy instead of each carrying hundreds of MB.
    Sits beside the HF ecosystem's own convention (~/.cache/...) rather than inventing
    a location. Override with RAG_MODEL_CACHE (vault-local stays reachable that way).
    """
    base = os.environ.get("XDG_CACHE_HOME") or os.path.join(os.path.expanduser("~"), ".cache")
    return os.path.join(base, "wiki-engine", "models")


def hf_default_cache():
    """Where the HF-backed libs put weights when left alone — a documented durable path."""
    try:
        from huggingface_hub import constants
        return constants.HF_HUB_CACHE
    except Exception:
        base = os.environ.get("XDG_CACHE_HOME") or os.path.join(os.path.expanduser("~"), ".cache")
        return os.path.join(base, "huggingface", "hub")


def _ensure_writable(path):
    """Create the cache dir, or fail naming it. Never silently falls back to temp —
    a fallback would restore the very bug this exists to prevent while looking fixed."""
    try:
        os.makedirs(path, exist_ok=True)
    except OSError as e:
        sys.exit("error: model cache %s is not usable (%s).\n"
                 "  Point RAG_MODEL_CACHE at a writable directory, or fix permissions.\n"
                 "  The engine will not fall back to a temp dir — temp is reaped by the OS."
                 % (path, e))
    if not os.access(path, os.W_OK):
        sys.exit("error: model cache %s is not writable.\n"
                 "  Point RAG_MODEL_CACHE at a writable directory, or fix permissions." % path)


def _adopt_legacy(root, legacy):
    """Move an already-downloaded cache into `root` instead of re-fetching it.

    Upgrade path for a vault provisioned before the cache was pinned: its weights are
    good, they are just in the OS temp dir. Re-downloading needs the network, and
    rag-build.sh / recall.sh run with HF_HUB_OFFLINE=1 — so without this an offline
    upgrade breaks recall while usable weights sit right there. One-shot by nature:
    once moved, there is nothing left to adopt.
    """
    if not os.path.isdir(legacy) or os.path.abspath(legacy) == os.path.abspath(root):
        return
    try:
        entries = os.listdir(legacy)
    except OSError:
        return
    moved = 0
    for name in entries:
        if name == "tmp":              # fastembed's own staging dir, not weights
            continue
        dst = os.path.join(root, name)
        if os.path.exists(dst):        # already adopted / newer copy wins
            continue
        try:
            shutil.move(os.path.join(legacy, name), dst)
            moved += 1
        except OSError:
            pass                        # partial adoption still beats a re-download
    if moved:
        sys.stderr.write("rag: adopted %d cached item(s) from %s -> %s\n" % (moved, legacy, root))


def _config(wiki):
    if not wiki:
        return {}
    p = os.path.join(wiki, ".rag", "config.json")
    if os.path.isfile(p):
        try:
            return json.load(open(p, encoding="utf-8"))
        except Exception:
            return {}
    return {}


class Embedder:
    def __init__(self, wiki=None):
        cfg = _config(wiki)
        self._cfg = cfg
        # Operator's explicit cache choice, if any: env wins, else what rag-setup
        # recorded. Kept separate from the *effective* path (self.cache) so a
        # forgotten env var is recovered from config instead of silently resolving
        # somewhere else than the prefetch did.
        self.cache_pin = os.environ.get("RAG_MODEL_CACHE") or cfg.get("model_cache_pin")
        self.cache = None
        self.backend = os.environ.get("RAG_EMBED_API") or cfg.get("backend") or "local"
        self.model = (os.environ.get("RAG_LOCAL_MODEL")
                      or os.environ.get("RAG_EMBED_MODEL")
                      or cfg.get("model") or DEFAULT_MODEL)
        self.url = os.environ.get("RAG_EMBED_URL", "http://localhost:11434/api/embeddings")
        self.key = os.environ.get("RAG_API_KEY", "")
        # pin the library when known (config written by rag-setup, or env), so build
        # and query never probe the wrong backend; otherwise auto-detect.
        self.lib_pref = os.environ.get("RAG_LOCAL_LIB") or cfg.get("lib")
        self.lib = None
        if self.backend == "local":
            self._init_local()

    def _prepare_cache(self, lib):
        """Point `lib` at a durable cache and return the directory it will actually use.

        fastembed defaults to tempfile.gettempdir()/fastembed_cache — reaped by the OS
        on a schedule the engine doesn't control, while the venv it belongs to survives
        — so it is *always* redirected. The HF-backed libs already default to a
        documented durable path that is shared with every other HF tool on the machine,
        so relocating them would reduce sharing and force a re-download for no gain:
        they move only on an explicit override, and are otherwise just recorded.

        Must run before the library is imported — these are read at import/construction.
        """
        if lib == "fastembed":
            root = self.cache_pin or default_cache_root()
            _ensure_writable(root)
            _adopt_legacy(root, os.path.join(tempfile.gettempdir(), "fastembed_cache"))
            os.environ["FASTEMBED_CACHE_PATH"] = root
            return root
        if self.cache_pin:
            _ensure_writable(self.cache_pin)
            # HF_HUB_CACHE, not HF_HOME — HF_HOME also relocates the token file.
            os.environ["HF_HUB_CACHE"] = self.cache_pin
            return self.cache_pin
        return hf_default_cache()

    def _load(self, lib):
        self.cache = self._prepare_cache(lib)
        if lib == "fastembed":
            from fastembed import TextEmbedding
            self._m = TextEmbedding(model_name=self.model)
        elif lib == "model2vec":
            from model2vec import StaticModel
            self._m = StaticModel.from_pretrained(self.model)
        elif lib == "sentence-transformers":
            from sentence_transformers import SentenceTransformer
            self._m = SentenceTransformer(self.model)
        else:
            raise ImportError("unknown embedder lib: %s" % lib)

    # import name per lib, for availability checks that don't execute the module
    _MODULES = {"fastembed": "fastembed", "model2vec": "model2vec",
                "sentence-transformers": "sentence_transformers"}

    def _init_local(self):
        order = [self.lib_pref] if self.lib_pref else ["fastembed", "model2vec", "sentence-transformers"]
        # Narrow to installed libs BEFORE preparing any cache. _prepare_cache has
        # filesystem side effects (creates the root, adopts a legacy cache), so
        # probing by import would let a library that isn't even installed move a
        # cache around — a model2vec-only vault would run the fastembed migration.
        # find_spec answers "is it importable?" without executing the module, and
        # the env vars still get set before the real import (HF_HUB_CACHE is read at
        # huggingface_hub import time, so it cannot be set afterwards).
        import importlib.util
        def installed(lib):
            try:
                return importlib.util.find_spec(self._MODULES.get(lib, lib)) is not None
            except (ImportError, ValueError):
                return False
        avail = [l for l in order if installed(l)]
        errs = ["%s (not installed)" % l for l in order if l not in avail]
        for lib in avail:
            try:
                self._load(lib); self.lib = lib; return
            except Exception as e:
                errs.append("%s (%s)" % (lib, e))
        sys.exit("error: no local embedder available — %s.\n"
                 "  Model cache: %s\n"
                 "  Provision the vault's runtime:  engine/bin/rag-setup.sh\n"
                 "  or use an endpoint: RAG_EMBED_API=ollama RAG_EMBED_URL=..."
                 % ("; ".join(errs), self.cache or self.cache_pin or default_cache_root()))

    def embed(self, texts):
        texts = [t[:6000] for t in texts]
        if self.backend == "local":
            if self.lib == "model2vec":
                return [[float(x) for x in row] for row in self._m.encode(texts)]
            if self.lib == "fastembed":
                return [[float(x) for x in row] for row in self._m.embed(texts)]
            return [[float(x) for x in self._m.encode(t)] for t in texts]
        return [self._http(t) for t in texts]

    def _http(self, text):
        body = ({"model": self.model, "input": text} if self.backend == "openai"
                else {"model": self.model, "prompt": text})
        req = urllib.request.Request(self.url, data=json.dumps(body).encode(),
                                     headers={"Content-Type": "application/json"})
        if self.key:
            req.add_header("Authorization", "Bearer " + self.key)
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                data = json.load(r)
        except urllib.error.URLError as e:
            sys.exit("error: embedding endpoint %s unreachable (%s)" % (self.url, e))
        return data["data"][0]["embedding"] if self.backend == "openai" else data["embedding"]
