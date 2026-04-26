use std::path::Path;
use std::time::Instant;

use rusqlite::Connection;

// ── Schema setup (mirrors data pipeline's index_builder.py) ─────────────────

fn create_test_index(path: &Path) {
    let conn = Connection::open(path).unwrap();

    conn.execute_batch(
        "
        CREATE TABLE drug_concepts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            preferred_name TEXT NOT NULL,
            generic_name TEXT,
            rxcui TEXT,
            product_type TEXT DEFAULT 'drug'
        );

        CREATE TABLE drug_aliases (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            concept_id INTEGER NOT NULL REFERENCES drug_concepts(id),
            alias TEXT NOT NULL,
            alias_type TEXT NOT NULL,
            source TEXT NOT NULL,
            UNIQUE(concept_id, alias, alias_type)
        );

        CREATE TABLE drug_products (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            concept_id INTEGER NOT NULL REFERENCES drug_concepts(id),
            ndc TEXT,
            dosage_form TEXT,
            strength TEXT,
            route TEXT,
            manufacturer TEXT,
            source TEXT NOT NULL
        );

        CREATE VIRTUAL TABLE drug_fts USING fts5(
            preferred_name,
            aliases,
            generic_name,
            content='',
            content_rowid='rowid',
            tokenize='unicode61 remove_diacritics 2'
        );

        CREATE TABLE supplements (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            ingredients TEXT,
            manufacturer TEXT,
            dosage_form TEXT,
            source TEXT NOT NULL DEFAULT 'dailymed'
        );

        CREATE VIRTUAL TABLE supplement_fts USING fts5(
            name,
            ingredients_text,
            content='',
            content_rowid='rowid',
            tokenize='unicode61 remove_diacritics 2'
        );
        ",
    )
    .unwrap();

    // Insert drug concepts
    let drugs: &[(&str, &str, &str)] = &[
        ("Lisinopril", "LISINOPRIL", "29046"),
        (
            "Lisinopril-Hydrochlorothiazide",
            "LISINOPRIL/HCTZ",
            "214758",
        ),
        ("Metformin Hydrochloride", "METFORMIN", "6809"),
        ("Atorvastatin Calcium", "ATORVASTATIN", "83367"),
        ("Omeprazole", "OMEPRAZOLE", "7646"),
        ("Amlodipine Besylate", "AMLODIPINE", "17767"),
        ("Amoxicillin", "AMOXICILLIN", "723"),
        ("Ibuprofen", "IBUPROFEN", "5640"),
    ];

    for (preferred, generic, rxcui) in drugs {
        conn.execute(
            "INSERT INTO drug_concepts (preferred_name, generic_name, rxcui, product_type)
             VALUES (?1, ?2, ?3, 'drug')",
            rusqlite::params![preferred, generic, rxcui],
        )
        .unwrap();

        let concept_id = conn.last_insert_rowid();

        // Populate FTS index
        conn.execute(
            "INSERT INTO drug_fts (rowid, preferred_name, aliases, generic_name)
             VALUES (?1, ?2, '', ?3)",
            rusqlite::params![concept_id, preferred, generic],
        )
        .unwrap();
    }

    // Insert brand aliases for a couple of drugs
    conn.execute(
        "INSERT INTO drug_aliases (concept_id, alias, alias_type, source)
         VALUES (1, 'Zestril', 'brand_name', 'openfda')",
        [],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO drug_aliases (concept_id, alias, alias_type, source)
         VALUES (1, 'Prinivil', 'brand_name', 'openfda')",
        [],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO drug_aliases (concept_id, alias, alias_type, source)
         VALUES (4, 'Lipitor', 'brand_name', 'openfda')",
        [],
    )
    .unwrap();

    // Insert drug products
    conn.execute(
        "INSERT INTO drug_products (concept_id, ndc, dosage_form, strength, route, manufacturer, source)
         VALUES (1, '12345-678-90', 'Tablet', '10 mg', 'Oral', 'Generic Pharma', 'openfda')",
        [],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO drug_products (concept_id, ndc, dosage_form, strength, route, manufacturer, source)
         VALUES (1, '12345-678-91', 'Tablet', '20 mg', 'Oral', 'Generic Pharma', 'openfda')",
        [],
    )
    .unwrap();

    // Insert supplements
    let supplements: &[(&str, &str)] = &[
        ("Vitamin D3", "cholecalciferol"),
        (
            "Fish Oil Omega-3",
            "eicosapentaenoic acid, docosahexaenoic acid",
        ),
        ("Magnesium Glycinate", "magnesium"),
    ];

    for (name, ingredients) in supplements {
        conn.execute(
            "INSERT INTO supplements (name, ingredients, dosage_form, source)
             VALUES (?1, ?2, 'Capsule', 'dailymed')",
            rusqlite::params![name, ingredients],
        )
        .unwrap();

        let supp_id = conn.last_insert_rowid();

        conn.execute(
            "INSERT INTO supplement_fts (rowid, name, ingredients_text)
             VALUES (?1, ?2, ?3)",
            rusqlite::params![supp_id, name, ingredients],
        )
        .unwrap();
    }
}

// ── Binary-crate search functions cannot be imported directly ────────────────
// We replicate the search logic here using the same SQL queries.

#[derive(Debug)]
#[allow(dead_code)]
struct DrugMatch {
    preferred_name: String,
    generic_name: Option<String>,
    rxcui: Option<String>,
    product_type: String,
}

#[derive(Debug)]
#[allow(dead_code)]
struct DrugProductInfo {
    dosage_form: Option<String>,
    strength: Option<String>,
    manufacturer: Option<String>,
}

fn search_drugs(path: &Path, query: &str, limit: usize) -> Vec<DrugMatch> {
    let trimmed = query.trim();
    if trimmed.is_empty() {
        return vec![];
    }
    let conn = match Connection::open_with_flags(path, rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY) {
        Ok(c) => c,
        Err(_) => return vec![],
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

fn search_supplements(path: &Path, query: &str, limit: usize) -> Vec<DrugMatch> {
    let trimmed = query.trim();
    if trimmed.is_empty() {
        return vec![];
    }
    let conn = match Connection::open_with_flags(path, rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY) {
        Ok(c) => c,
        Err(_) => return vec![],
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

fn search_all(path: &Path, query: &str, limit: usize) -> Vec<DrugMatch> {
    let mut results = search_drugs(path, query, limit);
    results.extend(search_supplements(path, query, limit));
    results.truncate(limit);
    results
}

fn get_product_details(path: &Path, preferred_name: &str) -> Vec<DrugProductInfo> {
    let conn = match Connection::open_with_flags(path, rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY) {
        Ok(c) => c,
        Err(_) => return vec![],
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

fn get_brand_names(path: &Path, preferred_name: &str) -> Vec<String> {
    let conn = match Connection::open_with_flags(path, rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY) {
        Ok(c) => c,
        Err(_) => return vec![],
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

// ── Tests ───────────────────────────────────────────────────────────────────

#[test]
fn search_drugs_prefix_match() {
    let dir = tempfile::tempdir().unwrap();
    let db_path = dir.path().join("drug-index.db");
    create_test_index(&db_path);

    let results = search_drugs(&db_path, "lisino", 10);
    assert_eq!(results.len(), 2);
    assert!(results.iter().any(|r| r.preferred_name == "Lisinopril"));
    assert!(
        results
            .iter()
            .any(|r| r.preferred_name == "Lisinopril-Hydrochlorothiazide")
    );
}

#[test]
fn search_drugs_single_match() {
    let dir = tempfile::tempdir().unwrap();
    let db_path = dir.path().join("drug-index.db");
    create_test_index(&db_path);

    let results = search_drugs(&db_path, "metfor", 10);
    assert_eq!(results.len(), 1);
    assert_eq!(results[0].preferred_name, "Metformin Hydrochloride");
    assert_eq!(results[0].generic_name.as_deref(), Some("METFORMIN"));
    assert_eq!(results[0].rxcui.as_deref(), Some("6809"));
    assert_eq!(results[0].product_type, "drug");
}

#[test]
fn search_supplements_prefix_match() {
    let dir = tempfile::tempdir().unwrap();
    let db_path = dir.path().join("drug-index.db");
    create_test_index(&db_path);

    let results = search_supplements(&db_path, "vitamin", 10);
    assert_eq!(results.len(), 1);
    assert_eq!(results[0].preferred_name, "Vitamin D3");
    assert_eq!(results[0].product_type, "supplement");
}

#[test]
fn search_supplements_by_ingredient() {
    let dir = tempfile::tempdir().unwrap();
    let db_path = dir.path().join("drug-index.db");
    create_test_index(&db_path);

    let results = search_supplements(&db_path, "magnesium", 10);
    assert_eq!(results.len(), 1);
    assert_eq!(results[0].preferred_name, "Magnesium Glycinate");
}

#[test]
fn search_all_combined_results() {
    let dir = tempfile::tempdir().unwrap();
    let db_path = dir.path().join("drug-index.db");
    create_test_index(&db_path);

    // "am" should match Amlodipine, Amoxicillin (drugs)
    let results = search_all(&db_path, "am", 10);
    assert!(results.len() >= 2);

    let names: Vec<&str> = results.iter().map(|r| r.preferred_name.as_str()).collect();
    assert!(names.contains(&"Amlodipine Besylate") || names.contains(&"Amoxicillin"));
}

#[test]
fn search_all_respects_limit() {
    let dir = tempfile::tempdir().unwrap();
    let db_path = dir.path().join("drug-index.db");
    create_test_index(&db_path);

    let results = search_all(&db_path, "a", 3);
    assert!(results.len() <= 3);
}

#[test]
fn search_empty_query_returns_empty() {
    let dir = tempfile::tempdir().unwrap();
    let db_path = dir.path().join("drug-index.db");
    create_test_index(&db_path);

    assert!(search_drugs(&db_path, "", 10).is_empty());
    assert!(search_drugs(&db_path, "   ", 10).is_empty());
    assert!(search_supplements(&db_path, "", 10).is_empty());
    assert!(search_all(&db_path, "", 10).is_empty());
}

#[test]
fn search_missing_index_returns_empty() {
    let missing = Path::new("nonexistent_drug_index_file.db");
    assert!(search_drugs(missing, "lisinopril", 10).is_empty());
    assert!(search_supplements(missing, "vitamin", 10).is_empty());
    assert!(search_all(missing, "lisinopril", 10).is_empty());
}

#[test]
fn search_no_match_returns_empty() {
    let dir = tempfile::tempdir().unwrap();
    let db_path = dir.path().join("drug-index.db");
    create_test_index(&db_path);

    assert!(search_drugs(&db_path, "zzzznotadrug", 10).is_empty());
    assert!(search_supplements(&db_path, "zzzznotasupplement", 10).is_empty());
}

#[test]
fn get_product_details_for_known_drug() {
    let dir = tempfile::tempdir().unwrap();
    let db_path = dir.path().join("drug-index.db");
    create_test_index(&db_path);

    let products = get_product_details(&db_path, "Lisinopril");
    assert_eq!(products.len(), 2);
    assert!(
        products
            .iter()
            .any(|p| p.strength.as_deref() == Some("10 mg"))
    );
    assert!(
        products
            .iter()
            .any(|p| p.strength.as_deref() == Some("20 mg"))
    );
    assert_eq!(products[0].manufacturer.as_deref(), Some("Generic Pharma"));
}

#[test]
fn get_brand_names_for_known_drug() {
    let dir = tempfile::tempdir().unwrap();
    let db_path = dir.path().join("drug-index.db");
    create_test_index(&db_path);

    let brands = get_brand_names(&db_path, "Lisinopril");
    assert_eq!(brands.len(), 2);
    assert!(brands.contains(&"Zestril".to_string()));
    assert!(brands.contains(&"Prinivil".to_string()));
}

#[test]
fn get_brand_names_missing_returns_empty() {
    let dir = tempfile::tempdir().unwrap();
    let db_path = dir.path().join("drug-index.db");
    create_test_index(&db_path);

    let brands = get_brand_names(&db_path, "Omeprazole");
    assert!(brands.is_empty());
}

#[test]
fn search_latency_under_50ms() {
    let dir = tempfile::tempdir().unwrap();
    let db_path = dir.path().join("drug-index.db");
    create_test_index(&db_path);

    let start = Instant::now();
    for _ in 0..100 {
        let _ = search_all(&db_path, "lisino", 10);
    }
    let elapsed = start.elapsed();
    let avg_ms = elapsed.as_millis() as f64 / 100.0;

    assert!(
        avg_ms < 50.0,
        "Average search latency {avg_ms:.1}ms exceeds 50ms threshold"
    );
}
