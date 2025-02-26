#!/usr/bin/env python3
"""
Test script to compare different chunking strategies.
"""

from auto_context.code_chunker import chunk_code
import os
import sys
from pathlib import Path

def print_separator(title=None):
    """Print a separator line with optional title."""
    width = 80
    if title:
        print(f"\n{'-' * 10} {title} {'-' * (width - 13 - len(title))}")
    else:
        print(f"\n{'-' * width}")

def test_chunking(file_path):
    """Test code chunking on a file."""
    print_separator(f"Testing chunking on {os.path.basename(file_path)}")

    with open(file_path, 'r') as f:
        source_code = f.read()

    chunks = chunk_code(source_code, file_path)

    print(f"Total chunks: {len(chunks)}")
    print(f"Average chunk size: {sum(len(chunk.content) for chunk in chunks) / len(chunks):.1f} characters")
    print(f"Average chunk lines: {sum(chunk.content.count('\\n') + 1 for chunk in chunks) / len(chunks):.1f} lines")

    # Print sample of chunks
    for i, chunk in enumerate(chunks):
        print_separator(f"Chunk {i+1}/{len(chunks)}")
        print(f"Lines: {chunk.start+1}-{chunk.end+1} ({chunk.end - chunk.start} lines)")
        print(f"Size: {len(chunk.content)} characters")
        print(chunk.content)

if __name__ == "__main__":
    # Use the file provided as argument, or default to code_indexer.py
    if len(sys.argv) > 1:
        file_path = sys.argv[1]
    else:
        file_path = str(Path(__file__).parent / "auto_context" / "code_indexer.py")

    # Test with structure preservation (default)
    test_chunking(file_path)
