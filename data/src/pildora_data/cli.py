"""CLI entry point for the Pildora ETL pipeline."""

from __future__ import annotations

import argparse
import logging
import sys
from pathlib import Path

from pildora_data.download import download_dailymed_supplements, download_openfda_ndc
from pildora_data.output import generate_quality_report, write_jsonl
from pildora_data.parsers.dailymed import parse_dailymed_supplements
from pildora_data.parsers.openfda import parse_openfda_ndc

logger = logging.getLogger("pildora_data")


def main() -> None:
    """Run the ETL pipeline."""
    parser = argparse.ArgumentParser(
        prog="pildora-etl",
        description="Pildora drug data ETL pipeline — downloads, parses, and exports drug data.",
    )
    parser.add_argument(
        "--cache-dir",
        type=Path,
        default=Path("cache"),
        help="Directory for cached downloads (default: cache/)",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("output"),
        help="Directory for output files (default: output/)",
    )
    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Enable verbose logging",
    )
    parser.add_argument(
        "--index",
        action="store_true",
        help="Build the SQLite FTS5 search index after ETL",
    )
    parser.add_argument(
        "--output-db",
        type=Path,
        default=None,
        help="Path for the SQLite index (default: <output-dir>/pildora_drugs.sqlite)",
    )
    parser.add_argument(
        "--skip-rxnorm",
        action="store_true",
        help="Skip RxNorm API lookups during index build",
    )
    parser.add_argument(
        "--compress",
        action="store_true",
        help="Compress the index with gzip after building",
    )
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    )

    cache_dir: Path = args.cache_dir
    output_dir: Path = args.output_dir
    output_dir.mkdir(parents=True, exist_ok=True)

    # Step 1: Download data
    logger.info("=== Step 1: Downloading data ===")
    try:
        openfda_path = download_openfda_ndc(cache_dir)
    except Exception:
        logger.exception("Failed to download openFDA data")
        sys.exit(1)

    try:
        dailymed_path = download_dailymed_supplements(cache_dir)
    except Exception:
        logger.exception("Failed to download DailyMed data")
        sys.exit(1)

    # Step 2: Parse openFDA NDC data
    logger.info("=== Step 2: Parsing openFDA NDC data ===")
    drugs = parse_openfda_ndc(openfda_path)
    logger.info("Parsed %d drug products.", len(drugs))

    # Step 3: Parse DailyMed supplements
    logger.info("=== Step 3: Parsing DailyMed supplements ===")
    supplements = parse_dailymed_supplements(dailymed_path)
    logger.info("Parsed %d supplements.", len(supplements))

    # Step 4: Write JSONL output
    logger.info("=== Step 4: Writing JSONL output ===")
    write_jsonl(drugs, output_dir / "drugs.jsonl")
    write_jsonl(supplements, output_dir / "supplements.jsonl")

    # Step 5: Quality report
    logger.info("=== Step 5: Quality report ===")
    report = generate_quality_report(drugs, supplements)
    report_path = output_dir / "quality_report.txt"
    report_path.write_text(report, encoding="utf-8")
    print(report)

    # Step 6: Build search index (optional)
    if args.index:
        from pildora_data.index_builder import build_index, get_index_stats

        logger.info("=== Step 6: Building SQLite FTS5 search index ===")
        db_path = args.output_db or (output_dir / "pildora_drugs.sqlite")

        rxnorm_cache = None
        if not args.skip_rxnorm:
            from pildora_data.index_builder import build_drug_concepts
            from pildora_data.rxnorm import fetch_rxnorm_cache

            concepts = build_drug_concepts(drugs)
            # Sort by product count descending, take top 200
            sorted_keys = sorted(concepts, key=lambda k: len(concepts[k]["products"]), reverse=True)
            top_names = [concepts[k]["generic_name"] for k in sorted_keys[:200]]
            cache_path = cache_dir / "rxnorm_cache.json"
            try:
                rxnorm_cache = fetch_rxnorm_cache(top_names, cache_path)
            except Exception:
                logger.exception("RxNorm lookup failed, continuing without RxCUI")

        build_index(drugs, supplements, db_path, rxnorm_cache=rxnorm_cache)

        stats = get_index_stats(db_path)
        print("\n--- Search Index Statistics ---")
        print(f"  Concepts:    {stats['concepts']}")
        print(f"  Aliases:     {stats['aliases']}")
        print(f"  Products:    {stats['products']}")
        print(f"  Supplements: {stats['supplements']}")
        print(f"  File size:   {stats['file_size_bytes']:,} bytes")

        # Step 7: Compress (optional)
        if args.compress:
            from pildora_data.compress import compress_index

            logger.info("=== Step 7: Compressing index ===")
            gz_path = compress_index(db_path)
            gz_size = gz_path.stat().st_size
            print(f"  Compressed:  {gz_size:,} bytes → {gz_path}")

    logger.info("ETL pipeline complete. Output written to %s", output_dir)
