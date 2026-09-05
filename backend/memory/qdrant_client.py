import os
import uuid

from fastembed import TextEmbedding
from qdrant_client import QdrantClient
from qdrant_client.http import models as qmodels


class QdrantMemoryClient:
    """Drop-in replacement for the old HydraDB-backed memory client.

    Same partitioning model HydraDB used (tenant_id + sub_tenant_id): every
    point's payload carries tenant_id/user_id and every query filters on
    both, so one collection safely serves multiple tenants/users. Unlike
    HydraDB, upsert/search are synchronous here — no ingest-then-poll-until-
    indexed step is needed.
    """

    COLLECTION = "dealscout_memories"
    # all-MiniLM-L6-v2 output size (fastembed's default model).
    VECTOR_SIZE = 384

    def __init__(self, tenant_id: str | None = None):
        self.tenant_id = tenant_id or os.environ.get("MEMORY_TENANT_ID", "dealscout")
        self.client = QdrantClient(url=os.environ.get("QDRANT_URL", "http://localhost:6333"))
        self._embedder = TextEmbedding(model_name="BAAI/bge-small-en-v1.5")
        self._ensure_collection()

    def _ensure_collection(self) -> None:
        if self.client.collection_exists(self.COLLECTION):
            return
        self.client.create_collection(
            collection_name=self.COLLECTION,
            vectors_config=qmodels.VectorParams(
                size=self.VECTOR_SIZE, distance=qmodels.Distance.COSINE
            ),
        )

    def _embed(self, text: str) -> list[float]:
        return next(iter(self._embedder.embed([text]))).tolist()

    def _tenant_filter(self, user_id: str) -> qmodels.Filter:
        return qmodels.Filter(
            must=[
                qmodels.FieldCondition(
                    key="tenant_id", match=qmodels.MatchValue(value=self.tenant_id)
                ),
                qmodels.FieldCondition(
                    key="user_id", match=qmodels.MatchValue(value=user_id)
                ),
            ]
        )

    def remember(self, user_id: str, text: str, metadata: dict | None = None) -> None:
        """Ingest a stated preference (e.g. a rejection reason)."""
        self.client.upsert(
            collection_name=self.COLLECTION,
            points=[
                qmodels.PointStruct(
                    id=str(uuid.uuid4()),
                    vector=self._embed(text),
                    payload={
                        "tenant_id": self.tenant_id,
                        "user_id": user_id,
                        "text": text,
                        **(metadata or {}),
                    },
                )
            ],
        )

    def recall(self, user_id: str, query: str, limit: int = 10) -> str:
        """Natural-language query for memories relevant to this category."""
        hits = self.client.query_points(
            collection_name=self.COLLECTION,
            query=self._embed(query),
            query_filter=self._tenant_filter(user_id),
            limit=limit,
        ).points
        return "\n".join(hit.payload["text"] for hit in hits)

    def replace_preferences(self, user_id: str, texts: list[str]) -> None:
        """Replace a user's entire preference set with a fresh batch."""
        self.forget_all(user_id)
        if not texts:
            return
        self.client.upsert(
            collection_name=self.COLLECTION,
            points=[
                qmodels.PointStruct(
                    id=str(uuid.uuid4()),
                    vector=self._embed(text),
                    payload={"tenant_id": self.tenant_id, "user_id": user_id, "text": text},
                )
                for text in texts
            ],
        )

    def forget_all(self, user_id: str) -> int:
        """Delete every stored memory for a user (used by 'New Session')."""
        existing, _ = self.client.scroll(
            collection_name=self.COLLECTION,
            scroll_filter=self._tenant_filter(user_id),
            limit=10_000,
            with_payload=False,
            with_vectors=False,
        )
        ids = [point.id for point in existing]
        if not ids:
            return 0
        self.client.delete(
            collection_name=self.COLLECTION,
            points_selector=qmodels.PointIdsList(points=ids),
        )
        return len(ids)
