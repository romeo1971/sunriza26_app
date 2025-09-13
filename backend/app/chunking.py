from __future__ import annotations

from typing import List, Dict


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
) -> List[Dict]:
    text = (text or "").strip()
    if not text:
        return []

    tk = _try_import_tiktoken()
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
    return chunks


