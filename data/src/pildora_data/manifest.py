"""Emit a distribution manifest for the tiered drug index artifacts.

The manifest is the contract between the ETL and the iOS app's tiered loader
(`PildoraDrugIndexLoader`). It is public, non-sensitive metadata about the
plaintext reference-data artifacts — it never references user data.

Contract (``manifest.json``)::

    {
      "schema_version": "1.0",          # index table schema (metadata.schema_version)
      "index_version": "2026.07.02",    # dataset version; app compares to decide updates
      "generated_at": "2026-07-02T…Z",
      "tiers": {
        "core": {                       # informational: what ships in the app bundle
          "filename": "pildora_drugs_core.sqlite.gz",
          "sha256": "…",               # hash of the COMPRESSED (.gz) artifact
          "size_bytes": 12345,          # size of the COMPRESSED artifact
          "uncompressed_sha256": "…",  # hash of the .sqlite after gunzip
          "uncompressed_size_bytes": 67890
        },
        "full": { … }                  # the artifact the app downloads on first launch
      }
    }

The app downloads ``tiers.full.filename`` from a configured base URL, verifies
``sha256`` on the compressed bytes, gunzips, then verifies
``uncompressed_sha256`` before atomically installing it.
"""

from __future__ import annotations

import hashlib
import json
import logging
from datetime import UTC, datetime
from pathlib import Path

from .index_builder import SCHEMA_VERSION

logger = logging.getLogger(__name__)

MANIFEST_FILENAME = "manifest.json"

_CHUNK = 1024 * 1024  # 1 MiB streaming read for hashing large files


def sha256_file(path: Path) -> str:
    """Return the hex SHA-256 digest of a file, read in streaming chunks."""
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(_CHUNK), b""):
            digest.update(chunk)
    return digest.hexdigest()


def build_artifact_descriptor(gz_path: Path, db_path: Path) -> dict[str, str | int]:
    """Describe one tier's artifacts for the manifest.

    Args:
        gz_path: The compressed ``.gz`` file the app downloads.
        db_path: The uncompressed ``.sqlite`` file (post-gunzip target).

    Returns:
        A descriptor dict with filename + hashes + sizes for both forms.
    """
    return {
        "filename": gz_path.name,
        "sha256": sha256_file(gz_path),
        "size_bytes": gz_path.stat().st_size,
        "uncompressed_sha256": sha256_file(db_path),
        "uncompressed_size_bytes": db_path.stat().st_size,
    }


def emit_manifest(
    output_dir: Path,
    index_version: str,
    *,
    core_gz: Path,
    core_db: Path,
    full_gz: Path,
    full_db: Path,
    schema_version: str = SCHEMA_VERSION,
    manifest_name: str = MANIFEST_FILENAME,
) -> Path:
    """Write ``manifest.json`` describing the core + full tier artifacts.

    Args:
        output_dir: Directory to write the manifest into.
        index_version: Dataset version stamp (shared by both tiers).
        core_gz / core_db: Compressed + uncompressed core index paths.
        full_gz / full_db: Compressed + uncompressed full index paths.
        schema_version: Index schema version (defaults to the builder's).
        manifest_name: Output filename (defaults to ``manifest.json``).

    Returns:
        Path to the written manifest file.
    """
    output_dir.mkdir(parents=True, exist_ok=True)
    manifest = {
        "schema_version": schema_version,
        "index_version": index_version,
        "generated_at": datetime.now(tz=UTC).isoformat(),
        "tiers": {
            "core": build_artifact_descriptor(core_gz, core_db),
            "full": build_artifact_descriptor(full_gz, full_db),
        },
    }
    manifest_path = output_dir / manifest_name
    manifest_json = json.dumps(manifest, indent=2, sort_keys=True) + "\n"
    manifest_path.write_text(manifest_json, encoding="utf-8")
    logger.info("Wrote manifest → %s (index_version=%s)", manifest_path, index_version)
    return manifest_path
