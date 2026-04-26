"""Parser for openFDA NDC Directory data."""

from __future__ import annotations

import logging
from pathlib import Path

import orjson

from pildora_data.models import DrugProduct

logger = logging.getLogger(__name__)


def parse_openfda_ndc(data_path: Path) -> list[DrugProduct]:
    """Parse openFDA NDC JSON data into DrugProduct objects.

    Handles both a single JSON file and a directory of JSON files.
    Each file is expected to contain a top-level ``results`` array.

    Args:
        data_path: Path to a JSON file or directory of JSON files.

    Returns:
        List of parsed DrugProduct objects.
    """
    json_files: list[Path] = []
    if data_path.is_dir():
        json_files = sorted(data_path.rglob("*.json"))
    elif data_path.is_file():
        json_files = [data_path]
    else:
        logger.warning("Data path does not exist: %s", data_path)
        return []

    products: list[DrugProduct] = []
    seen_ndcs: set[str] = set()

    for json_file in json_files:
        logger.info("Parsing %s ...", json_file.name)
        try:
            raw = json_file.read_bytes()
            data = orjson.loads(raw)
        except (OSError, orjson.JSONDecodeError) as e:
            logger.warning("Failed to parse %s: %s", json_file, e)
            continue

        results = data.get("results", []) if isinstance(data, dict) else []
        for record in results:
            product = _parse_ndc_record(record)
            if product and product.ndc not in seen_ndcs:
                seen_ndcs.add(product.ndc)
                products.append(product)

    logger.info("Parsed %d unique drug products from %d file(s).", len(products), len(json_files))
    return products


def _parse_ndc_record(record: dict) -> DrugProduct | None:
    """Parse a single openFDA NDC record into a DrugProduct.

    Returns None if the record lacks a valid NDC code.
    """
    ndc = (record.get("product_ndc") or "").strip()
    if not ndc:
        return None

    generic_name = (record.get("generic_name") or "").strip()
    brand_name = (record.get("brand_name") or "").strip()
    drug_name = brand_name or generic_name or ndc

    strength = _extract_strength(record.get("active_ingredients"))

    routes = record.get("route") or []
    route = routes[0] if isinstance(routes, list) and routes else ""

    return DrugProduct(
        ndc=ndc,
        drug_name=drug_name,
        generic_name=generic_name,
        brand_name=brand_name,
        dosage_form=(record.get("dosage_form") or "").strip(),
        strength=strength,
        route=route.strip() if isinstance(route, str) else "",
        manufacturer=(record.get("labeler_name") or "").strip(),
        product_type=(record.get("product_type") or "").strip(),
    )


def _extract_strength(ingredients: list[dict] | None) -> str:
    """Extract and join strengths from active_ingredients list."""
    if not ingredients or not isinstance(ingredients, list):
        return ""

    strengths: list[str] = []
    for ing in ingredients:
        if not isinstance(ing, dict):
            continue
        s = (ing.get("strength") or "").strip()
        if s:
            strengths.append(s)

    return "; ".join(strengths)
