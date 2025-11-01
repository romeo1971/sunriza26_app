import os
import json
import typing as t
from flask import Flask, request, jsonify
import requests


app = Flask(__name__)


def _chunk_text(text: str, target_tokens: int = 900, overlap: int = 100, min_chunk_tokens: int = 630) -> t.List[t.Dict[str, t.Any]]:
    text = (text or "").strip()
    if not text:
        return []
    approx_chars = max(target_tokens * 4, 2000)
    chunks: t.List[t.Dict[str, t.Any]] = []
    start = 0
    idx = 0
    while start < len(text):
        end = min(len(text), start + approx_chars)
        chunk = text[start:end]
        chunks.append({"index": idx, "text": chunk})
        start = end - min(overlap * 4, end)
        idx += 1
    def approx_tokens(s: str) -> int:
        return max(1, len(s) // 4)
    while len(chunks) >= 2 and approx_tokens(chunks[-1]["text"]) < min_chunk_tokens:
        prev = chunks[-2]["text"]
        last = chunks[-1]["text"]
        chunks[-2]["text"] = (prev + "\n\n" + last).strip()
        chunks.pop()
    for i, c in enumerate(chunks):
        c["index"] = i
    return chunks


@app.after_request
def add_cors(resp):
    resp.headers["Access-Control-Allow-Origin"] = "*"
    resp.headers["Access-Control-Allow-Methods"] = "POST, OPTIONS"
    resp.headers["Access-Control-Allow-Headers"] = "Content-Type, Authorization"
    return resp


@app.route("/", methods=["POST", "OPTIONS"])
@app.route("/avatar/memory/insert", methods=["POST", "OPTIONS"])
def memory_insert():
    if request.method == "OPTIONS":
        return ("", 204)

    try:
        body = request.get_json(silent=True) or {}
        if body.get("dry_run"):
            return jsonify({"ok": True, "msg": "dry_run", "echo": body})

        user_id = (body.get("user_id") or "").strip()
        avatar_id = (body.get("avatar_id") or "").strip()
        full_text = body.get("full_text") or ""
        source = body.get("source")
        file_name = body.get("file_name")
        target_tokens = int(body.get("target_tokens", 900))
        overlap = int(body.get("overlap", 100))
        min_chunk_tokens = int(body.get("min_chunk_tokens", 630))

        if not user_id or not avatar_id or not full_text:
            return jsonify({"error": "user_id, avatar_id und full_text erforderlich"}), 400

        if len(full_text) > 5_000_000:
            return jsonify({"error": f"Text zu groß: {len(full_text)} chars (max: 5000000)"}), 400

        chunks = _chunk_text(full_text, target_tokens, overlap, min_chunk_tokens)
        if not chunks:
            return jsonify({"error": "full_text ist leer"}), 400

        # Direkt den Worker per HTTP aufrufen (fire-and-forget)
        worker_url = os.getenv("WORKER_URL")
        if not worker_url:
            return jsonify({"error": "WORKER_URL fehlt"}), 500
        try:
            requests.post(
                worker_url,
                headers={"Content-Type": "application/json"},
                json={
                    "user_id": user_id,
                    "avatar_id": avatar_id,
                    "full_text": full_text,
                    "source": source or "app",
                    "file_name": file_name,
                    "target_tokens": target_tokens,
                    "overlap": overlap,
                    "min_chunk_tokens": min_chunk_tokens,
                },
                timeout=5,
            )
        except Exception:
            # Wir antworten trotzdem 200, UI bleibt snappy; Worker kann erneut versucht werden
            pass
        return jsonify({"queued": True}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "8080")))


