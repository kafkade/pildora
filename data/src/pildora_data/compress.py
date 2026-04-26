"""Compress the SQLite index for distribution."""

from __future__ import annotations

import gzip
import shutil
from pathlib import Path


def compress_index(db_path: Path, output_path: Path | None = None) -> Path:
    """Compress the index with gzip for distribution.

    Args:
        db_path: Path to the SQLite database file.
        output_path: Optional output path. Defaults to ``<db_path>.gz``.

    Returns:
        Path to the compressed file.
    """
    output = output_path or db_path.with_suffix(db_path.suffix + ".gz")
    output.parent.mkdir(parents=True, exist_ok=True)
    with open(db_path, "rb") as f_in, gzip.open(output, "wb", compresslevel=9) as f_out:
        shutil.copyfileobj(f_in, f_out)
    return output
