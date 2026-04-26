"""RxNorm REST API client for concept normalization."""

from __future__ import annotations

import json
import logging
import time
from pathlib import Path

import httpx

logger = logging.getLogger(__name__)

RXNORM_BASE = "https://rxnav.nlm.nih.gov/REST"
REQUEST_DELAY = 0.15  # seconds between requests to respect rate limits


def lookup_rxcui(
    drug_name: str,
    client: httpx.Client | None = None,
) -> str | None:
    """Look up RxCUI for a drug name. Returns None if not found.

    Args:
        drug_name: Drug name to look up (generic or brand).
        client: Optional pre-configured httpx.Client.

    Returns:
        RxCUI string, or None if the drug was not found.
    """
    params = {"name": drug_name, "search": 1}
    url = f"{RXNORM_BASE}/rxcui.json"

    try:
        if client:
            resp = client.get(url, params=params)
        else:
            resp = httpx.get(url, params=params, timeout=30.0)
        resp.raise_for_status()
        data = resp.json()
    except (httpx.HTTPError, json.JSONDecodeError) as e:
        logger.debug("RxNorm lookup failed for %r: %s", drug_name, e)
        return None

    id_group = data.get("idGroup", {})
    rxnorm_ids = id_group.get("rxnormId")
    if rxnorm_ids and isinstance(rxnorm_ids, list):
        return rxnorm_ids[0]
    return None


def get_related_names(
    rxcui: str,
    client: httpx.Client | None = None,
) -> dict[str, list[str]]:
    """Get brand/generic name relationships for an RxCUI.

    Args:
        rxcui: RxCUI identifier.
        client: Optional pre-configured httpx.Client.

    Returns:
        Dict with 'brand_names' and 'generic_names' lists.
    """
    url = f"{RXNORM_BASE}/rxcui/{rxcui}/related.json"
    params = {"tty": "BN+IN"}  # Brand Name + Ingredient

    try:
        if client:
            resp = client.get(url, params=params)
        else:
            resp = httpx.get(url, params=params, timeout=30.0)
        resp.raise_for_status()
        data = resp.json()
    except (httpx.HTTPError, json.JSONDecodeError) as e:
        logger.debug("RxNorm related lookup failed for rxcui=%s: %s", rxcui, e)
        return {"brand_names": [], "generic_names": []}

    result: dict[str, list[str]] = {"brand_names": [], "generic_names": []}
    concept_groups = (
        data.get("relatedGroup", {}).get("conceptGroup", [])
    )

    for group in concept_groups:
        tty = group.get("tty", "")
        for prop in group.get("conceptProperties", []):
            name = prop.get("name", "")
            if not name:
                continue
            if tty == "BN":
                result["brand_names"].append(name)
            elif tty == "IN":
                result["generic_names"].append(name)

    return result


def fetch_rxnorm_cache(
    drug_names: list[str],
    cache_path: Path,
    max_lookups: int = 200,
) -> dict[str, str]:
    """Look up RxCUIs for a list of drug names, using a file cache.

    Loads any existing cache, performs API lookups only for uncached names
    (up to max_lookups new calls), saves updated cache, and returns the full map.

    Args:
        drug_names: List of drug names to look up.
        cache_path: Path to the JSON cache file.
        max_lookups: Maximum number of new API lookups to perform.

    Returns:
        Dict mapping drug name (lowercase) → RxCUI string.
    """
    cache: dict[str, str] = {}
    if cache_path.exists():
        try:
            cache = json.loads(cache_path.read_text(encoding="utf-8"))
            logger.info("Loaded %d cached RxNorm lookups from %s", len(cache), cache_path)
        except (json.JSONDecodeError, OSError) as e:
            logger.warning("Failed to load RxNorm cache: %s", e)

    uncached = [n for n in drug_names if n.lower() not in cache]
    to_lookup = uncached[:max_lookups]

    if not to_lookup:
        logger.info("All %d drug names already cached.", len(drug_names))
        return cache

    logger.info("Looking up %d drug names via RxNorm API...", len(to_lookup))
    with httpx.Client(timeout=30.0) as client:
        for i, name in enumerate(to_lookup):
            rxcui = lookup_rxcui(name, client=client)
            if rxcui:
                cache[name.lower()] = rxcui
                logger.debug("[%d/%d] %s → rxcui=%s", i + 1, len(to_lookup), name, rxcui)
            else:
                logger.debug("[%d/%d] %s → not found", i + 1, len(to_lookup), name)
            time.sleep(REQUEST_DELAY)

    cache_path.parent.mkdir(parents=True, exist_ok=True)
    cache_path.write_text(json.dumps(cache, indent=2), encoding="utf-8")
    logger.info("Saved %d RxNorm lookups to %s", len(cache), cache_path)
    return cache
