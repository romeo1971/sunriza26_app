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
    existing_names = set()
    try:
        lst = pc.list_indexes()
        for it in lst:
            # Supports dict, object with .name, or plain string
            name = None
            if isinstance(it, str):
                name = it
            elif isinstance(it, dict):
                name = it.get("name")
            else:
                name = getattr(it, "name", None)
            if name:
                existing_names.add(name)
    except Exception:
        # Fallback: assume not existing, creation will be attempted
        existing_names = set()
    def _is_ready(desc: Any) -> bool:  # type: ignore[name-defined]
        try:
            if isinstance(desc, dict):
                status = desc.get("status")
                if isinstance(status, dict):
                    return bool(status.get("ready", True))
                # Keine Status-Info → als bereit behandeln
                return True
            status_obj = getattr(desc, "status", None)
            if status_obj is None:
                return True
            return bool(getattr(status_obj, "ready", True))
        except Exception:
            return True

    if index_name in existing_names:
        # ensure it's ready (max 60s)
        try:
            t0 = time.time()
            while True:
                desc = pc.describe_index(index_name)
                if _is_ready(desc):
                    break
                if time.time() - t0 > 60:
                    break
                time.sleep(1)
        except Exception:
            # best-effort readiness check
            pass
        return
    # Try requested spec first; on plan/region errors, auto-fallback to aws/us-east-1
    def _wait_ready(timeout_sec: int = 60) -> None:
        try:
            t0 = time.time()
            while True:
                desc = pc.describe_index(index_name)
                if _is_ready(desc):
                    return
                if time.time() - t0 > timeout_sec:
                    return
                time.sleep(1)
        except Exception:
            return

    try:
        pc.create_index(
            name=index_name,
            dimension=dimension,
            metric=metric,
            spec=ServerlessSpec(cloud=cloud, region=region),
        )
        _wait_ready()
        return
    except Exception as e:
        msg = str(e).lower()
        # Pinecone often returns 400 INVALID_ARGUMENT when region isn't allowed on plan
        hints = ("invalid_argument" in msg) or ("free plan" in msg) or ("does not support indexes" in msg) or ("bad request" in msg)
        # Be robust: if configured region/cloud isn't the known-free default, allow fallback even if message doesn't match
        is_non_default_target = (str(cloud).lower() != "aws") or (str(region).lower() != "us-east-1")
        if not (hints or is_non_default_target):
            # Re-raise unknown errors when already targeting the default region
            raise
    # Fallback to a widely-supported region on free plans
    pc.create_index(
        name=index_name,
        dimension=dimension,
        metric=metric,
        spec=ServerlessSpec(cloud="aws", region="us-east-1"),
    )
    _wait_ready()


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
    res = index.fetch(ids=ids, namespace=namespace)
    # Vereinheitliche Ausgabe auf Dict
    if isinstance(res, dict):
        return res
    # pinecone>=5 liefert Response-Objekte
    try:
        # neuere Clients haben to_dict()
        return res.to_dict()  # type: ignore[attr-defined]
    except Exception:
        vectors = getattr(res, "vectors", None)
        if isinstance(vectors, dict):
            return {"vectors": vectors}
        return {"vectors": {}}


def delete_vectors(
    pc: Pinecone,
    index_name: str,
    namespace: str,
    ids: List[str],
) -> None:
    index = pc.Index(index_name)
    index.delete(ids=ids, namespace=namespace)


def delete_by_filter(
    pc: Pinecone,
    index_name: str,
    namespace: str,
    flt: Dict[str, Any],
) -> None:
    try:
        index = pc.Index(index_name)
        try:
            index.delete(filter=flt, namespace=namespace)
        except Exception as e:
            # Wenn der Namespace nicht existiert, behandeln wir es als "nichts zu löschen".
            try:
                from pinecone.exceptions import NotFoundException  # type: ignore
            except Exception:
                NotFoundException = None  # type: ignore
            if (NotFoundException and isinstance(e, NotFoundException)) or (
                "Namespace not found" in str(e)
            ):
                return
            raise
    except Exception as e:
        # Index selbst existiert nicht → ebenfalls still ignorieren
        try:
            from pinecone.exceptions import NotFoundException  # type: ignore
        except Exception:
            NotFoundException = None  # type: ignore
        if (NotFoundException and isinstance(e, NotFoundException)) or (
            "not found" in str(e).lower()
        ):
            return
        raise

