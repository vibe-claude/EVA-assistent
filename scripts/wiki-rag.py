#!/usr/bin/env python3
"""
EVA Wiki RAG — semantic search over wiki/ using sentence-transformers + SQLite.

Usage:
  python3 wiki-rag.py index <file>          — index single file
  python3 wiki-rag.py reindex               — reindex all wiki files
  python3 wiki-rag.py search "<query>"      — semantic search, returns JSON
  python3 wiki-rag.py search "<query>" N    — top N results (default 5)
"""

import sys
import os
import json
import sqlite3
import hashlib
import struct
import re
from pathlib import Path
from datetime import datetime

WIKI_DIR = Path(__file__).parent.parent / "wiki"
DB_PATH  = WIKI_DIR / ".index.db"
MODEL_NAME = "paraphrase-multilingual-MiniLM-L12-v2"
SKIP_FILES = {"index.md", "log.md"}

# ── lazy model load ──────────────────────────────────────────────────────────
_model = None
def get_model():
    global _model
    if _model is None:
        from sentence_transformers import SentenceTransformer
        _model = SentenceTransformer(MODEL_NAME)
    return _model

# ── SQLite ───────────────────────────────────────────────────────────────────
def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS embeddings (
            slug        TEXT PRIMARY KEY,
            file_path   TEXT,
            title       TEXT,
            type        TEXT,
            status      TEXT,
            object      TEXT,
            party       TEXT,
            content     TEXT,
            content_hash TEXT,
            embedding   BLOB,
            updated_at  TEXT
        )
    """)
    conn.commit()
    return conn

# ── frontmatter parser ───────────────────────────────────────────────────────
def parse_frontmatter(text):
    meta = {}
    if not text.startswith("---"):
        return meta, text
    end = text.find("\n---", 3)
    if end < 0:
        return meta, text
    fm = text[3:end]
    body = text[end+4:]
    for line in fm.splitlines():
        m = re.match(r"^(\w+):\s*(.+)", line.strip())
        if m:
            meta[m.group(1)] = m.group(2).strip()
    return meta, body

def extract_title(body):
    m = re.search(r"^#\s+(.+)", body, re.MULTILINE)
    return m.group(1).strip() if m else ""

def file_to_text(path):
    """Convert wiki file to text for embedding (frontmatter fields + body)."""
    text = Path(path).read_text(encoding="utf-8")
    meta, body = parse_frontmatter(text)
    # Build searchable text: metadata fields + body without headers/links
    parts = []
    for field in ("object", "party", "type", "status"):
        if meta.get(field) and meta[field] != "null":
            parts.append(meta[field])
    # Clean body: remove markdown syntax, keep prose
    clean = re.sub(r"^#{1,6}\s+", "", body, flags=re.MULTILINE)
    clean = re.sub(r"\[\[.*?\]\]", "", clean)
    clean = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", clean)
    clean = re.sub(r"```.*?```", "", clean, flags=re.DOTALL)
    clean = re.sub(r"`[^`]+`", "", clean)
    clean = re.sub(r"^\s*[-*|].*", "", clean, flags=re.MULTILINE)
    clean = re.sub(r"\s+", " ", clean).strip()
    parts.append(clean[:1500])
    return " ".join(parts)

# ── embedding helpers ─────────────────────────────────────────────────────────
def embed(text):
    model = get_model()
    vec = model.encode(text, normalize_embeddings=True)
    return struct.pack(f"{len(vec)}f", *vec)

def unpack(blob):
    n = len(blob) // 4
    return list(struct.unpack(f"{n}f", blob))

def cosine(a, b):
    dot = sum(x*y for x,y in zip(a,b))
    return dot  # already normalized

# ── index / reindex ──────────────────────────────────────────────────────────
def index_file(path):
    path = Path(path)
    if path.name in SKIP_FILES or not path.suffix == ".md":
        return
    text_raw = path.read_text(encoding="utf-8")
    h = hashlib.md5(text_raw.encode()).hexdigest()
    slug = path.stem

    conn = get_db()
    row = conn.execute("SELECT content_hash FROM embeddings WHERE slug=?", (slug,)).fetchone()
    if row and row[0] == h:
        conn.close()
        return  # unchanged

    meta, body = parse_frontmatter(text_raw)
    title = extract_title(body)
    search_text = file_to_text(path)
    vec = embed(search_text)

    conn.execute("""
        INSERT OR REPLACE INTO embeddings
        (slug, file_path, title, type, status, object, party, content, content_hash, embedding, updated_at)
        VALUES (?,?,?,?,?,?,?,?,?,?,?)
    """, (
        slug, str(path), title,
        meta.get("type",""), meta.get("status",""),
        meta.get("object",""), meta.get("party",""),
        search_text[:500],
        h, vec, datetime.now().isoformat()
    ))
    conn.commit()
    conn.close()
    print(f"indexed: {slug}", file=sys.stderr)

def reindex_all():
    for f in sorted(WIKI_DIR.glob("*.md")):
        if f.name not in SKIP_FILES:
            index_file(f)
    print("reindex done", file=sys.stderr)

# ── search ────────────────────────────────────────────────────────────────────
def keyword_score(query_words, slug, title, obj, party, typ, status, content):
    """BM25-like keyword score: how many query words appear in document fields."""
    text = " ".join([slug, title, obj, party, typ, status, content]).lower()
    hits = sum(1 for w in query_words if w and len(w) > 2 and w in text)
    return hits / max(len(query_words), 1)

def search(query, top_k=5):
    conn = get_db()
    rows = conn.execute(
        "SELECT slug, file_path, title, type, status, object, party, content, embedding FROM embeddings"
    ).fetchall()
    conn.close()
    if not rows:
        return []

    qvec = unpack(embed(query))
    query_words = re.sub(r"[^а-яёa-z0-9 ]", " ", query.lower()).split()

    scored = []
    for slug, fp, title, typ, status, obj, party, content, blob in rows:
        dvec = unpack(blob)
        sem = cosine(qvec, dvec)
        kw  = keyword_score(query_words, slug, title or "", obj or "", party or "", typ or "", status or "", content or "")
        # Hybrid: 60% semantic + 40% keyword
        hybrid = 0.6 * sem + 0.4 * kw
        scored.append({
            "slug": slug,
            "file": fp,
            "title": title or slug,
            "type": typ,
            "status": status,
            "object": obj,
            "party": party,
            "score": round(hybrid, 4)
        })
    scored.sort(key=lambda x: x["score"], reverse=True)
    return scored[:top_k]

# ── CLI ───────────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    cmd = sys.argv[1]

    if cmd == "index" and len(sys.argv) >= 3:
        index_file(sys.argv[2])

    elif cmd == "reindex":
        reindex_all()

    elif cmd == "search" and len(sys.argv) >= 3:
        query = sys.argv[2]
        top_k = int(sys.argv[3]) if len(sys.argv) >= 4 else 5
        results = search(query, top_k)
        print(json.dumps(results, ensure_ascii=False, indent=2))

    else:
        print(__doc__)
        sys.exit(1)
