import os
import json
from flask import Flask, request, jsonify
import requests

app = Flask(__name__)


@app.route("/", methods=["POST"])
def process():
    try:
        body = request.get_json(silent=True) or {}
        user_id = (body.get("user_id") or "").strip()
        avatar_id = (body.get("avatar_id") or "").strip()
        full_text = (body.get("full_text") or "").strip()
        
        if not user_id or not avatar_id or not full_text:
            return jsonify({"error": "missing fields"}), 400

        # Simple chunking (max 3000 chars per chunk)
        chunks = []
        idx = 0
        for i in range(0, len(full_text), 3000):
            chunks.append({"index": idx, "text": full_text[i:i+3000]})
            idx += 1

        MISTRAL_KEY = os.getenv("MISTRAL_API_KEY", "").strip()
        PINECONE_KEY = os.getenv("PINECONE_API_KEY", "").strip()
        
        if not MISTRAL_KEY or not PINECONE_KEY:
            return jsonify({"error": "API keys missing"}), 500

        # Get Pinecone host (Bestand: sunriza26-avatar-data; via Env übersteuerbar)
        index_name = os.getenv("PINECONE_GLOBAL_INDEX", "sunriza26-avatar-data")
        namespace = f"{user_id}_{avatar_id}"
        host_resp = requests.get(
            f"https://api.pinecone.io/indexes/{index_name}",
            headers={"Api-Key": PINECONE_KEY},
            timeout=15
        )
        if host_resp.status_code != 200:
            return jsonify({"error": "pinecone host lookup failed"}), 500
        
        host = host_resp.json().get("host")
        if not host:
            return jsonify({"error": "no pinecone host"}), 500

        doc_id = str(int(__import__('time').time() * 1000))
        created_at = int(__import__('time').time() * 1000)
        total = 0

        # Process in small batches
        BATCH = 1
        for i in range(0, len(chunks), BATCH):
            batch = chunks[i:i+BATCH]
            texts = [c["text"] for c in batch]
            
            # Get embeddings
            emb_resp = requests.post(
                "https://api.mistral.ai/v1/embeddings",
                headers={
                    "Authorization": f"Bearer {MISTRAL_KEY}",
                    "Content-Type": "application/json"
                },
                json={"model": os.getenv("MISTRAL_EMBED_MODEL", "mistral-embed"), "input": texts},
                timeout=30
            )
            if emb_resp.status_code != 200:
                return jsonify({"error": f"OpenAI failed: {emb_resp.text}"}), 500
            
            emb_data = emb_resp.json()
            
            # Upsert to Pinecone
            vectors = []
            for j, chunk in enumerate(batch):
                vec = emb_data["data"][j]["embedding"]
                # Auf 1536 Dimension bringen (Padding/Truncation) für bestehenden Index
                target_dim = int(os.getenv("EMB_DIM", "1536"))
                if len(vec) > target_dim:
                    vec = vec[:target_dim]
                elif len(vec) < target_dim:
                    vec = vec + [0.0] * (target_dim - len(vec))
                vectors.append({
                    "id": f"{avatar_id}-{doc_id}-{chunk['index']}",
                    "values": vec,
                    "metadata": {
                        "user_id": user_id,
                        "avatar_id": avatar_id,
                        "chunk_index": chunk["index"],
                        "doc_id": doc_id,
                        "created_at": created_at,
                        "source": body.get("source", "app")
                    }
                })
            
            up_resp = requests.post(
                f"https://{host}/vectors/upsert",
                headers={
                    "Api-Key": PINECONE_KEY,
                    "Content-Type": "application/json"
                },
                json={"namespace": namespace, "vectors": vectors},
                timeout=30
            )
            if up_resp.status_code != 200:
                return jsonify({"error": f"Pinecone upsert failed: {up_resp.text}"}), 500
            
            total += len(vectors)
            # Clear memory
            del vectors, emb_data, texts

        return jsonify({"ok": True, "inserted": total, "namespace": namespace}), 200

    except Exception as e:
        import traceback
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "8080")))







