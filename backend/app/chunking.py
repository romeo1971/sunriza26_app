from __future__ import annotations

from typing import List, Dict, Optional
import os


def _try_import_tiktoken():
    try:
        import tiktoken  # type: ignore

        return tiktoken
    except Exception:
        return None


def chunk_text(
    text: str,
    target_tokens: int = 900,
    overlap: int = 100,
    *,
    min_chunk_tokens_override: Optional[int] = None,
) -> List[Dict]:
    text = (text or "").strip()
    if not text:
        return []

    tk = _try_import_tiktoken()
    # Mindestgröße kleiner Chunks (Default: 70% von target_tokens oder ENV MIN_CHUNK_TOKENS)
    if min_chunk_tokens_override is not None:
        min_chunk_tokens = int(max(1, min_chunk_tokens_override))
    else:
        try:
            min_chunk_tokens = int(os.getenv("MIN_CHUNK_TOKENS", "0"))
        except Exception:
            min_chunk_tokens = 0
    if min_chunk_tokens <= 0:
        min_chunk_tokens = max(1, int(target_tokens * 0.7))

    if tk is None:
        # Fallback: naive Split nach ~target_tokens*4 Zeichen
        approx_chars = max(target_tokens * 4, 2000)
        chunks: List[Dict] = []
        start = 0
        idx = 0
        while start < len(text):
            end = min(len(text), start + approx_chars)
            chunk = text[start:end]
            chunks.append({"index": idx, "text": chunk})
            start = end - min(int(overlap * 4), end)
            idx += 1
        # Merge zu kleine letzte Chunks (nahezu anhand Zeichenlänge)
        def _approx_tokens(s: str) -> int:
            return max(1, len(s) // 4)
        while len(chunks) >= 2 and _approx_tokens(chunks[-1]["text"]) < min_chunk_tokens:
            prev = chunks[-2]["text"]
            last = chunks[-1]["text"]
            chunks[-2]["text"] = (prev + "\n\n" + last).strip()
            chunks.pop()
        # Reindex
        for i, c in enumerate(chunks):
            c["index"] = i
        return chunks

    enc = tk.get_encoding("cl100k_base")
    tokens = enc.encode(text)
    if not tokens:
        return []

    step = max(1, target_tokens - overlap)
    chunks: List[Dict] = []
    idx = 0
    for start in range(0, len(tokens), step):
        end = min(len(tokens), start + target_tokens)
        sub = tokens[start:end]
        if not sub:
            continue
        chunk_text = enc.decode(sub)
        chunks.append({"index": idx, "text": chunk_text})
        idx += 1
        if end >= len(tokens):
            break
    # Zu kleine letzte Chunks in den vorherigen mergen, bis Mindestgröße erfüllt
    def _count_tokens(s: str) -> int:
        try:
            return len(enc.encode(s))
        except Exception:
            return max(1, len(s) // 4)

    while len(chunks) >= 2 and _count_tokens(chunks[-1]["text"]) < min_chunk_tokens:
        prev = chunks[-2]["text"]
        last = chunks[-1]["text"]
        chunks[-2]["text"] = (prev + "\n\n" + last).strip()
        chunks.pop()
    # Reindex
    for i, c in enumerate(chunks):
        c["index"] = i
    return chunks


