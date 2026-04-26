"""Build the SQLite FTS5 search index from ETL output."""

from __future__ import annotations

import logging
import sqlite3
from collections import defaultdict
from datetime import UTC, datetime
from pathlib import Path

from .models import DrugProduct, Supplement

logger = logging.getLogger(__name__)

SCHEMA_VERSION = "1.0"


def create_schema(conn: sqlite3.Connection) -> None:
    """Create the database schema for the drug search index."""
    conn.executescript("""
        -- Drug concepts (one row per unique drug)
        CREATE TABLE IF NOT EXISTS drug_concepts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            preferred_name TEXT NOT NULL,
            generic_name TEXT,
            rxcui TEXT,
            product_type TEXT DEFAULT 'drug'
        );

        -- Drug aliases for search (brand names, alternate names)
        CREATE TABLE IF NOT EXISTS drug_aliases (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            concept_id INTEGER NOT NULL REFERENCES drug_concepts(id),
            alias TEXT NOT NULL,
            alias_type TEXT NOT NULL,
            source TEXT NOT NULL,
            UNIQUE(concept_id, alias, alias_type)
        );

        -- Individual drug products (NDC-level)
        CREATE TABLE IF NOT EXISTS drug_products (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            concept_id INTEGER NOT NULL REFERENCES drug_concepts(id),
            ndc TEXT,
            dosage_form TEXT,
            strength TEXT,
            route TEXT,
            manufacturer TEXT,
            source TEXT NOT NULL
        );

        -- FTS5 virtual table for drug autocomplete
        CREATE VIRTUAL TABLE IF NOT EXISTS drug_fts USING fts5(
            preferred_name,
            aliases,
            generic_name,
            content='',
            content_rowid='rowid',
            tokenize='unicode61 remove_diacritics 2'
        );

        -- Supplements (separate from drugs)
        CREATE TABLE IF NOT EXISTS supplements (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            ingredients TEXT,
            manufacturer TEXT,
            dosage_form TEXT,
            source TEXT NOT NULL DEFAULT 'dailymed'
        );

        -- FTS5 for supplement autocomplete
        CREATE VIRTUAL TABLE IF NOT EXISTS supplement_fts USING fts5(
            name,
            ingredients_text,
            content='',
            content_rowid='rowid',
            tokenize='unicode61 remove_diacritics 2'
        );

        -- Build metadata
        CREATE TABLE IF NOT EXISTS metadata (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );

        -- Indexes
        CREATE INDEX IF NOT EXISTS idx_drug_aliases_concept ON drug_aliases(concept_id);
        CREATE INDEX IF NOT EXISTS idx_drug_products_concept ON drug_products(concept_id);
        CREATE INDEX IF NOT EXISTS idx_drug_concepts_rxcui ON drug_concepts(rxcui);
        CREATE INDEX IF NOT EXISTS idx_drug_products_ndc ON drug_products(ndc);
    """)


def build_drug_concepts(
    drugs: list[DrugProduct],
) -> dict[str, dict]:
    """Group drug products into concepts by generic name.

    Products with the same generic name (case-insensitive) are grouped
    into a single concept. The preferred name is derived from the generic
    name (title-cased) when available, otherwise from the brand name.

    Args:
        drugs: List of DrugProduct objects to group.

    Returns:
        Dict mapping concept key (lowered generic name) to concept data
        containing products, brand_names set, and generic_name.
    """
    concepts: dict[str, dict] = defaultdict(
        lambda: {"products": [], "brand_names": set(), "generic_name": ""},
    )

    for drug in drugs:
        key = (drug.generic_name or drug.drug_name).strip().lower()
        if not key:
            continue
        entry = concepts[key]
        entry["products"].append(drug)
        entry["generic_name"] = drug.generic_name or drug.drug_name
        if drug.brand_name:
            entry["brand_names"].add(drug.brand_name.strip())

    return dict(concepts)


def _insert_drug_concepts(
    conn: sqlite3.Connection,
    concepts: dict[str, dict],
    rxnorm_cache: dict[str, str] | None = None,
) -> dict[str, int]:
    """Insert drug concepts, aliases, and products into the database.

    Returns:
        Dict mapping concept key → concept_id.
    """
    rxcache = rxnorm_cache or {}
    concept_ids: dict[str, int] = {}

    for key, data in concepts.items():
        generic_name = data["generic_name"]
        preferred_name = generic_name.strip().title() if generic_name else key.title()
        rxcui = rxcache.get(key) or rxcache.get(generic_name.lower())

        # Determine product_type from the first product (if available)
        product_type = "drug"
        if data["products"]:
            pt = data["products"][0].product_type
            if pt:
                product_type = pt

        cursor = conn.execute(
            "INSERT INTO drug_concepts (preferred_name, generic_name, rxcui, product_type) "
            "VALUES (?, ?, ?, ?)",
            (preferred_name, generic_name, rxcui, product_type),
        )
        concept_id = cursor.lastrowid
        concept_ids[key] = concept_id

        # Insert generic name as an alias
        if generic_name:
            conn.execute(
                "INSERT OR IGNORE INTO drug_aliases (concept_id, alias, alias_type, source) "
                "VALUES (?, ?, 'generic', 'openfda')",
                (concept_id, generic_name),
            )

        # Insert brand names as aliases
        for brand in sorted(data["brand_names"]):
            if brand:
                conn.execute(
                    "INSERT OR IGNORE INTO drug_aliases "
                    "(concept_id, alias, alias_type, source) "
                    "VALUES (?, ?, 'brand', 'openfda')",
                    (concept_id, brand),
                )

        # Insert individual products
        for drug in data["products"]:
            conn.execute(
                "INSERT INTO drug_products "
                "(concept_id, ndc, dosage_form, strength, route, manufacturer, source) "
                "VALUES (?, ?, ?, ?, ?, ?, ?)",
                (
                    concept_id,
                    drug.ndc,
                    drug.dosage_form,
                    drug.strength,
                    drug.route,
                    drug.manufacturer,
                    drug.source,
                ),
            )

    return concept_ids


def _populate_drug_fts(
    conn: sqlite3.Connection,
    concepts: dict[str, dict],
    concept_ids: dict[str, int],
) -> None:
    """Populate the drug FTS5 index from concept data."""
    for key, data in concepts.items():
        concept_id = concept_ids[key]
        generic = data["generic_name"]
        preferred_name = generic.strip().title() if generic else key.title()
        generic_name = data["generic_name"]
        all_aliases = " ".join(sorted(data["brand_names"]))

        conn.execute(
            "INSERT INTO drug_fts(rowid, preferred_name, aliases, generic_name) "
            "VALUES (?, ?, ?, ?)",
            (concept_id, preferred_name, all_aliases, generic_name),
        )


def _insert_supplements(
    conn: sqlite3.Connection,
    supplements: list[Supplement],
) -> None:
    """Insert supplements and populate the supplement FTS5 index."""
    import json

    for supp in supplements:
        ingredients_json = json.dumps(supp.ingredients) if supp.ingredients else "[]"
        cursor = conn.execute(
            "INSERT INTO supplements (name, ingredients, manufacturer, dosage_form, source) "
            "VALUES (?, ?, ?, ?, ?)",
            (supp.name, ingredients_json, supp.manufacturer, supp.dosage_form, supp.source),
        )
        supp_id = cursor.lastrowid

        ingredients_text = " ".join(supp.ingredients)
        conn.execute(
            "INSERT INTO supplement_fts(rowid, name, ingredients_text) VALUES (?, ?, ?)",
            (supp_id, supp.name, ingredients_text),
        )


def _insert_metadata(
    conn: sqlite3.Connection,
    drug_count: int,
    supplement_count: int,
    concept_count: int,
    alias_count: int,
) -> None:
    """Insert build metadata into the metadata table."""
    meta = {
        "schema_version": SCHEMA_VERSION,
        "build_date": datetime.now(tz=UTC).isoformat(),
        "drug_concept_count": str(drug_count),
        "supplement_count": str(supplement_count),
        "total_concept_count": str(concept_count),
        "alias_count": str(alias_count),
    }
    for k, v in meta.items():
        conn.execute(
            "INSERT OR REPLACE INTO metadata (key, value) VALUES (?, ?)",
            (k, v),
        )


def build_index(
    drugs: list[DrugProduct],
    supplements: list[Supplement],
    output_path: Path,
    rxnorm_cache: dict[str, str] | None = None,
) -> Path:
    """Build the SQLite FTS5 search index.

    Creates a SQLite database with drug concepts, aliases, products,
    supplements, and FTS5 virtual tables for fast autocomplete search.

    Args:
        drugs: List of DrugProduct objects from the ETL pipeline.
        supplements: List of Supplement objects from the ETL pipeline.
        output_path: Path where the SQLite database will be written.
        rxnorm_cache: Optional dict mapping drug name (lowercase) → RxCUI.

    Returns:
        Path to the created SQLite database.
    """
    output_path.parent.mkdir(parents=True, exist_ok=True)

    # Remove existing database so we build fresh
    if output_path.exists():
        output_path.unlink()

    conn = sqlite3.connect(str(output_path))
    try:
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute("PRAGMA synchronous=NORMAL")

        create_schema(conn)

        # Build and insert drug concepts
        concepts = build_drug_concepts(drugs)
        concept_ids = _insert_drug_concepts(conn, concepts, rxnorm_cache)
        _populate_drug_fts(conn, concepts, concept_ids)

        # Insert supplements
        _insert_supplements(conn, supplements)

        # Gather counts for metadata
        concept_count = conn.execute("SELECT COUNT(*) FROM drug_concepts").fetchone()[0]
        alias_count = conn.execute("SELECT COUNT(*) FROM drug_aliases").fetchone()[0]
        supp_count = conn.execute("SELECT COUNT(*) FROM supplements").fetchone()[0]

        _insert_metadata(conn, concept_count, supp_count, concept_count + supp_count, alias_count)

        conn.commit()

        # VACUUM to compact the database
        conn.execute("VACUUM")

        logger.info(
            "Built index: %d concepts, %d aliases, %d products, %d supplements → %s",
            concept_count,
            alias_count,
            conn.execute("SELECT COUNT(*) FROM drug_products").fetchone()[0],
            supp_count,
            output_path,
        )
    finally:
        conn.close()

    return output_path


def get_index_stats(db_path: Path) -> dict[str, str | int]:
    """Get statistics from a built index.

    Args:
        db_path: Path to the SQLite database.

    Returns:
        Dict of statistic name → value.
    """
    conn = sqlite3.connect(str(db_path))
    try:
        stats: dict[str, str | int] = {}
        stats["concepts"] = conn.execute("SELECT COUNT(*) FROM drug_concepts").fetchone()[0]
        stats["aliases"] = conn.execute("SELECT COUNT(*) FROM drug_aliases").fetchone()[0]
        stats["products"] = conn.execute("SELECT COUNT(*) FROM drug_products").fetchone()[0]
        stats["supplements"] = conn.execute("SELECT COUNT(*) FROM supplements").fetchone()[0]
        stats["file_size_bytes"] = db_path.stat().st_size

        # Metadata
        for row in conn.execute("SELECT key, value FROM metadata"):
            stats[f"meta_{row[0]}"] = row[1]

        return stats
    finally:
        conn.close()
