"""Data models for the Pildora drug data pipeline."""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class DrugProduct:
    """A normalized drug product from openFDA NDC data."""

    ndc: str
    drug_name: str
    generic_name: str = ""
    brand_name: str = ""
    dosage_form: str = ""
    strength: str = ""
    route: str = ""
    manufacturer: str = ""
    product_type: str = ""
    source: str = "openfda"


@dataclass
class Supplement:
    """A normalized supplement/vitamin product from DailyMed."""

    id: str
    name: str
    ingredients: list[str] = field(default_factory=list)
    manufacturer: str = ""
    dosage_form: str = ""
    source: str = "dailymed"
