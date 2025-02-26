#!/usr/bin/env python3
"""Command-line interface for code indexing."""

import argparse
import logging
import os
import sys
from typing import Any

from .file_discovery import FileDiscovery
from .code_chunker import chunk_code, EXTENSION_TO_LANGUAGE
from .code_indexer import CodeIndexer
from .utils import get_default_db_path

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    handlers=[logging.StreamHandler()]
)
logger = logging.getLogger(__name__)


def read_file(path: str) -> str:
    """Read file content safely.

    Args:
        path: Path to the file

    Returns:
        File content as string

    Raises:
        IOError: If file cannot be read
    """
    try:
        with open(path, "r", encoding="utf-8") as f:
            return f.read()
    except UnicodeDecodeError:
        # Try with latin-1 encoding if utf-8 fails
        try:
            with open(path, "r", encoding="latin-1") as f:
                return f.read()
        except Exception as e:
            logger.warning(f"Failed to read file {path} with latin-1 encoding: {e}")
            raise IOError(f"Cannot read file {path}") from e
    except Exception as e:
        logger.warning(f"Failed to read file {path}: {e}")
        raise IOError(f"Cannot read file {path}") from e


def get_language_from_path(path: str) -> str:
    """Determine language from file extension.

    Args:
        path: Path to the file

    Returns:
        Language name or "text" if unknown
    """
    ext = path.split(".")[-1].lower()
    return EXTENSION_TO_LANGUAGE.get(ext, "text")


def index_repository(
    repo_path: str,
    batch_size: int = 30,
    model_name: str = "Alibaba-NLP/gte-modernbert-base",
    db_path: str | None = None,
) -> None:
    """Index all code files in the repository.

    Args:
        repo_path: Path to the repository
        batch_size: Number of files to process in each batch
        model_name: HuggingFace model name for embeddings
        db_path: Path to Milvus database files
    """

    if not db_path or db_path == "":
        db_path = get_default_db_path()

    # Initialize components
    file_discovery = FileDiscovery(batch_size=batch_size)
    code_indexer = CodeIndexer(model_name=model_name, db_path=db_path)

    # Start indexing
    logger.info(f"Starting indexing of repository: {repo_path}")
    logger.info(f"Using batch size: {batch_size}")
    
    total_files_processed = 0
    total_chunks_indexed = 0

    # Process files in batches
    for batch_num, file_batch in enumerate(file_discovery.find_files(repo_path), 1):
        logger.info(f"Processing batch {batch_num} with {len(file_batch)} files")
        
        # Lists to collect data for batch indexing
        source_codes: list[str] = []
        file_paths: list[str] = []
        languages: list[str] = []
        metadatas: list[dict[str, Any]] = []
        
        # Process each file in the batch
        for file_path in file_batch:
            try:
                # Read file content
                content = read_file(file_path)
                language = get_language_from_path(file_path)
                
                # Chunk the code
                chunks = chunk_code(content, file_path)
                
                # Add chunks to batch
                for chunk in chunks:
                    source_codes.append(chunk.content)
                    file_paths.append(chunk.file_path)
                    languages.append(language)
                    metadatas.append({
                        "start_line": chunk.start,
                        "end_line": chunk.end,
                        "file_path": chunk.file_path,
                    })
                
                total_files_processed += 1
                total_chunks_indexed += len(chunks)
                
            except Exception as e:
                logger.error(f"Error processing file {file_path}: {e}")
                continue
        
        # Index the batch if we have any chunks
        if source_codes:
            try:
                code_indexer.index_code(
                    source_codes=source_codes,
                    file_paths=file_paths,
                    languages=languages,
                    metadatas=metadatas
                )
                logger.info(f"Indexed {len(source_codes)} chunks from batch {batch_num}")
            except Exception as e:
                logger.error(f"Error indexing batch {batch_num}: {e}")
    
    logger.info(f"Indexing completed. Processed {total_files_processed} files and indexed {total_chunks_indexed} chunks.")


def main():
    """Main entry point for the CLI."""
    parser = argparse.ArgumentParser(description="Index code repository for semantic search")
    parser.add_argument(
        "repo_path",
        help="Path to the repository to index",
        default=".",
        nargs="?"
    )
    parser.add_argument(
        "--batch-size",
        type=int,
        default=30,
        help="Number of files to process in each batch"
    )
    parser.add_argument(
        "--model",
        type=str,
        default="Alibaba-NLP/gte-modernbert-base",
        help="HuggingFace model name for embeddings"
    )
    parser.add_argument(
        "--db-path",
        type=str,
        help="Path to Milvus database files (default: ~/.local/state/nvim/llm-sidekick/milvus-lite.db)"
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Enable verbose logging"
    )

    args = parser.parse_args()

    # Set log level
    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)

    # Convert repo_path to absolute path
    repo_path = os.path.abspath(args.repo_path)
    
    # Validate repo_path
    if not os.path.isdir(repo_path):
        logger.error(f"Repository path does not exist or is not a directory: {repo_path}")
        sys.exit(1)

    try:
        index_repository(
            repo_path=repo_path,
            batch_size=args.batch_size,
            model_name=args.model,
            db_path=args.db_path
        )
    except Exception as e:
        logger.error(f"Indexing failed: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
