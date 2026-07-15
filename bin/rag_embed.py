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
import os, sys, json, urllib.request, urllib.error

DEFAULT_MODEL = "BAAI/bge-base-en-v1.5"


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

    def _load(self, lib):
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

    def _init_local(self):
        order = [self.lib_pref] if self.lib_pref else ["fastembed", "model2vec", "sentence-transformers"]
        errs = []
        for lib in order:
            try:
                self._load(lib); self.lib = lib; return
            except Exception as e:
                errs.append("%s (%s)" % (lib, e))
        sys.exit("error: no local embedder available — %s.\n"
                 "  Provision the vault's runtime:  engine/bin/rag-setup.sh\n"
                 "  or use an endpoint: RAG_EMBED_API=ollama RAG_EMBED_URL=..." % "; ".join(errs))

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
