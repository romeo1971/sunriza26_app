import json
import os
import typing as t

import functions_framework
import logging
import requests


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


def _cors_headers() -> dict:
    return {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type, Authorization",
    }


logger = logging.getLogger("memory_cf")
logger.setLevel(logging.INFO)


@functions_framework.http
def memory_insert(request):  # entry-point: memory_insert
    if request.method == "OPTIONS":
        return ("", 204, _cors_headers())

    headers = _cors_headers()

    if request.method != "POST":
        return (json.dumps({"error": "Method not allowed"}), 405, {**headers, "Content-Type": "application/json"})

    try:
        body = request.get_json(silent=True) or {}
        if body.get("dry_run"):
            return (json.dumps({"ok": True, "msg": "dry_run", "echo": body}), 200, {**headers, "Content-Type": "application/json"})
        user_id = (body.get("user_id") or "").strip()
        avatar_id = (body.get("avatar_id") or "").strip()
        full_text = body.get("full_text") or ""
        source = body.get("source")
        file_name = body.get("file_name")
        target_tokens = int(body.get("target_tokens", 900))
        overlap = int(body.get("overlap", 100))
        min_chunk_tokens = int(body.get("min_chunk_tokens", 630))

        if not user_id or not avatar_id or not full_text:
            return (
                json.dumps({"error": "user_id, avatar_id und full_text erforderlich"}),
                400,
                {**headers, "Content-Type": "application/json"},
            )

        # Schutz gegen riesige Inputs
        if len(full_text) > 5_000_000:
            return (
                json.dumps({"error": f"Text zu groß: {len(full_text)} chars (max: 5000000)"}),
                400,
                {**headers, "Content-Type": "application/json"},
            )
        logger.info("step=chunking len=%s", len(full_text))
        chunks = _chunk_text(full_text, target_tokens, overlap, min_chunk_tokens)
        if not chunks:
            return (json.dumps({"error": "full_text ist leer"}), 400, {**headers, "Content-Type": "application/json"})

        OPENAI_API_KEY = (os.getenv("OPENAI_API_KEY") or "").strip()
        PINECONE_API_KEY = (os.getenv("PINECONE_API_KEY") or "").strip()
        if not OPENAI_API_KEY or not PINECONE_API_KEY:
            return (json.dumps({"error": "Server secrets missing"}), 500, {**headers, "Content-Type": "application/json"})

        index_name = "sunriza26-avatar-data"
        namespace = f"{user_id}_{avatar_id}"

        # Embeddings + Upsert strikt in Minibatches (Peak-RAM minimieren)
        BATCH = 1  # minimaler Speicher-Fußabdruck

        # Pinecone Host auflösen (Control Plane)
        logger.info("step=host_lookup index=%s", index_name)
        host_resp = requests.get(
            f"https://api.pinecone.io/indexes/{index_name}", headers={"Api-Key": PINECONE_API_KEY}, timeout=15
        )
        if host_resp.status_code >= 300:
            return (
                json.dumps({"error": f"Pinecone host lookup failed: {host_resp.text}"}),
                host_resp.status_code,
                {**headers, "Content-Type": "application/json"},
            )
        host = (host_resp.json() or {}).get("host")
        if not host:
            return (json.dumps({"error": "Pinecone host missing"}), 500, {**headers, "Content-Type": "application/json"})

        total_inserted = 0
        doc_id = f"{int(__import__('time').time()*1000)}"
        created_at = int(__import__('time').time()*1000)

        logger.info("step=batches total=%s size=%s", (len(chunks)+BATCH-1)//BATCH, BATCH)
        for i in range(0, len(chunks), BATCH):
            part = chunks[i:i + BATCH]
            part_texts = [c["text"] for c in part]
            logger.info("step=embeddings start=%s count=%s", i, len(part_texts))
            part_embeddings: t.List[t.List[float]]
            if os.getenv("FAKE_EMB", "0") == "1":
                # Fake-Embeddings (stabil, minimaler Speicher) – Dimension passend zum Zielindex
                dim = int(os.getenv("EMB_DIM", "1536"))
                part_embeddings = [[0.001 * (j + 1)] * dim for j in range(len(part_texts))]
            else:
                emb_resp = requests.post(
                    "https://api.openai.com/v1/embeddings",
                    headers={"Authorization": f"Bearer {OPENAI_API_KEY}", "Content-Type": "application/json"},
                    json={"model": "text-embedding-3-small", "input": part_texts},
                    timeout=30,
                )
                if emb_resp.status_code >= 300:
                    return (
                        json.dumps({"error": f"OpenAI embeddings failed: {emb_resp.text}"}),
                        emb_resp.status_code,
                        {**headers, "Content-Type": "application/json"},
                    )
                emb_json = emb_resp.json()
                part_embeddings = [d["embedding"] for d in emb_json.get("data", [])]

            # Isolationsmodus: Nur Embeddings testen, kein Pinecone
            if os.getenv("ONLY_EMB", "0") == "1":
                total_inserted += len(part_embeddings)
                continue

            # Vektoren für diesen Batch
            vectors = []
            for off, ch in enumerate(part):
                meta = {
                    "user_id": user_id,
                    "avatar_id": avatar_id,
                    "chunk_index": ch["index"],
                    "doc_id": doc_id,
                    "created_at": created_at,
                    "source": (source or "app"),
                    # "text" wird NICHT mehr in Metadata gespeichert (Speicher/JSON minimal)
                }
                if file_name:
                    meta["file_name"] = file_name
                vectors.append({
                    "id": f"{avatar_id}-{doc_id}-{ch['index']}",
                    "values": part_embeddings[off],
                    "metadata": meta,
                })

            logger.info("step=upsert start=%s count=%s", i, len(vectors))
            upsert = requests.post(
                f"https://{host}/vectors/upsert",
                headers={"Api-Key": PINECONE_API_KEY, "Content-Type": "application/json"},
                json={"namespace": namespace, "vectors": vectors},
                timeout=60,
            )
            if upsert.status_code >= 300:
                return (
                    json.dumps({"error": f"Pinecone upsert failed: {upsert.text}"}),
                    upsert.status_code,
                    {**headers, "Content-Type": "application/json"},
                )
            total_inserted += len(vectors)
            # Hilft dem GC zwischen den Batches
            del vectors, part_embeddings, part_texts

        logger.info("step=done inserted=%s", total_inserted)
        return (
            json.dumps({
                "namespace": namespace,
                "inserted": total_inserted,
                "index_name": index_name,
                "model": "text-embedding-3-small",
                "batches": (len(chunks) + BATCH - 1) // BATCH,
                "only_embeddings": os.getenv("ONLY_EMB", "0") == "1",
            }),
            200,
            {**headers, "Content-Type": "application/json"},
        )
    except Exception as e:
        logger.exception("handler_error")
        return (json.dumps({"error": str(e)}), 500, {**headers, "Content-Type": "application/json"})
