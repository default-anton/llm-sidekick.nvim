#!/usr/bin/env python3
"""Command-line interface for searching indexed code."""

import argparse
import logging
import sys
from typing import Any, Dict, List

from auto_context.code_indexer import CodeIndexer
from auto_context.utils import get_default_db_path

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    handlers=[logging.StreamHandler()]
)
logger = logging.getLogger(__name__)

def search_code(
    query: str,
    limit: int = 5,
    language: str | None = None,
    similarity_threshold: float = 0.71,
    db_path: str | None = None,
) -> List[Dict[str, Any]]:
    """Search for code in the index that matches the query.

    Args:
        query: The search query
        limit: Maximum number of results to return
        language: Optional language filter
        similarity_threshold: Minimum similarity score (0-1)
        db_path: Path to Milvus database files

    Returns:
        List of search results above the similarity threshold
    """
    if not db_path or db_path == "":
        db_path = get_default_db_path()

    # Initialize code indexer
    code_indexer = CodeIndexer(db_path=db_path)

    # Search with a higher limit since we'll filter by threshold
    search_limit = limit * 2
    results = code_indexer.search(query=query, limit=search_limit, language=language)

    # Filter results by similarity threshold
    # Milvus returns similarity score (IP) where higher values mean more similar
    filtered_results = [
        result for result in results
        if result["distance"] >= similarity_threshold  # Higher distance means more similar in IP similarity
    ]

    # Return only up to the requested limit
    return filtered_results[:limit]

def display_results(results: List[Dict[str, Any]]) -> None:
    """Format and display search results.

    Args:
        results: List of search results
    """
    if not results:
        print("No matching results found.")
        return

    print(f"Found {len(results)} matching results:\n")

    for i, result in enumerate(results, 1):
        # Extract data from result
        file_path = result["entity"]["file_path"]
        score = result["distance"]
        source_code = result["entity"]["source_code"]

        # Get line numbers if available in metadata
        metadata = result["entity"].get("metadata", {})
        start_line = metadata.get("start_line", "?")
        end_line = metadata.get("end_line", "?")

        # Format and print the result
        print(f"Result {i} (similarity: {score:.2f}):")
        print(f"File: {file_path} (lines {start_line}-{end_line})")
        print("-" * 80)
        print(source_code)
        print("=" * 80)
        print()

def main():
    """Main entry point for the CLI."""
    parser = argparse.ArgumentParser(description="Search indexed code repository")
    parser.add_argument(
        "query",
        help="Search query"
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=5,
        help="Maximum number of results to return"
    )
    parser.add_argument(
        "--language",
        type=str,
        help="Filter results by programming language"
    )
    parser.add_argument(
        "--threshold",
        type=float,
        default=0.71,
        help="Minimum similarity threshold (0-1)"
    )
    parser.add_argument(
        "--db-path",
        type=str,
        help="Path to Milvus database files (default: ~/.local/state/nvim/llm-sidekick/milvus_lite.db)"
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

    try:
        results = search_code(
            query=args.query,
            limit=args.limit,
            language=args.language,
            similarity_threshold=args.threshold,
            db_path=args.db_path
        )
        display_results(results)
    except Exception as e:
        logger.error(f"Search failed: {e}", exc_info=True)
        sys.exit(1)

if __name__ == "__main__":
    main()
