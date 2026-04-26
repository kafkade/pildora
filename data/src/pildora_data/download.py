"""Download functions for openFDA and DailyMed data sources."""

from __future__ import annotations

import json
import logging
import zipfile
from pathlib import Path

import httpx

logger = logging.getLogger(__name__)

OPENFDA_DOWNLOAD_INDEX = "https://api.fda.gov/download.json"
DAILYMED_SPL_API = "https://dailymed.nlm.nih.gov/dailymed/services/v2/spls.json"

HTTP_TIMEOUT = 120.0
DAILYMED_PAGE_SIZE = 100
DAILYMED_MAX_PAGES = 50


def download_openfda_ndc(cache_dir: Path) -> Path:
    """Download openFDA NDC Directory bulk data and extract JSON.

    Fetches the download index from the openFDA API, finds the NDC dataset
    ZIP URL, downloads it (if not already cached), and extracts the JSON files.

    Args:
        cache_dir: Directory to cache downloaded files.

    Returns:
        Path to the directory containing extracted JSON files.
    """
    cache_dir.mkdir(parents=True, exist_ok=True)
    extracted_dir = cache_dir / "openfda_ndc"

    if extracted_dir.exists() and any(extracted_dir.glob("*.json")):
        logger.info("openFDA NDC data already cached at %s", extracted_dir)
        return extracted_dir

    logger.info("Fetching openFDA download index...")
    with httpx.Client(timeout=HTTP_TIMEOUT) as client:
        resp = client.get(OPENFDA_DOWNLOAD_INDEX)
        resp.raise_for_status()
        index = resp.json()

    ndc_partitions = index.get("results", {}).get("drug", {}).get("ndc", {}).get("partitions", [])
    if not ndc_partitions:
        msg = "No NDC partitions found in openFDA download index"
        raise RuntimeError(msg)

    zip_path = cache_dir / "openfda_ndc.zip"
    if not zip_path.exists():
        download_url = ndc_partitions[0]["file"]
        logger.info("Downloading openFDA NDC data from %s ...", download_url)
        _download_file(download_url, zip_path)

    logger.info("Extracting openFDA NDC data...")
    extracted_dir.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(zip_path) as zf:
        zf.extractall(extracted_dir)

    json_files = list(extracted_dir.rglob("*.json"))
    logger.info("Extracted %d JSON file(s) to %s", len(json_files), extracted_dir)
    return extracted_dir


def download_dailymed_supplements(cache_dir: Path) -> Path:
    """Download DailyMed supplement SPL data via the REST API.

    Paginates through the DailyMed SPL API filtering for dietary supplements
    and saves the combined results as a single JSON file.

    Args:
        cache_dir: Directory to cache downloaded files.

    Returns:
        Path to the JSON file containing supplement data.
    """
    cache_dir.mkdir(parents=True, exist_ok=True)
    output_file = cache_dir / "dailymed_supplements.json"

    if output_file.exists():
        logger.info("DailyMed supplement data already cached at %s", output_file)
        return output_file

    logger.info("Downloading DailyMed supplement data...")
    all_records: list[dict] = []

    with httpx.Client(timeout=HTTP_TIMEOUT) as client:
        for page in range(1, DAILYMED_MAX_PAGES + 1):
            params = {
                "drug_class_code": "dietary_supplement",
                "pagesize": DAILYMED_PAGE_SIZE,
                "page": page,
            }
            logger.info("Fetching DailyMed page %d...", page)

            try:
                resp = client.get(DAILYMED_SPL_API, params=params)
                resp.raise_for_status()
            except httpx.HTTPStatusError as e:
                logger.warning(
                    "DailyMed API returned %s on page %d, stopping.",
                    e.response.status_code,
                    page,
                )
                break

            data = resp.json()
            records = data.get("data", [])
            if not records:
                logger.info("No more records at page %d, stopping.", page)
                break

            all_records.extend(records)
            logger.info("Fetched %d records (total: %d)", len(records), len(all_records))

            metadata = data.get("metadata", {})
            total_pages = metadata.get("total_pages", page)
            if page >= total_pages:
                break

    logger.info("Downloaded %d total DailyMed supplement records.", len(all_records))
    output_file.write_text(json.dumps({"data": all_records}, indent=2), encoding="utf-8")
    return output_file


def _download_file(url: str, dest: Path) -> None:
    """Stream-download a file to disk."""
    with (
        httpx.Client(timeout=HTTP_TIMEOUT, follow_redirects=True) as client,
        client.stream("GET", url) as resp,
    ):
        resp.raise_for_status()
        total = int(resp.headers.get("content-length", 0))
        downloaded = 0
        with open(dest, "wb") as f:
            for chunk in resp.iter_bytes(chunk_size=8192):
                f.write(chunk)
                downloaded += len(chunk)
        if total:
            logger.info("Downloaded %d / %d bytes", downloaded, total)
        else:
            logger.info("Downloaded %d bytes", downloaded)
