"""Tests for the search module — FTS5 query tests with latency checks."""

from __future__ import annotations

import time
from pathlib import Path

import pytest

from pildora_data.index_builder import build_index
from pildora_data.parsers.dailymed import parse_dailymed_supplements
from pildora_data.parsers.openfda import parse_openfda_ndc
from pildora_data.search import search_all, search_drugs, search_supplements

FIXTURES_DIR = Path(__file__).parent / "fixtures"


@pytest.fixture(scope="module")
def search_db(tmp_path_factory: pytest.TempPathFactory) -> Path:
    """Build a search index from fixtures for all search tests."""
    db_path = tmp_path_factory.mktemp("search") / "test_search.sqlite"
    drugs = parse_openfda_ndc(FIXTURES_DIR / "search_drugs.json")
    supplements = parse_dailymed_supplements(FIXTURES_DIR / "search_supplements.json")
    build_index(drugs, supplements, db_path)
    return db_path


class TestDrugSearch:
    """FTS5 drug search tests."""

    def test_prefix_search_atorva(self, search_db: Path) -> None:
        results = search_drugs(search_db, "atorva*")
        assert len(results) > 0
        names = [r["preferred_name"].lower() for r in results]
        assert any("atorvastatin" in n for n in names)

    def test_brand_name_lipitor(self, search_db: Path) -> None:
        results = search_drugs(search_db, "LIPITOR")
        assert len(results) > 0
        # Lipitor should match via the aliases column
        names = [r["generic_name"].upper() for r in results]
        assert any("ATORVASTATIN" in n for n in names)

    def test_exact_match_acetaminophen(self, search_db: Path) -> None:
        results = search_drugs(search_db, "acetaminophen")
        assert len(results) > 0
        names = [r["preferred_name"].lower() for r in results]
        assert any("acetaminophen" in n for n in names)

    def test_ibuprofen(self, search_db: Path) -> None:
        results = search_drugs(search_db, "ibuprofen")
        assert len(results) > 0
        assert any("IBUPROFEN" in r["generic_name"].upper() for r in results)

    def test_aspirin(self, search_db: Path) -> None:
        results = search_drugs(search_db, "aspirin")
        assert len(results) > 0

    def test_amoxicillin(self, search_db: Path) -> None:
        results = search_drugs(search_db, "amoxicillin")
        assert len(results) > 0

    def test_metformin(self, search_db: Path) -> None:
        results = search_drugs(search_db, "metformin*")
        assert len(results) > 0
        assert any("METFORMIN" in r["generic_name"].upper() for r in results)

    def test_atorvastatin_calcium_multi_word(self, search_db: Path) -> None:
        results = search_drugs(search_db, "atorvastatin calcium")
        assert len(results) > 0

    def test_results_have_expected_fields(self, search_db: Path) -> None:
        results = search_drugs(search_db, "aspirin")
        assert len(results) > 0
        r = results[0]
        assert "id" in r
        assert "preferred_name" in r
        assert "generic_name" in r
        assert "rxcui" in r
        assert "product_type" in r
        assert "rank" in r

    def test_limit_parameter(self, search_db: Path) -> None:
        results = search_drugs(search_db, "a*", limit=3)
        assert len(results) <= 3

    def test_no_results_for_nonsense(self, search_db: Path) -> None:
        results = search_drugs(search_db, "xyzzyplugh")
        assert len(results) == 0

    def test_search_latency_under_50ms(self, search_db: Path) -> None:
        queries = ["atorva*", "ibuprofen", "aspirin", "metformin*", "acetaminophen"]
        for q in queries:
            start = time.perf_counter()
            search_drugs(search_db, q)
            elapsed_ms = (time.perf_counter() - start) * 1000
            assert elapsed_ms < 50, f"Query {q!r} took {elapsed_ms:.1f}ms (>50ms)"


class TestSupplementSearch:
    """FTS5 supplement search tests."""

    def test_vitamin_d(self, search_db: Path) -> None:
        results = search_supplements(search_db, "vitamin d*")
        assert len(results) > 0
        assert any("vitamin" in r["name"].lower() for r in results)

    def test_melatonin(self, search_db: Path) -> None:
        results = search_supplements(search_db, "melatonin")
        assert len(results) > 0

    def test_fish_oil(self, search_db: Path) -> None:
        results = search_supplements(search_db, "fish oil")
        assert len(results) > 0

    def test_ingredient_search(self, search_db: Path) -> None:
        results = search_supplements(search_db, "cholecalciferol")
        assert len(results) > 0

    def test_results_have_expected_fields(self, search_db: Path) -> None:
        results = search_supplements(search_db, "zinc")
        assert len(results) > 0
        r = results[0]
        assert "id" in r
        assert "name" in r
        assert "manufacturer" in r

    def test_supplement_search_latency(self, search_db: Path) -> None:
        start = time.perf_counter()
        search_supplements(search_db, "vitamin*")
        elapsed_ms = (time.perf_counter() - start) * 1000
        assert elapsed_ms < 50, f"Supplement search took {elapsed_ms:.1f}ms"


class TestSearchAll:
    """Tests for combined drug + supplement search."""

    def test_returns_both_types(self, search_db: Path) -> None:
        # "vitamin" matches supplement names; should find supplements
        results = search_all(search_db, "vitamin*")
        types = {r["type"] for r in results}
        assert "supplement" in types

    def test_drug_result_has_type(self, search_db: Path) -> None:
        results = search_all(search_db, "aspirin")
        drug_results = [r for r in results if r["type"] == "drug"]
        assert len(drug_results) > 0

    def test_combined_limit(self, search_db: Path) -> None:
        results = search_all(search_db, "a*", limit=5)
        assert len(results) <= 5

    def test_combined_search_latency(self, search_db: Path) -> None:
        start = time.perf_counter()
        search_all(search_db, "ibuprofen")
        elapsed_ms = (time.perf_counter() - start) * 1000
        assert elapsed_ms < 50, f"Combined search took {elapsed_ms:.1f}ms"
