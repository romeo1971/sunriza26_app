import os
import json
import typing as t
from flask import Flask, request, jsonify
import requests


app = Flask(__name__)


@app.route("/task", methods=["POST"])
def process_task():
    try:
        body = request.get_json(silent=True) or {}
        user_id = (body.get("user_id") or "").strip()
        avatar_id = (body.get("avatar_id") or "").strip()
        full_text = body.get("full_text") or ""
        source = body.get("source")
        file_name = body.get("file_name")
        target_tokens = int(body.get("target_tokens", 900))
        overlap = int(body.get("overlap", 100))
        min_chunk_tokens = int(body.get("min_chunk_tokens", 630))

        if not user_id or not avatar_id or not full_text:
            return jsonify({"error": "missing fields"}), 400

        # Chunk
        def _chunk_text(text: str, tt: int, ov: int, mn: int) -> t.List[t.Dict[str, t.Any]]:
            text = (text or "").strip()
            if not text:
                return []
            approx_chars = max(tt * 4, 2000)
            chunks: t.List[t.Dict[str, t.Any]] = []
            start = 0
            idx = 0
            while start < len(text):
                end = min(len(text), start + approx_chars)
                chunk = text[start:end]
                chunks.append({"index": idx, "text": chunk})
                start = end - min(ov * 4, end)
                idx += 1
            def approx_tokens(s: str) -> int:
                return max(1, len(s)//4)
            while len(chunks) >= 2 and approx_tokens(chunks[-1]["text"]) < mn:
                prev = chunks[-2]["text"]
                last = chunks[-1]["text"]
                chunks[-2]["text"] = (prev + "\n\n" + last).strip()
                chunks.pop()
            for i, c in enumerate(chunks):
                c["index"] = i
            return chunks

        chunks = _chunk_text(full_text, target_tokens, overlap, min_chunk_tokens)
        if not chunks:
            return jsonify({"ok": True, "inserted": 0})

        OPENAI_API_KEY = (os.getenv("OPENAI_API_KEY") or "").strip()
        PINECONE_API_KEY = (os.getenv("PINECONE_API_KEY") or "").strip()

        # Pinecone host
        index_name = "sunriza26-avatar-data"
        namespace = f"{user_id}_{avatar_id}"
        host_resp = requests.get(
            f"https://api.pinecone.io/indexes/{index_name}", headers={"Api-Key": PINECONE_API_KEY}, timeout=15
        )
        host = (host_resp.json() or {}).get("host")
        if not host:
            return jsonify({"error": "pinecone host"}), 500

        BATCH = 8
        total = 0
        doc_id = str(int(__import__('time').time()*1000))
        created_at = int(__import__('time').time()*1000)

        for i in range(0, len(chunks), BATCH):
            part = chunks[i:i+BATCH]
            part_texts = [c["text"] for c in part]
            emb_resp = requests.post(
                "https://api.openai.com/v1/embeddings",
                headers={"Authorization": f"Bearer {OPENAI_API_KEY}", "Content-Type": "application/json"},
                json={"model": "text-embedding-3-small", "input": part_texts},
                timeout=60,
            )
            emb = emb_resp.json()
            vectors = []
            for off, ch in enumerate(part):
                meta = {
                    "user_id": user_id,
                    "avatar_id": avatar_id,
                    "chunk_index": ch["index"],
                    "doc_id": doc_id,
                    "created_at": created_at,
                    "source": (source or "app"),
                }
                vectors.append({
                    "id": f"{avatar_id}-{doc_id}-{ch['index']}",
                    "values": emb["data"][off]["embedding"],
                    "metadata": meta,
                })
            up = requests.post(
                f"https://{host}/vectors/upsert",
                headers={"Api-Key": PINECONE_API_KEY, "Content-Type": "application/json"},
                json={"namespace": namespace, "vectors": vectors},
                timeout=60,
            )
            total += len(vectors)

        return jsonify({"ok": True, "inserted": total})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "8080")))



