"""Tests for index compression."""

from __future__ import annotations

import gzip
from pathlib import Path

from pildora_data.compress import compress_index
from pildora_data.index_builder import build_index
from pildora_data.models import DrugProduct, Supplement


def _build_sample_db(tmp_path: Path) -> Path:
    db_path = tmp_path / "test.sqlite"
    drugs = [
        DrugProduct(ndc="001", drug_name="ASPIRIN", generic_name="ASPIRIN",
                    brand_name="BAYER", strength="325 mg/1"),
        DrugProduct(ndc="002", drug_name="LIPITOR", generic_name="ATORVASTATIN CALCIUM",
                    brand_name="LIPITOR", strength="10 mg/1"),
    ]
    supplements = [
        Supplement(id="s1", name="Vitamin D3", ingredients=["CHOLECALCIFEROL"]),
    ]
    build_index(drugs, supplements, db_path)
    return db_path


class TestCompressIndex:
    """Tests for gzip compression of the index."""

    def test_produces_gzip_file(self, tmp_path: Path) -> None:
        db_path = _build_sample_db(tmp_path)
        compressed = compress_index(db_path)

        assert compressed.exists()
        assert compressed.suffix == ".gz"
        # Verify it's valid gzip
        with gzip.open(compressed, "rb") as f:
            data = f.read()
        assert len(data) > 0

    def test_compressed_smaller_than_original(self, tmp_path: Path) -> None:
        db_path = _build_sample_db(tmp_path)
        compressed = compress_index(db_path)

        original_size = db_path.stat().st_size
        compressed_size = compressed.stat().st_size
        assert compressed_size < original_size

    def test_custom_output_path(self, tmp_path: Path) -> None:
        db_path = _build_sample_db(tmp_path)
        custom_path = tmp_path / "custom" / "output.gz"
        compressed = compress_index(db_path, output_path=custom_path)

        assert compressed == custom_path
        assert compressed.exists()

    def test_roundtrip_integrity(self, tmp_path: Path) -> None:
        db_path = _build_sample_db(tmp_path)
        original_bytes = db_path.read_bytes()

        compressed = compress_index(db_path)
        with gzip.open(compressed, "rb") as f:
            decompressed = f.read()

        assert decompressed == original_bytes
