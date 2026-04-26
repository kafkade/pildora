"""Tests for output writer and quality report."""

from __future__ import annotations

from pathlib import Path

import orjson

from pildora_data.models import DrugProduct, Supplement
from pildora_data.output import generate_quality_report, write_jsonl


def _sample_drugs() -> list[DrugProduct]:
    return [
        DrugProduct(
            ndc="0002-0800",
            drug_name="LIPITOR",
            generic_name="ATORVASTATIN CALCIUM",
            brand_name="LIPITOR",
            dosage_form="TABLET",
            strength="10 mg/1",
            route="ORAL",
            manufacturer="Pfizer",
            product_type="HUMAN PRESCRIPTION DRUG",
        ),
        DrugProduct(
            ndc="0591-0405",
            drug_name="METFORMIN HYDROCHLORIDE",
            generic_name="METFORMIN HYDROCHLORIDE",
            brand_name="",
            dosage_form="TABLET",
            strength="500 mg/1",
            route="ORAL",
            manufacturer="Watson",
        ),
        DrugProduct(
            ndc="9999-0001",
            drug_name="9999-0001",
            generic_name="",
            brand_name="",
        ),
    ]


def _sample_supplements() -> list[Supplement]:
    return [
        Supplement(
            id="aaa-001",
            name="Vitamin D3",
            ingredients=["CHOLECALCIFEROL"],
            manufacturer="Nature Made",
            dosage_form="CAPSULE",
        ),
        Supplement(
            id="aaa-002",
            name="Fish Oil",
            ingredients=["EPA", "DHA"],
            manufacturer="Nordic Naturals",
        ),
        Supplement(
            id="aaa-003",
            name="Probiotic",
        ),
    ]


class TestWriteJsonl:
    """Tests for write_jsonl."""

    def test_writes_drug_products(self, tmp_path: Path) -> None:
        drugs = _sample_drugs()
        output = tmp_path / "drugs.jsonl"
        write_jsonl(drugs, output)

        lines = output.read_bytes().strip().split(b"\n")
        assert len(lines) == 3

        first = orjson.loads(lines[0])
        assert first["ndc"] == "0002-0800"
        assert first["source"] == "openfda"

    def test_writes_supplements(self, tmp_path: Path) -> None:
        supps = _sample_supplements()
        output = tmp_path / "supplements.jsonl"
        write_jsonl(supps, output)

        lines = output.read_bytes().strip().split(b"\n")
        assert len(lines) == 3

        first = orjson.loads(lines[0])
        assert first["name"] == "Vitamin D3"
        assert first["source"] == "dailymed"

    def test_creates_parent_directories(self, tmp_path: Path) -> None:
        output = tmp_path / "nested" / "dir" / "out.jsonl"
        write_jsonl([_sample_drugs()[0]], output)
        assert output.exists()

    def test_empty_list_creates_empty_file(self, tmp_path: Path) -> None:
        output = tmp_path / "empty.jsonl"
        write_jsonl([], output)
        assert output.exists()
        assert output.read_text() == ""

    def test_jsonl_format_one_json_per_line(self, tmp_path: Path) -> None:
        drugs = _sample_drugs()
        output = tmp_path / "drugs.jsonl"
        write_jsonl(drugs, output)

        for line in output.read_bytes().strip().split(b"\n"):
            parsed = orjson.loads(line)
            assert isinstance(parsed, dict)


class TestQualityReport:
    """Tests for generate_quality_report."""

    def test_report_contains_drug_count(self) -> None:
        report = generate_quality_report(_sample_drugs(), _sample_supplements())
        assert "Total products:       3" in report

    def test_report_contains_supplement_count(self) -> None:
        report = generate_quality_report(_sample_drugs(), _sample_supplements())
        assert "Total supplements:    3" in report

    def test_report_contains_coverage_stats(self) -> None:
        report = generate_quality_report(_sample_drugs(), _sample_supplements())
        assert "With brand name:" in report
        assert "With strength:" in report
        assert "With ingredients:" in report

    def test_report_contains_known_gaps(self) -> None:
        report = generate_quality_report(_sample_drugs(), _sample_supplements())
        assert "Known Gaps" in report
        assert "Drugs missing brand name:" in report

    def test_empty_inputs(self) -> None:
        report = generate_quality_report([], [])
        assert "Total products:       0" in report
        assert "Total supplements:    0" in report
        assert "No gaps detected." in report

    def test_report_is_string(self) -> None:
        report = generate_quality_report(_sample_drugs(), _sample_supplements())
        assert isinstance(report, str)
