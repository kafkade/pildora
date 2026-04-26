"""Tests for DailyMed supplement parser."""

from __future__ import annotations

from pathlib import Path

from pildora_data.models import Supplement
from pildora_data.parsers.dailymed import parse_dailymed_supplements

FIXTURES_DIR = Path(__file__).parent / "fixtures"


class TestParseDailymed:
    """Tests for parse_dailymed_supplements."""

    def test_parses_valid_records(self) -> None:
        supplements = parse_dailymed_supplements(FIXTURES_DIR / "dailymed_sample.json")
        # 8 records: 1 empty setid, 1 empty name, 1 duplicate → 5 unique valid
        assert len(supplements) == 5

    def test_all_are_supplement_instances(self) -> None:
        supplements = parse_dailymed_supplements(FIXTURES_DIR / "dailymed_sample.json")
        for s in supplements:
            assert isinstance(s, Supplement)

    def test_vitamin_d3_parsed_correctly(self) -> None:
        supplements = parse_dailymed_supplements(FIXTURES_DIR / "dailymed_sample.json")
        vit_d = next(s for s in supplements if s.id == "aaa-bbb-001")
        assert vit_d.name == "Vitamin D3"
        assert vit_d.manufacturer == "Nature Made"
        assert vit_d.dosage_form == "CAPSULE"
        assert vit_d.ingredients == ["CHOLECALCIFEROL"]
        assert vit_d.source == "dailymed"

    def test_dict_ingredients(self) -> None:
        supplements = parse_dailymed_supplements(FIXTURES_DIR / "dailymed_sample.json")
        fish_oil = next(s for s in supplements if s.id == "aaa-bbb-003")
        assert fish_oil.ingredients == ["EPA", "DHA"]

    def test_empty_ingredients(self) -> None:
        supplements = parse_dailymed_supplements(FIXTURES_DIR / "dailymed_sample.json")
        probiotic = next(s for s in supplements if s.id == "aaa-bbb-005")
        assert probiotic.ingredients == []
        assert probiotic.dosage_form == ""

    def test_missing_id_skipped(self) -> None:
        supplements = parse_dailymed_supplements(FIXTURES_DIR / "dailymed_sample.json")
        ids = [s.id for s in supplements]
        assert "" not in ids

    def test_missing_name_skipped(self) -> None:
        supplements = parse_dailymed_supplements(FIXTURES_DIR / "dailymed_sample.json")
        ids = [s.id for s in supplements]
        assert "aaa-bbb-006" not in ids

    def test_duplicate_id_deduplicated(self) -> None:
        supplements = parse_dailymed_supplements(FIXTURES_DIR / "dailymed_sample.json")
        id_counts = {}
        for s in supplements:
            id_counts[s.id] = id_counts.get(s.id, 0) + 1
        for sid, count in id_counts.items():
            assert count == 1, f"ID {sid} appears {count} times"

    def test_nonexistent_file_returns_empty(self) -> None:
        supplements = parse_dailymed_supplements(Path("/nonexistent/file.json"))
        assert supplements == []
