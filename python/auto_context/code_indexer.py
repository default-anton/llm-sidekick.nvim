"""Code indexing service for semantic search."""

from pathlib import Path
from typing import Any
import logging

from milvus import MilvusClient, FieldSchema, DataType, CollectionSchema
import torch.nn.functional as F
from transformers import AutoModel, AutoTokenizer
import torch

logger = logging.getLogger(__name__)

class CodeIndexer:
    """Manages code indexing and semantic search using Milvus."""

    def __init__(
        self,
        model_name: str = "Alibaba-NLP/gte-modernbert-base",
        collection_name: str = "code_chunks",
        db_path: str | None = None,
    ):
        """Initialize the code indexer.

        Args:
            model_name: HuggingFace model name for embeddings
            collection_name: Name of the Milvus collection
            db_path: Path to Milvus database files
        """
        self.model_name: str = model_name
        self.collection_name: str = collection_name
        self.db_path: str = db_path or str(Path.home() / ".milvus-lite.db")

        self.device: str
        if torch.cuda.is_available():
            self.device = "cuda"
        elif hasattr(torch.backends, "mps") and torch.backends.mps.is_available():
            self.device = "mps"
        else:
            self.device = "cpu"
        logger.info(f"Using device: {self.device}")

        self.model: AutoModel = AutoModel.from_pretrained(model_name).to(self.device)
        self.tokenizer: AutoTokenizer = AutoTokenizer.from_pretrained(model_name)

        self.milvus: MilvusClient = MilvusClient(
            uri="lite://" + self.db_path,
        )

        self._setup_collection()

    def _setup_collection(self):
        """Create Milvus collection if it doesn't exist."""
        if not self.milvus.list_collections().get(self.collection_name):
            fields: list[FieldSchema] = [
                FieldSchema(
                    name="id",
                    dtype=DataType.INT64,
                    is_primary=True,
                    auto_id=True
                ),
                FieldSchema(
                    name="embedding",
                    dtype=DataType.FLOAT_VECTOR,
                    dim=768
                ),
                FieldSchema(
                    name="source_code",
                    dtype=DataType.VARCHAR,
                    max_length=65535
                ),
                FieldSchema(
                    name="file_path",
                    dtype=DataType.VARCHAR,
                    max_length=2048
                ),
                FieldSchema(
                    name="language",
                    dtype=DataType.VARCHAR,
                    max_length=32
                ),
                # Store additional metadata like:
                # - line numbers
                # - git info
                # - function/class names
                # - imports
                FieldSchema(
                    name="metadata",
                    dtype=DataType.JSON,
                ),
            ]

            schema: CollectionSchema = CollectionSchema(
                fields=fields,
                description="Code chunks with semantic embeddings",
                enable_dynamic_field=False
            )

            self.collection = self.milvus.create_collection(
                collection_name=self.collection_name,
                schema=schema,
                index_params={
                    "field_name": "embedding",
                    "index_type": "IVF_FLAT",
                    "metric_type": "L2",
                    "params": {"nlist": 1024}
                }
            )
            logger.info(f"Created collection: {self.collection_name}")
        else:
            self.collection = self.milvus.get_collection(self.collection_name)
            logger.info(f"Using existing collection: {self.collection_name}")

    def _generate_embeddings(self, texts: list[str]) -> list[list[float]]:
        """Generate embeddings for a batch of texts using the model."""
        # Tokenize and encode
        inputs: dict[str, torch.Tensor] = self.tokenizer(
            texts,
            padding=True,
            truncation=True,
            max_length=8192,
            return_tensors="pt"
        ).to(self.device)

        # Generate embeddings
        with torch.no_grad():
            outputs: torch.Tensor = self.model(**inputs)
            embeddings: torch.Tensor = outputs.last_hidden_state[:, 0]
            embeddings = F.normalize(embeddings, p=2, dim=1)

        return embeddings.cpu().numpy().tolist()

    def index_code(
        self,
        source_codes: list[str],
        file_paths: list[str],
        languages: list[str],
        metadatas: None | list[dict[str, Any]] = None
    ) -> None:
        """Index a batch of code chunks with their metadata.

        Args:
            source_codes: List of code chunks to index
            file_paths: List of file paths corresponding to each code chunk
            languages: List of programming languages for each chunk
            metadatas: Optional list of metadata dictionaries for each chunk
        """
        if not source_codes:
            return

        if metadatas is None:
            metadatas = [{}] * len(source_codes)

        if not (len(source_codes) == len(file_paths) == len(languages) == len(metadatas)):
            raise ValueError("All input lists must have the same length")

        embeddings = self._generate_embeddings(source_codes)

        self.milvus.insert(
            collection_name=self.collection_name,
            data={
                "embedding": embeddings,
                "source_code": source_codes,
                "file_path": file_paths,
                "language": languages,
                "metadata": [m or {} for m in metadatas]
            }
        )

    def search(
        self,
        query: str,
        limit: int = 5,
        language: str | None = None
    ) -> list[dict[str, Any]]:
        """Search for similar code chunks."""
        query_embeddings = self._generate_embeddings([query])

        expr = None
        if language:
            expr = f"language == '{language}'"

        results: list[dict[str, Any]] = self.milvus.search(
            collection_name=self.collection_name,
            data=query_embeddings,
            limit=limit,
            expr=expr,
            output_fields=["source_code", "file_path", "language", "metadata"]
        )

        return results[0]
