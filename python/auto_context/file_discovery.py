"""File discovery and batching functionality for code indexing."""

import subprocess
from pathlib import Path
from collections.abc import Iterator
import logging

from auto_context.code_chunker import EXTENSION_TO_LANGUAGE

logger = logging.getLogger(__name__)

class FileBatcher:
    """Handles batched processing of files."""

    def __init__(self, batch_size: int = 30):
        """Initialize the file batcher.

        Args:
            batch_size: Number of files to process in each batch
        """
        self.batch_size: int = batch_size

    def batch_files(self, files: list[str]) -> Iterator[list[str]]:
        """Yield batches of files.

        Args:
            files: List of file paths to batch

        Yields:
            Batches of file paths
        """
        for i in range(0, len(files), self.batch_size):
            yield files[i:i + self.batch_size]

class FileDiscovery:
    """Handles file discovery and filtering."""

    SUPPORTED_EXTENSIONS: list[str] = list(EXTENSION_TO_LANGUAGE.keys())

    def __init__(
        self,
        extensions: list[str] | None = None,
        batch_size: int = 30
    ):
        """Initialize the file discovery service.

        Args:
            extensions: Optional list of file extensions to include
            batch_size: Number of files to process in each batch
        """
        self.extensions: list[str] = extensions or self.SUPPORTED_EXTENSIONS
        self.batcher: FileBatcher = FileBatcher(batch_size)

    def _build_fd_command(self, directory: str) -> list[str]:
        """Build the fd command with appropriate extensions.

        Args:
            directory: Directory to search in

        Returns:
            List of command parts for subprocess
        """
        cmd = [
            "fd",
            "",
            "--type", "f",
            "--hidden",
            "--exclude", ".git",
            "--exclude", "node_modules",
        ]

        for ext in self.extensions:
            cmd.extend(["-e", ext])

        cmd.append(directory)

        return cmd

    def find_files(self, directory: str) -> Iterator[list[str]]:
        """Find all relevant files in the directory and yield in batches.

        Args:
            directory: Directory to search in

        Yields:
            Batches of file paths

        Raises:
            RuntimeError: If fd command fails
        """
        try:
            cmd = self._build_fd_command(directory)
            logger.debug(f"Running command: {' '.join(cmd)}")

            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                check=True
            )

            files = [
                str(Path(f).resolve())
                for f in result.stdout.splitlines()
                if f.strip()
            ]

            logger.info(f"Found {len(files)} files to process")

            yield from self.batcher.batch_files(files)

        except subprocess.CalledProcessError as e:
            logger.error(f"Failed to run fd command: {e}")
            logger.error(f"stderr: {str(e.stderr)}")
            raise RuntimeError("Failed to discover files") from e
