from __future__ import annotations

from typing import List, Dict, Any

from pinecone import Pinecone, ServerlessSpec


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
        return
    pc.create_index(
        name=index_name,
        dimension=dimension,
        metric=metric,
        spec=ServerlessSpec(cloud=cloud, region=region),
    )


def upsert_vectors(
    pc: Pinecone,
    index_name: str,
    namespace: str,
    vectors: List[Dict[str, Any]],
) -> None:
    index = pc.Index(index_name)
    index.upsert(vectors=vectors, namespace=namespace)


