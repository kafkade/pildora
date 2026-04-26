"""Tests for openFDA NDC parser."""

from __future__ import annotations

from pathlib import Path

from pildora_data.models import DrugProduct
from pildora_data.parsers.openfda import parse_openfda_ndc

FIXTURES_DIR = Path(__file__).parent / "fixtures"


class TestParseOpenfda:
    """Tests for parse_openfda_ndc."""

    def test_parses_valid_records(self) -> None:
        products = parse_openfda_ndc(FIXTURES_DIR / "openfda_sample.json")
        # 8 records in fixture, but 1 has empty NDC, 1 is a duplicate → 6 unique
        assert len(products) == 6

    def test_all_products_are_drug_products(self) -> None:
        products = parse_openfda_ndc(FIXTURES_DIR / "openfda_sample.json")
        for p in products:
            assert isinstance(p, DrugProduct)

    def test_lipitor_parsed_correctly(self) -> None:
        products = parse_openfda_ndc(FIXTURES_DIR / "openfda_sample.json")
        lipitor = next(p for p in products if p.ndc == "0002-0800")
        assert lipitor.drug_name == "LIPITOR"
        assert lipitor.generic_name == "ATORVASTATIN CALCIUM"
        assert lipitor.brand_name == "LIPITOR"
        assert lipitor.dosage_form == "TABLET, FILM COATED"
        assert lipitor.strength == "10 mg/1"
        assert lipitor.route == "ORAL"
        assert lipitor.manufacturer == "Pfizer Laboratories"
        assert lipitor.product_type == "HUMAN PRESCRIPTION DRUG"
        assert lipitor.source == "openfda"

    def test_multi_ingredient_strength(self) -> None:
        products = parse_openfda_ndc(FIXTURES_DIR / "openfda_sample.json")
        exforge = next(p for p in products if p.ndc == "0078-0401")
        assert exforge.strength == "5 mg/1; 160 mg/1"

    def test_missing_brand_falls_back_to_generic(self) -> None:
        products = parse_openfda_ndc(FIXTURES_DIR / "openfda_sample.json")
        metformin = next(p for p in products if p.ndc == "0591-0405")
        assert metformin.drug_name == "METFORMIN HYDROCHLORIDE"
        assert metformin.brand_name == ""

    def test_empty_ndc_skipped(self) -> None:
        products = parse_openfda_ndc(FIXTURES_DIR / "openfda_sample.json")
        ndcs = [p.ndc for p in products]
        assert "" not in ndcs

    def test_duplicate_ndc_deduplicated(self) -> None:
        products = parse_openfda_ndc(FIXTURES_DIR / "openfda_sample.json")
        ndc_counts = {}
        for p in products:
            ndc_counts[p.ndc] = ndc_counts.get(p.ndc, 0) + 1
        for ndc, count in ndc_counts.items():
            assert count == 1, f"NDC {ndc} appears {count} times"

    def test_minimal_record(self) -> None:
        products = parse_openfda_ndc(FIXTURES_DIR / "openfda_sample.json")
        minimal = next(p for p in products if p.ndc == "9999-0001")
        assert minimal.drug_name == "9999-0001"  # falls back to NDC
        assert minimal.generic_name == ""
        assert minimal.brand_name == ""
        assert minimal.strength == ""
        assert minimal.route == ""

    def test_nonexistent_path_returns_empty(self) -> None:
        products = parse_openfda_ndc(Path("/nonexistent/path"))
        assert products == []

    def test_directory_parsing(self, tmp_path: Path) -> None:
        """Parser handles a directory containing multiple JSON files."""
        import shutil

        sample = FIXTURES_DIR / "openfda_sample.json"
        shutil.copy(sample, tmp_path / "part1.json")
        products = parse_openfda_ndc(tmp_path)
        assert len(products) == 6
