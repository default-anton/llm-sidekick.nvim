"""Code indexing service for semantic search."""

from pathlib import Path
from typing import Any
import logging
import gc

from pymilvus import MilvusClient, FieldSchema, DataType, CollectionSchema
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
        self.db_path: str = db_path or str(Path.home() / ".milvus_lite.db")

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
            uri=self.db_path,
        )

        self._setup_collection()

    def _setup_collection(self):
        """Create Milvus collection if it doesn't exist."""
        if self.milvus.has_collection(self.collection_name):
            logger.info(f"Using existing collection: {self.collection_name}")
        else:
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

            self.milvus.create_collection(
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

    def _clear_gpu_memory(self):
        """Clear GPU memory cache based on the device type."""
        if self.device == "cuda":
            torch.cuda.empty_cache()
        elif self.device == "mps":
            # MPS (Apple Silicon) doesn't have a direct equivalent to empty_cache
            # But we can force garbage collection to help free memory
            gc.collect()
        
        # Force Python garbage collection regardless of device
        gc.collect()

    def _generate_embeddings(self, texts: list[str]) -> list[list[float]]:
        """Generate embeddings for a batch of texts using the model."""
        try:
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
                
                # Move to CPU and convert to Python list
                result = embeddings.cpu().numpy().tolist()
                
                # Explicitly delete tensors to free memory
                del outputs
                del embeddings
                for tensor in inputs.values():
                    del tensor
                del inputs
                
                # Clear GPU memory cache
                self._clear_gpu_memory()
                
                return result
        except Exception as e:
            logger.error(f"Error generating embeddings: {str(e)}")
            # Clear GPU memory on error as well
            self._clear_gpu_memory()
            raise

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

        batch_size = 8
        total_chunks = len(source_codes)
        total_batches = (total_chunks + batch_size - 1) // batch_size  # Ceiling division

        logger.info(f"Indexing {total_chunks} code chunks in {total_batches} batches (size: {batch_size})")

        for batch_idx in range(0, total_chunks, batch_size):
            batch_end = min(batch_idx + batch_size, total_chunks)
            batch_num = batch_idx // batch_size + 1

            logger.debug(f"Processing batch {batch_num}/{total_batches} (chunks {batch_idx+1}-{batch_end})")

            # Extract the current batch
            batch_source_codes = source_codes[batch_idx:batch_end]
            batch_file_paths = file_paths[batch_idx:batch_end]
            batch_languages = languages[batch_idx:batch_end]
            batch_metadatas = metadatas[batch_idx:batch_end]

            try:
                # Generate embeddings for this batch
                batch_embeddings = self._generate_embeddings(batch_source_codes)

                # Create records for this batch
                batch_data = [
                    {
                        "embedding": batch_embeddings[i],
                        "source_code": batch_source_codes[i],
                        "file_path": batch_file_paths[i],
                        "language": batch_languages[i],
                        "metadata": batch_metadatas[i] or {}
                    }
                    for i in range(len(batch_source_codes))
                ]

                # Insert this batch into Milvus
                self.milvus.insert(collection_name=self.collection_name, data=batch_data)

                logger.debug(f"Successfully indexed batch {batch_num}/{total_batches}")
                
                # Clean up references to help garbage collection
                del batch_embeddings
                del batch_data
                
                # Force garbage collection after each batch
                gc.collect()
                self._clear_gpu_memory()

            except Exception as e:
                logger.error(f"Error processing batch {batch_num}/{total_batches}: {str(e)}")
                # Clear memory on error
                self._clear_gpu_memory()
                # Continue with the next batch instead of failing completely
                continue

        logger.info(f"Completed indexing {total_chunks} code chunks")

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
        
        # Clean up after search
        del query_embeddings
        self._clear_gpu_memory()

        return results[0]
