"""Search the drug and supplement index."""

from __future__ import annotations

import sqlite3
from pathlib import Path


def search_drugs(db_path: Path, query: str, limit: int = 10) -> list[dict]:
    """Search for drugs using FTS5. Returns ranked results.

    Args:
        db_path: Path to the SQLite index database.
        query: Search query string (supports FTS5 syntax including prefix*).
        limit: Maximum number of results to return.

    Returns:
        List of dicts with drug concept data, ordered by relevance.
    """
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    try:
        results = conn.execute(
            """
            SELECT dc.id, dc.preferred_name, dc.generic_name, dc.rxcui,
                   dc.product_type, drug_fts.rank
            FROM drug_fts
            JOIN drug_concepts dc ON dc.id = drug_fts.rowid
            WHERE drug_fts MATCH ?
            ORDER BY drug_fts.rank
            LIMIT ?
            """,
            (query, limit),
        ).fetchall()
        return [dict(r) for r in results]
    except sqlite3.OperationalError:
        return []
    finally:
        conn.close()


def search_supplements(db_path: Path, query: str, limit: int = 10) -> list[dict]:
    """Search for supplements using FTS5.

    Args:
        db_path: Path to the SQLite index database.
        query: Search query string (supports FTS5 syntax including prefix*).
        limit: Maximum number of results to return.

    Returns:
        List of dicts with supplement data, ordered by relevance.
    """
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    try:
        results = conn.execute(
            """
            SELECT s.id, s.name, s.ingredients, s.manufacturer,
                   s.dosage_form, supplement_fts.rank
            FROM supplement_fts
            JOIN supplements s ON s.id = supplement_fts.rowid
            WHERE supplement_fts MATCH ?
            ORDER BY supplement_fts.rank
            LIMIT ?
            """,
            (query, limit),
        ).fetchall()
        return [dict(r) for r in results]
    except sqlite3.OperationalError:
        return []
    finally:
        conn.close()


def search_all(db_path: Path, query: str, limit: int = 10) -> list[dict]:
    """Search drugs and supplements, merge and rank results.

    Drug results are tagged with type='drug', supplement results with
    type='supplement'. Results are interleaved by rank (lower = better).

    Args:
        db_path: Path to the SQLite index database.
        query: Search query string.
        limit: Maximum number of results to return.

    Returns:
        List of dicts with combined results, ordered by relevance.
    """
    drug_results = search_drugs(db_path, query, limit=limit)
    supp_results = search_supplements(db_path, query, limit=limit)

    for r in drug_results:
        r["type"] = "drug"
    for r in supp_results:
        r["type"] = "supplement"

    combined = drug_results + supp_results
    combined.sort(key=lambda r: r.get("rank", 0))
    return combined[:limit]
