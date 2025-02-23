"""Code indexing service for semantic search."""

from pathlib import Path
from typing import List, Optional, Dict, Any
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
        db_path: Optional[str] = None,
    ):
        """Initialize the code indexer.
        
        Args:
            model_name: HuggingFace model name for embeddings
            collection_name: Name of the Milvus collection
            db_path: Path to Milvus database files
        """
        self.model_name = model_name
        self.collection_name = collection_name
        self.db_path = db_path or str(Path.home() / ".milvus-lite.db")
        
        if torch.cuda.is_available():
            self.device = "cuda"
        elif hasattr(torch.backends, "mps") and torch.backends.mps.is_available():
            self.device = "mps"
        else:
            self.device = "cpu"
        logger.info(f"Using device: {self.device}")
        
        self.model = AutoModel.from_pretrained(model_name).to(self.device)
        self.tokenizer = AutoTokenizer.from_pretrained(model_name)
        
        self.milvus = MilvusClient(
            uri="lite://" + self.db_path,
        )
        
        self._setup_collection()

    def _setup_collection(self):
        """Create Milvus collection if it doesn't exist."""
        if not self.milvus.list_collections().get(self.collection_name):
            fields = [
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
                FieldSchema(
                    name="metadata",
                    dtype=DataType.JSON,
                    # Store additional metadata like:
                    # - line numbers
                    # - git info
                    # - function/class names
                    # - imports
                ),
            ]
            
            schema = CollectionSchema(
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

    def _generate_embeddings(self, texts: List[str]) -> List[List[float]]:
        """Generate embeddings for a batch of texts using the model."""
        # Tokenize and encode
        inputs = self.tokenizer(
            texts,
            padding=True,
            truncation=True,
            max_length=8192,
            return_tensors="pt"
        ).to(self.device)
        
        # Generate embeddings
        with torch.no_grad():
            outputs = self.model(**inputs)
            embeddings = outputs.last_hidden_state[:, 0]
            embeddings = F.normalize(embeddings, p=2, dim=1)
        
        return embeddings.cpu().numpy().tolist()

    def index_code(
        self,
        codes: List[str],
        file_paths: List[str],
        languages: List[str],
        metadatas: Optional[List[Dict[str, Any]]] = None
    ) -> None:
        """Index a batch of code chunks with their metadata.
        
        Args:
            codes: List of code chunks to index
            file_paths: List of file paths corresponding to each code chunk
            languages: List of programming languages for each chunk
            metadatas: Optional list of metadata dictionaries for each chunk
        """
        if not codes:
            return
            
        if metadatas is None:
            metadatas = [None] * len(codes)
            
        if not (len(codes) == len(file_paths) == len(languages) == len(metadatas)):
            raise ValueError("All input lists must have the same length")
            
        embeddings = self._generate_embeddings(codes)
        
        self.milvus.insert(
            collection_name=self.collection_name,
            data={
                "embedding": embeddings,
                "code": codes,
                "file_path": file_paths,
                "language": languages,
                "metadata": [m or {} for m in metadatas]
            }
        )

    def search(
        self,
        query: str,
        limit: int = 5,
        language: Optional[str] = None
    ) -> List[Dict[str, Any]]:
        """Search for similar code chunks."""
        query_embedding = self._generate_embedding(query)
        
        expr = None
        if language:
            expr = f"language == '{language}'"
        
        results = self.milvus.search(
            collection_name=self.collection_name,
            data=[query_embedding],
            limit=limit,
            expr=expr,
            output_fields=["code", "file_path", "language", "metadata"]
        )
        
        return results[0]
