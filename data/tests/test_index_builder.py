"""Tests for the SQLite FTS5 index builder."""

from __future__ import annotations

import sqlite3
from pathlib import Path

from pildora_data.index_builder import (
    build_drug_concepts,
    build_index,
    create_schema,
    get_index_stats,
)
from pildora_data.models import DrugProduct, Supplement
from pildora_data.parsers.dailymed import parse_dailymed_supplements
from pildora_data.parsers.openfda import parse_openfda_ndc

FIXTURES_DIR = Path(__file__).parent / "fixtures"


def _sample_drugs() -> list[DrugProduct]:
    return parse_openfda_ndc(FIXTURES_DIR / "search_drugs.json")


def _sample_supplements() -> list[Supplement]:
    return parse_dailymed_supplements(FIXTURES_DIR / "search_supplements.json")


class TestCreateSchema:
    """Tests for schema creation."""

    def test_creates_all_tables(self, tmp_path: Path) -> None:
        db = tmp_path / "test.sqlite"
        conn = sqlite3.connect(str(db))
        create_schema(conn)

        tables = {
            row[0]
            for row in conn.execute(
                "SELECT name FROM sqlite_master WHERE type IN ('table', 'view')"
            ).fetchall()
        }
        conn.close()

        assert "drug_concepts" in tables
        assert "drug_aliases" in tables
        assert "drug_products" in tables
        assert "drug_fts" in tables
        assert "supplements" in tables
        assert "supplement_fts" in tables
        assert "metadata" in tables

    def test_idempotent_schema_creation(self, tmp_path: Path) -> None:
        db = tmp_path / "test.sqlite"
        conn = sqlite3.connect(str(db))
        create_schema(conn)
        create_schema(conn)  # should not raise
        conn.close()


class TestBuildDrugConcepts:
    """Tests for concept grouping logic."""

    def test_groups_by_generic_name(self) -> None:
        drugs = [
            DrugProduct(ndc="001", drug_name="LIPITOR", generic_name="ATORVASTATIN CALCIUM",
                        brand_name="LIPITOR"),
            DrugProduct(ndc="002", drug_name="ATORVASTATIN", generic_name="ATORVASTATIN CALCIUM",
                        brand_name=""),
        ]
        concepts = build_drug_concepts(drugs)
        assert len(concepts) == 1
        key = "atorvastatin calcium"
        assert key in concepts
        assert len(concepts[key]["products"]) == 2

    def test_collects_brand_names(self) -> None:
        drugs = [
            DrugProduct(ndc="001", drug_name="ADVIL", generic_name="IBUPROFEN",
                        brand_name="ADVIL"),
            DrugProduct(ndc="002", drug_name="MOTRIN", generic_name="IBUPROFEN",
                        brand_name="MOTRIN"),
        ]
        concepts = build_drug_concepts(drugs)
        assert concepts["ibuprofen"]["brand_names"] == {"ADVIL", "MOTRIN"}

    def test_skips_empty_key(self) -> None:
        drugs = [
            DrugProduct(ndc="001", drug_name="", generic_name=""),
        ]
        concepts = build_drug_concepts(drugs)
        assert len(concepts) == 0

    def test_uses_drug_name_when_no_generic(self) -> None:
        drugs = [
            DrugProduct(ndc="001", drug_name="MYSTERY DRUG", generic_name=""),
        ]
        concepts = build_drug_concepts(drugs)
        assert "mystery drug" in concepts


class TestBuildIndex:
    """Tests for the full index build pipeline."""

    def test_builds_index_from_sample_data(self, tmp_path: Path) -> None:
        db_path = tmp_path / "test.sqlite"
        drugs = _sample_drugs()
        supplements = _sample_supplements()

        result = build_index(drugs, supplements, db_path)
        assert result == db_path
        assert db_path.exists()
        assert db_path.stat().st_size > 0

    def test_concept_deduplication(self, tmp_path: Path) -> None:
        db_path = tmp_path / "test.sqlite"
        drugs = _sample_drugs()
        build_index(drugs, [], db_path)

        conn = sqlite3.connect(str(db_path))
        # Atorvastatin has 2 products but should be 1 concept
        ator = conn.execute(
            "SELECT id FROM drug_concepts WHERE generic_name = 'ATORVASTATIN CALCIUM'"
        ).fetchall()
        assert len(ator) == 1
        concept_id = ator[0][0]

        products = conn.execute(
            "SELECT COUNT(*) FROM drug_products WHERE concept_id = ?",
            (concept_id,),
        ).fetchone()[0]
        assert products == 2  # Two NDC entries for atorvastatin

        conn.close()

    def test_aliases_populated(self, tmp_path: Path) -> None:
        db_path = tmp_path / "test.sqlite"
        drugs = _sample_drugs()
        build_index(drugs, [], db_path)

        conn = sqlite3.connect(str(db_path))
        # Ibuprofen concept should have ADVIL and MOTRIN as brand aliases
        ibu = conn.execute(
            "SELECT id FROM drug_concepts WHERE generic_name = 'IBUPROFEN'"
        ).fetchone()
        assert ibu is not None

        aliases = conn.execute(
            "SELECT alias, alias_type FROM drug_aliases WHERE concept_id = ? ORDER BY alias",
            (ibu[0],),
        ).fetchall()
        alias_names = [a[0] for a in aliases]
        assert "ADVIL" in alias_names
        assert "MOTRIN" in alias_names

        conn.close()

    def test_supplements_inserted(self, tmp_path: Path) -> None:
        db_path = tmp_path / "test.sqlite"
        supplements = _sample_supplements()
        build_index([], supplements, db_path)

        conn = sqlite3.connect(str(db_path))
        count = conn.execute("SELECT COUNT(*) FROM supplements").fetchone()[0]
        assert count == len(supplements)
        conn.close()

    def test_metadata_populated(self, tmp_path: Path) -> None:
        db_path = tmp_path / "test.sqlite"
        build_index(_sample_drugs(), _sample_supplements(), db_path)

        conn = sqlite3.connect(str(db_path))
        meta = dict(conn.execute("SELECT key, value FROM metadata").fetchall())
        assert meta["schema_version"] == "1.0"
        assert "build_date" in meta
        assert int(meta["drug_concept_count"]) > 0
        conn.close()

    def test_rxnorm_cache_applied(self, tmp_path: Path) -> None:
        db_path = tmp_path / "test.sqlite"
        drugs = [
            DrugProduct(ndc="001", drug_name="LIPITOR", generic_name="ATORVASTATIN CALCIUM",
                        brand_name="LIPITOR"),
        ]
        cache = {"atorvastatin calcium": "83367"}
        build_index(drugs, [], db_path, rxnorm_cache=cache)

        conn = sqlite3.connect(str(db_path))
        rxcui = conn.execute(
            "SELECT rxcui FROM drug_concepts WHERE generic_name = 'ATORVASTATIN CALCIUM'"
        ).fetchone()[0]
        assert rxcui == "83367"
        conn.close()

    def test_replaces_existing_db(self, tmp_path: Path) -> None:
        db_path = tmp_path / "test.sqlite"
        build_index([], [], db_path)

        conn1 = sqlite3.connect(str(db_path))
        count1 = conn1.execute("SELECT COUNT(*) FROM drug_concepts").fetchone()[0]
        conn1.close()

        build_index(_sample_drugs(), _sample_supplements(), db_path)

        conn2 = sqlite3.connect(str(db_path))
        count2 = conn2.execute("SELECT COUNT(*) FROM drug_concepts").fetchone()[0]
        conn2.close()

        assert count1 == 0
        assert count2 > 0

    def test_fts_index_populated(self, tmp_path: Path) -> None:
        db_path = tmp_path / "test.sqlite"
        build_index(_sample_drugs(), [], db_path)

        conn = sqlite3.connect(str(db_path))
        fts_rows = conn.execute("SELECT COUNT(*) FROM drug_fts").fetchone()[0]
        concept_rows = conn.execute("SELECT COUNT(*) FROM drug_concepts").fetchone()[0]
        assert fts_rows == concept_rows
        assert fts_rows > 0
        conn.close()


class TestGetIndexStats:
    """Tests for index statistics."""

    def test_returns_stats(self, tmp_path: Path) -> None:
        db_path = tmp_path / "test.sqlite"
        build_index(_sample_drugs(), _sample_supplements(), db_path)

        stats = get_index_stats(db_path)
        assert stats["concepts"] > 0
        assert stats["supplements"] > 0
        assert stats["file_size_bytes"] > 0
        assert "meta_schema_version" in stats
