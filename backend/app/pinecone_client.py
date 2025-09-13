from __future__ import annotations

from typing import List, Dict, Any

from pinecone import Pinecone, ServerlessSpec
import time


def get_pinecone(api_key: str) -> Pinecone:
    return Pinecone(api_key=api_key)


def ensure_index_exists(
    pc: Pinecone,
    index_name: str,
    dimension: int,
    metric: str,
    cloud: str,
    region: str,
) -> None:
    """Create index if missing (idempotent)."""
    existing = {i["name"] for i in pc.list_indexes()}
    if index_name in existing:
        # ensure it's ready
        try:
            desc = pc.describe_index(index_name)
            while isinstance(desc, dict) and not desc.get("status", {}).get("ready", False):
                time.sleep(1)
                desc = pc.describe_index(index_name)
        except Exception:
            # best-effort readiness check
            pass
        return
    pc.create_index(
        name=index_name,
        dimension=dimension,
        metric=metric,
        spec=ServerlessSpec(cloud=cloud, region=region),
    )
    # wait until ready
    try:
        desc = pc.describe_index(index_name)
        while isinstance(desc, dict) and not desc.get("status", {}).get("ready", False):
            time.sleep(1)
            desc = pc.describe_index(index_name)
    except Exception:
        pass


def upsert_vectors(
    pc: Pinecone,
    index_name: str,
    namespace: str,
    vectors: List[Dict[str, Any]],
) -> None:
    index = pc.Index(index_name)
    index.upsert(vectors=vectors, namespace=namespace)



def upsert_vector(
    pc: Pinecone,
    index_name: str,
    namespace: str,
    vector: Dict[str, Any],
) -> None:
    index = pc.Index(index_name)
    index.upsert(vectors=[vector], namespace=namespace)


def fetch_vectors(
    pc: Pinecone,
    index_name: str,
    namespace: str,
    ids: List[str],
) -> Dict[str, Any]:
    index = pc.Index(index_name)
    return index.fetch(ids=ids, namespace=namespace)


def delete_vectors(
    pc: Pinecone,
    index_name: str,
    namespace: str,
    ids: List[str],
) -> None:
    index = pc.Index(index_name)
    index.delete(ids=ids, namespace=namespace)

