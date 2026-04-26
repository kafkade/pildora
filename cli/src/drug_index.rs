//! Query the local FTS5 drug/supplement index built by the data pipeline.
//!
//! All searches are read-only and gracefully degrade: a missing or corrupt
//! index silently returns empty results rather than crashing.

use std::path::{Path, PathBuf};

use rusqlite::{Connection, OpenFlags};

/// A single match from the drug or supplement FTS index.
#[derive(Debug, Clone)]
pub struct DrugMatch {
    pub preferred_name: String,
    pub generic_name: Option<String>,
    pub rxcui: Option<String>,
    pub product_type: String,
}

/// Product-level details for a drug concept.
#[allow(dead_code)]
#[derive(Debug, Clone)]
pub struct DrugProductInfo {
    pub dosage_form: Option<String>,
    pub strength: Option<String>,
    pub manufacturer: Option<String>,
}

/// Default location of the drug index database.
pub fn default_index_path() -> PathBuf {
    crate::storage::default_data_dir().join("drug-index.db")
}

/// Open the index read-only, returning `None` if the file is missing or corrupt.
fn open_index(path: &Path) -> Option<Connection> {
    Connection::open_with_flags(path, OpenFlags::SQLITE_OPEN_READ_ONLY).ok()
}

/// Search the drug FTS index for matches.
///
/// Appends `*` to the query for prefix matching. Returns up to `limit` results
/// ordered by FTS5 relevance rank.
pub fn search_drugs(index_path: &Path, query: &str, limit: usize) -> Vec<DrugMatch> {
    let trimmed = query.trim();
    if trimmed.is_empty() {
        return vec![];
    }

    let Some(conn) = open_index(index_path) else {
        return vec![];
    };

    let fts_query = format!("{trimmed}*");

    let Ok(mut stmt) = conn.prepare(
        "SELECT dc.preferred_name, dc.generic_name, dc.rxcui, dc.product_type
         FROM drug_fts
         JOIN drug_concepts dc ON dc.id = drug_fts.rowid
         WHERE drug_fts MATCH ?1
         ORDER BY drug_fts.rank
         LIMIT ?2",
    ) else {
        return vec![];
    };

    let limit_i64 = i64::try_from(limit).unwrap_or(i64::MAX);

    stmt.query_map(rusqlite::params![fts_query, limit_i64], |row| {
        Ok(DrugMatch {
            preferred_name: row.get(0)?,
            generic_name: row.get(1)?,
            rxcui: row.get(2)?,
            product_type: row.get::<_, Option<String>>(3)?.unwrap_or_default(),
        })
    })
    .ok()
    .map(|rows| rows.filter_map(Result::ok).collect())
    .unwrap_or_default()
}

/// Search the supplement FTS index for matches.
pub fn search_supplements(index_path: &Path, query: &str, limit: usize) -> Vec<DrugMatch> {
    let trimmed = query.trim();
    if trimmed.is_empty() {
        return vec![];
    }

    let Some(conn) = open_index(index_path) else {
        return vec![];
    };

    let fts_query = format!("{trimmed}*");

    let Ok(mut stmt) = conn.prepare(
        "SELECT s.name, s.ingredients, s.dosage_form
         FROM supplement_fts
         JOIN supplements s ON s.id = supplement_fts.rowid
         WHERE supplement_fts MATCH ?1
         ORDER BY supplement_fts.rank
         LIMIT ?2",
    ) else {
        return vec![];
    };

    let limit_i64 = i64::try_from(limit).unwrap_or(i64::MAX);

    stmt.query_map(rusqlite::params![fts_query, limit_i64], |row| {
        Ok(DrugMatch {
            preferred_name: row.get(0)?,
            generic_name: row.get::<_, Option<String>>(1)?,
            rxcui: None,
            product_type: "supplement".to_string(),
        })
    })
    .ok()
    .map(|rows| rows.filter_map(Result::ok).collect())
    .unwrap_or_default()
}

/// Search both drug and supplement indexes, returning merged results.
pub fn search_all(index_path: &Path, query: &str, limit: usize) -> Vec<DrugMatch> {
    let mut results = search_drugs(index_path, query, limit);
    results.extend(search_supplements(index_path, query, limit));
    results.truncate(limit);
    results
}

/// Retrieve product-level details (dosage form, strength, manufacturer)
/// for a drug concept identified by its preferred name.
#[allow(dead_code)]
pub fn get_product_details(index_path: &Path, preferred_name: &str) -> Vec<DrugProductInfo> {
    let Some(conn) = open_index(index_path) else {
        return vec![];
    };

    let Ok(mut stmt) = conn.prepare(
        "SELECT dp.dosage_form, dp.strength, dp.manufacturer
         FROM drug_products dp
         JOIN drug_concepts dc ON dc.id = dp.concept_id
         WHERE dc.preferred_name = ?1",
    ) else {
        return vec![];
    };

    stmt.query_map(rusqlite::params![preferred_name], |row| {
        Ok(DrugProductInfo {
            dosage_form: row.get(0)?,
            strength: row.get(1)?,
            manufacturer: row.get(2)?,
        })
    })
    .ok()
    .map(|rows| rows.filter_map(Result::ok).collect())
    .unwrap_or_default()
}

/// Look up brand-name aliases for a drug concept by preferred name.
pub fn get_brand_names(index_path: &Path, preferred_name: &str) -> Vec<String> {
    let Some(conn) = open_index(index_path) else {
        return vec![];
    };

    let Ok(mut stmt) = conn.prepare(
        "SELECT da.alias
         FROM drug_aliases da
         JOIN drug_concepts dc ON dc.id = da.concept_id
         WHERE dc.preferred_name = ?1 AND da.alias_type = 'brand_name'",
    ) else {
        return vec![];
    };

    stmt.query_map(rusqlite::params![preferred_name], |row| row.get(0))
        .ok()
        .map(|rows| rows.filter_map(Result::ok).collect())
        .unwrap_or_default()
}
