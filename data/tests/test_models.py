"""Tests for data models."""

from __future__ import annotations

from pildora_data.models import DrugProduct, Supplement


class TestDrugProduct:
    """Tests for DrugProduct dataclass."""

    def test_required_fields(self) -> None:
        drug = DrugProduct(ndc="0002-0800", drug_name="LIPITOR")
        assert drug.ndc == "0002-0800"
        assert drug.drug_name == "LIPITOR"

    def test_defaults(self) -> None:
        drug = DrugProduct(ndc="0001-0001", drug_name="Test Drug")
        assert drug.generic_name == ""
        assert drug.brand_name == ""
        assert drug.dosage_form == ""
        assert drug.strength == ""
        assert drug.route == ""
        assert drug.manufacturer == ""
        assert drug.product_type == ""
        assert drug.source == "openfda"

    def test_all_fields(self) -> None:
        drug = DrugProduct(
            ndc="0002-0800",
            drug_name="LIPITOR",
            generic_name="ATORVASTATIN CALCIUM",
            brand_name="LIPITOR",
            dosage_form="TABLET",
            strength="10 mg/1",
            route="ORAL",
            manufacturer="Pfizer",
            product_type="HUMAN PRESCRIPTION DRUG",
            source="openfda",
        )
        assert drug.ndc == "0002-0800"
        assert drug.manufacturer == "Pfizer"

    def test_equality(self) -> None:
        d1 = DrugProduct(ndc="0001", drug_name="A")
        d2 = DrugProduct(ndc="0001", drug_name="A")
        assert d1 == d2

    def test_inequality(self) -> None:
        d1 = DrugProduct(ndc="0001", drug_name="A")
        d2 = DrugProduct(ndc="0002", drug_name="B")
        assert d1 != d2


class TestSupplement:
    """Tests for Supplement dataclass."""

    def test_required_fields(self) -> None:
        supp = Supplement(id="abc-123", name="Vitamin D3")
        assert supp.id == "abc-123"
        assert supp.name == "Vitamin D3"

    def test_defaults(self) -> None:
        supp = Supplement(id="abc-123", name="Vitamin D3")
        assert supp.ingredients == []
        assert supp.manufacturer == ""
        assert supp.dosage_form == ""
        assert supp.source == "dailymed"

    def test_ingredients_default_factory(self) -> None:
        s1 = Supplement(id="a", name="A")
        s2 = Supplement(id="b", name="B")
        s1.ingredients.append("X")
        assert s2.ingredients == []  # not shared

    def test_all_fields(self) -> None:
        supp = Supplement(
            id="abc-123",
            name="Vitamin D3",
            ingredients=["CHOLECALCIFEROL"],
            manufacturer="Nature Made",
            dosage_form="CAPSULE",
            source="dailymed",
        )
        assert supp.ingredients == ["CHOLECALCIFEROL"]
        assert supp.manufacturer == "Nature Made"
