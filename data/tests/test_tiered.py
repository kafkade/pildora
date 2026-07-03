"""Tests for the tiered (core/full) index split and manifest emission."""

from __future__ import annotations

import gzip
import json
import sqlite3
from pathlib import Path

from pildora_data.index_builder import (
    build_core_index,
    build_index,
    default_index_version,
    select_core_drugs,
    select_core_generic_keys,
)
from pildora_data.manifest import (
    build_artifact_descriptor,
    emit_manifest,
    sha256_file,
)
from pildora_data.models import DrugProduct, Supplement


def _drug(ndc: str, generic: str, brand: str = "") -> DrugProduct:
    return DrugProduct(ndc=ndc, drug_name=brand or generic, generic_name=generic, brand_name=brand)


def _skewed_drugs() -> list[DrugProduct]:
    """Drugs where 'ibuprofen' has 3 products, 'atorvastatin' 2, others 1."""
    return [
        _drug("001", "IBUPROFEN", "ADVIL"),
        _drug("002", "IBUPROFEN", "MOTRIN"),
        _drug("003", "IBUPROFEN", ""),
        _drug("004", "ATORVASTATIN CALCIUM", "LIPITOR"),
        _drug("005", "ATORVASTATIN CALCIUM", ""),
        _drug("006", "METFORMIN", "GLUCOPHAGE"),
        _drug("007", "LISINOPRIL", "ZESTRIL"),
    ]


class TestCoreSelection:
    def test_selects_top_n_by_product_count(self) -> None:
        keys = select_core_generic_keys(_skewed_drugs(), limit=2)
        assert keys == {"ibuprofen", "atorvastatin calcium"}

    def test_core_drugs_are_subset_of_full(self) -> None:
        drugs = _skewed_drugs()
        core = select_core_drugs(drugs, limit=2)
        # Every core product is one of the originals.
        assert all(d in drugs for d in core)
        # Ibuprofen (3) + Atorvastatin (2) products kept.
        assert len(core) == 5

    def test_limit_larger_than_data_keeps_all(self) -> None:
        drugs = _skewed_drugs()
        core = select_core_drugs(drugs, limit=999)
        assert len(core) == len(drugs)

    def test_zero_limit_keeps_no_drugs(self) -> None:
        assert select_core_drugs(_skewed_drugs(), limit=0) == []


class TestBuildCoreIndex:
    def test_core_index_has_fewer_concepts_than_full(self, tmp_path: Path) -> None:
        drugs = _skewed_drugs()
        supplements = [Supplement(id="s1", name="Vitamin D3", ingredients=["cholecalciferol"])]

        full_db = tmp_path / "full.sqlite"
        core_db = tmp_path / "core.sqlite"
        build_index(drugs, supplements, full_db, index_version="2026.01.01")
        build_core_index(drugs, supplements, core_db, limit=2, index_version="2026.01.01")

        full_concepts = _count(full_db, "drug_concepts")
        core_concepts = _count(core_db, "drug_concepts")
        assert full_concepts == 4  # ibuprofen, atorvastatin, metformin, lisinopril
        assert core_concepts == 2  # only the top 2

    def test_core_keeps_all_supplements(self, tmp_path: Path) -> None:
        drugs = _skewed_drugs()
        supplements = [
            Supplement(id="s1", name="Vitamin D3", ingredients=["cholecalciferol"]),
            Supplement(id="s2", name="Fish Oil", ingredients=["omega-3"]),
        ]
        core_db = tmp_path / "core.sqlite"
        build_core_index(drugs, supplements, core_db, limit=1)
        assert _count(core_db, "supplements") == 2

    def test_core_concept_set_is_subset_of_full(self, tmp_path: Path) -> None:
        drugs = _skewed_drugs()
        full_db = tmp_path / "full.sqlite"
        core_db = tmp_path / "core.sqlite"
        build_index(drugs, [], full_db)
        build_core_index(drugs, [], core_db, limit=2)

        assert _generic_names(core_db).issubset(_generic_names(full_db))


class TestIndexVersion:
    def test_default_version_is_date_shaped(self) -> None:
        version = default_index_version()
        parts = version.split(".")
        assert len(parts) == 3
        assert all(p.isdigit() for p in parts)

    def test_version_written_to_metadata(self, tmp_path: Path) -> None:
        db = tmp_path / "v.sqlite"
        build_index([_drug("001", "IBUPROFEN")], [], db, index_version="2030.12.31")
        assert _meta(db, "index_version") == "2030.12.31"

    def test_core_and_full_share_version(self, tmp_path: Path) -> None:
        drugs = _skewed_drugs()
        full_db = tmp_path / "full.sqlite"
        core_db = tmp_path / "core.sqlite"
        version = "2026.05.05"
        build_index(drugs, [], full_db, index_version=version)
        build_core_index(drugs, [], core_db, limit=2, index_version=version)
        assert _meta(full_db, "index_version") == _meta(core_db, "index_version") == version


class TestManifest:
    def test_sha256_matches_hashlib(self, tmp_path: Path) -> None:
        import hashlib

        f = tmp_path / "blob.bin"
        f.write_bytes(b"pildora" * 1000)
        assert sha256_file(f) == hashlib.sha256(f.read_bytes()).hexdigest()

    def test_descriptor_fields(self, tmp_path: Path) -> None:
        db = tmp_path / "core.sqlite"
        build_index([_drug("001", "IBUPROFEN")], [], db)
        gz = tmp_path / "core.sqlite.gz"
        with open(db, "rb") as fi, gzip.open(gz, "wb") as fo:
            fo.write(fi.read())

        desc = build_artifact_descriptor(gz, db)
        assert desc["filename"] == "core.sqlite.gz"
        assert desc["size_bytes"] == gz.stat().st_size
        assert desc["uncompressed_size_bytes"] == db.stat().st_size
        assert desc["sha256"] == sha256_file(gz)
        assert desc["uncompressed_sha256"] == sha256_file(db)

    def test_emit_manifest_structure_and_hashes(self, tmp_path: Path) -> None:
        drugs = _skewed_drugs()
        full_db = tmp_path / "pildora_drugs_full.sqlite"
        core_db = tmp_path / "pildora_drugs_core.sqlite"
        build_index(drugs, [], full_db, index_version="2026.02.02")
        build_core_index(drugs, [], core_db, limit=2, index_version="2026.02.02")

        full_gz = _gzip(full_db)
        core_gz = _gzip(core_db)

        manifest_path = emit_manifest(
            tmp_path,
            "2026.02.02",
            core_gz=core_gz,
            core_db=core_db,
            full_gz=full_gz,
            full_db=full_db,
        )
        manifest = json.loads(manifest_path.read_text())

        assert manifest["schema_version"] == "1.0"
        assert manifest["index_version"] == "2026.02.02"
        assert "generated_at" in manifest
        assert set(manifest["tiers"]) == {"core", "full"}
        # Hash in the manifest must match the on-disk artifact.
        assert manifest["tiers"]["full"]["sha256"] == sha256_file(full_gz)
        assert manifest["tiers"]["full"]["uncompressed_sha256"] == sha256_file(full_db)
        assert manifest["tiers"]["core"]["filename"] == "pildora_drugs_core.sqlite.gz"

    def test_manifest_gz_hash_verifies_after_gunzip(self, tmp_path: Path) -> None:
        """Simulate the app's verify path: hash gz, gunzip, hash the db."""
        db = tmp_path / "pildora_drugs_full.sqlite"
        build_index([_drug("001", "IBUPROFEN")], [], db)
        gz = _gzip(db)
        core_db = tmp_path / "pildora_drugs_core.sqlite"
        build_core_index([_drug("001", "IBUPROFEN")], [], core_db, limit=1)
        core_gz = _gzip(core_db)

        manifest = json.loads(
            emit_manifest(
                tmp_path,
                "2026.03.03",
                core_gz=core_gz,
                core_db=core_db,
                full_gz=gz,
                full_db=db,
            ).read_text()
        )
        full = manifest["tiers"]["full"]

        assert sha256_file(gz) == full["sha256"]
        decompressed = gzip.decompress(gz.read_bytes())
        import hashlib

        assert hashlib.sha256(decompressed).hexdigest() == full["uncompressed_sha256"]


# --- helpers ---------------------------------------------------------------


def _gzip(db: Path) -> Path:
    gz = db.with_suffix(db.suffix + ".gz")
    with open(db, "rb") as fi, gzip.open(gz, "wb") as fo:
        fo.write(fi.read())
    return gz


def _count(db: Path, table: str) -> int:
    conn = sqlite3.connect(str(db))
    try:
        return conn.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
    finally:
        conn.close()


def _generic_names(db: Path) -> set[str]:
    conn = sqlite3.connect(str(db))
    try:
        return {r[0] for r in conn.execute("SELECT generic_name FROM drug_concepts")}
    finally:
        conn.close()


def _meta(db: Path, key: str) -> str | None:
    conn = sqlite3.connect(str(db))
    try:
        row = conn.execute("SELECT value FROM metadata WHERE key = ?", (key,)).fetchone()
        return row[0] if row else None
    finally:
        conn.close()
