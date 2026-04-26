"""Output writers and quality reporting for the ETL pipeline."""

from __future__ import annotations

import logging
from pathlib import Path

import orjson

from pildora_data.models import DrugProduct, Supplement

logger = logging.getLogger(__name__)


def write_jsonl(
    products: list[DrugProduct | Supplement],
    output_path: Path,
) -> None:
    """Write products as JSONL (one JSON object per line).

    Args:
        products: List of DrugProduct or Supplement objects.
        output_path: Path to the output JSONL file.
    """
    output_path.parent.mkdir(parents=True, exist_ok=True)

    with open(output_path, "wb") as f:
        for product in products:
            line = orjson.dumps(_to_dict(product), option=orjson.OPT_SORT_KEYS)
            f.write(line)
            f.write(b"\n")

    logger.info("Wrote %d records to %s", len(products), output_path)


def _to_dict(obj: DrugProduct | Supplement) -> dict:
    """Convert a dataclass to a dict, handling both types."""
    if isinstance(obj, DrugProduct):
        return {
            "ndc": obj.ndc,
            "drug_name": obj.drug_name,
            "generic_name": obj.generic_name,
            "brand_name": obj.brand_name,
            "dosage_form": obj.dosage_form,
            "strength": obj.strength,
            "route": obj.route,
            "manufacturer": obj.manufacturer,
            "product_type": obj.product_type,
            "source": obj.source,
        }
    if isinstance(obj, Supplement):
        return {
            "id": obj.id,
            "name": obj.name,
            "ingredients": obj.ingredients,
            "manufacturer": obj.manufacturer,
            "dosage_form": obj.dosage_form,
            "source": obj.source,
        }
    msg = f"Unsupported type: {type(obj)}"
    raise TypeError(msg)


def generate_quality_report(
    drugs: list[DrugProduct],
    supplements: list[Supplement],
) -> str:
    """Generate a text quality report for the ETL output.

    Args:
        drugs: List of parsed DrugProduct objects.
        supplements: List of parsed Supplement objects.

    Returns:
        A formatted text report string.
    """
    lines: list[str] = []
    lines.append("=" * 60)
    lines.append("Pildora ETL — Quality Report")
    lines.append("=" * 60)

    # Drug product stats
    lines.append("")
    lines.append("Drug Products (openFDA NDC)")
    lines.append("-" * 40)
    lines.append(f"  Total products:       {len(drugs)}")
    unique_ndcs = len({d.ndc for d in drugs})
    lines.append(f"  Unique NDCs:          {unique_ndcs}")
    unique_generics = len({d.generic_name for d in drugs if d.generic_name})
    lines.append(f"  Unique generic names: {unique_generics}")

    with_brand = sum(1 for d in drugs if d.brand_name)
    with_strength = sum(1 for d in drugs if d.strength)
    with_route = sum(1 for d in drugs if d.route)
    with_manufacturer = sum(1 for d in drugs if d.manufacturer)

    lines.append(f"  With brand name:      {with_brand} ({_pct(with_brand, len(drugs))})")
    lines.append(f"  With strength:        {with_strength} ({_pct(with_strength, len(drugs))})")
    lines.append(f"  With route:           {with_route} ({_pct(with_route, len(drugs))})")
    mfr_pct = _pct(with_manufacturer, len(drugs))
    lines.append(f"  With manufacturer:    {with_manufacturer} ({mfr_pct})")

    # Supplement stats
    lines.append("")
    lines.append("Supplements (DailyMed)")
    lines.append("-" * 40)
    lines.append(f"  Total supplements:    {len(supplements)}")
    unique_names = len({s.name for s in supplements})
    lines.append(f"  Unique names:         {unique_names}")

    with_ingredients = sum(1 for s in supplements if s.ingredients)
    with_mfr = sum(1 for s in supplements if s.manufacturer)
    with_form = sum(1 for s in supplements if s.dosage_form)

    ing_pct = _pct(with_ingredients, len(supplements))
    lines.append(f"  With ingredients:     {with_ingredients} ({ing_pct})")
    lines.append(f"  With manufacturer:    {with_mfr} ({_pct(with_mfr, len(supplements))})")
    lines.append(f"  With dosage form:     {with_form} ({_pct(with_form, len(supplements))})")

    # Known gaps
    lines.append("")
    lines.append("Known Gaps")
    lines.append("-" * 40)
    missing_brand = sum(1 for d in drugs if not d.brand_name)
    missing_strength = sum(1 for d in drugs if not d.strength)
    missing_ingredients = sum(1 for s in supplements if not s.ingredients)

    if missing_brand:
        lines.append(f"  Drugs missing brand name:       {missing_brand}")
    if missing_strength:
        lines.append(f"  Drugs missing strength:         {missing_strength}")
    if missing_ingredients:
        lines.append(f"  Supplements missing ingredients: {missing_ingredients}")
    if not (missing_brand or missing_strength or missing_ingredients):
        lines.append("  No gaps detected.")

    lines.append("")
    lines.append("=" * 60)
    return "\n".join(lines)


def _pct(part: int, total: int) -> str:
    """Format a percentage string."""
    if total == 0:
        return "0.0%"
    return f"{part / total * 100:.1f}%"
