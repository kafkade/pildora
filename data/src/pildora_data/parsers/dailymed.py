"""Parser for DailyMed supplement SPL data."""

from __future__ import annotations

import logging
from pathlib import Path

import orjson

from pildora_data.models import Supplement

logger = logging.getLogger(__name__)


def parse_dailymed_supplements(data_path: Path) -> list[Supplement]:
    """Parse DailyMed supplement JSON data into Supplement objects.

    Expects a JSON file with a top-level ``data`` array of supplement records.

    Args:
        data_path: Path to the DailyMed supplements JSON file.

    Returns:
        List of parsed Supplement objects.
    """
    if not data_path.is_file():
        logger.warning("DailyMed data file not found: %s", data_path)
        return []

    try:
        raw = data_path.read_bytes()
        data = orjson.loads(raw)
    except (OSError, orjson.JSONDecodeError) as e:
        logger.warning("Failed to parse %s: %s", data_path, e)
        return []

    records = data.get("data", []) if isinstance(data, dict) else []
    supplements: list[Supplement] = []
    seen_ids: set[str] = set()

    for record in records:
        supplement = _parse_supplement_record(record)
        if supplement and supplement.id not in seen_ids:
            seen_ids.add(supplement.id)
            supplements.append(supplement)

    logger.info("Parsed %d unique supplements.", len(supplements))
    return supplements


def _parse_supplement_record(record: dict) -> Supplement | None:
    """Parse a single DailyMed supplement record into a Supplement.

    Returns None if the record lacks a valid identifier.
    """
    spl_set_id = (record.get("setid") or record.get("spl_set_id") or "").strip()
    if not spl_set_id:
        return None

    name = (record.get("spl_name") or record.get("title") or "").strip()
    if not name:
        return None

    ingredients = _extract_ingredients(record.get("active_ingredients"))
    manufacturer = (record.get("labeler") or "").strip()

    dosage_form = ""
    products = record.get("products")
    if isinstance(products, list) and products:
        first_product = products[0]
        if isinstance(first_product, dict):
            dosage_form = (first_product.get("dosage_form") or "").strip()

    return Supplement(
        id=spl_set_id,
        name=name,
        ingredients=ingredients,
        manufacturer=manufacturer,
        dosage_form=dosage_form,
    )


def _extract_ingredients(ingredients: list | None) -> list[str]:
    """Extract ingredient names from various formats."""
    if not ingredients or not isinstance(ingredients, list):
        return []

    result: list[str] = []
    for item in ingredients:
        if isinstance(item, str):
            name = item.strip()
        elif isinstance(item, dict):
            name = (item.get("name") or "").strip()
        else:
            continue
        if name:
            result.append(name)

    return result
