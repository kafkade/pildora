use serde::Serialize;

use crate::models::{DoseLog, Medication, Schedule};

/// Full export data structure.
#[derive(Debug, Serialize)]
pub struct ExportData {
    pub metadata: ExportMetadata,
    pub medications: Vec<Medication>,
    pub schedules: Vec<Schedule>,
    pub dose_logs: Vec<DoseLog>,
}

#[derive(Debug, Serialize)]
pub struct ExportMetadata {
    pub export_date: String,
    pub vault_name: String,
    pub pildora_version: String,
    pub medication_count: usize,
    pub schedule_count: usize,
    pub dose_log_count: usize,
}

/// Export as pretty-printed JSON.
pub fn to_json(data: &ExportData) -> Result<String, String> {
    serde_json::to_string_pretty(data).map_err(|e| e.to_string())
}

/// Escape a field for CSV output.
///
/// If the value contains commas, double quotes, or newlines, wrap it in
/// double quotes and double any existing double quotes (RFC 4180).
fn csv_escape(field: &str) -> String {
    if field.contains(',') || field.contains('"') || field.contains('\n') || field.contains('\r') {
        let escaped = field.replace('"', "\"\"");
        format!("\"{escaped}\"")
    } else {
        field.to_string()
    }
}

/// Export medications as CSV.
pub fn medications_to_csv(meds: &[Medication]) -> Result<String, String> {
    let mut out = String::from(
        "name,generic_name,brand_name,dosage,form,prescriber,pharmacy,notes,start_date,end_date\n",
    );

    for med in meds {
        let row = [
            csv_escape(&med.name),
            csv_escape(med.generic_name.as_deref().unwrap_or("")),
            csv_escape(med.brand_name.as_deref().unwrap_or("")),
            csv_escape(&med.dosage),
            csv_escape(&med.form),
            csv_escape(med.prescriber.as_deref().unwrap_or("")),
            csv_escape(med.pharmacy.as_deref().unwrap_or("")),
            csv_escape(med.notes.as_deref().unwrap_or("")),
            csv_escape(med.start_date.as_deref().unwrap_or("")),
            csv_escape(med.end_date.as_deref().unwrap_or("")),
        ];
        out.push_str(&row.join(","));
        out.push('\n');
    }

    Ok(out)
}

/// Export dose logs as CSV.
pub fn dose_logs_to_csv(logs: &[DoseLog]) -> Result<String, String> {
    let mut out = String::from("medication_name,taken_at,status,notes\n");

    for log in logs {
        let status = match log.status {
            crate::models::DoseStatus::Taken => "taken",
            crate::models::DoseStatus::Skipped => "skipped",
        };
        let row = [
            csv_escape(&log.medication_name),
            csv_escape(&log.taken_at.to_rfc3339()),
            csv_escape(status),
            csv_escape(log.notes.as_deref().unwrap_or("")),
        ];
        out.push_str(&row.join(","));
        out.push('\n');
    }

    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::{DoseStatus, SchedulePattern};
    use chrono::Utc;
    use uuid::Uuid;

    fn make_med(name: &str) -> Medication {
        let now = Utc::now();
        Medication {
            id: Uuid::new_v4(),
            name: name.to_string(),
            generic_name: None,
            brand_name: None,
            dosage: "10mg".to_string(),
            form: "tablet".to_string(),
            prescriber: None,
            pharmacy: None,
            notes: None,
            rxnorm_id: None,
            start_date: None,
            end_date: None,
            created_at: now,
            updated_at: now,
        }
    }

    fn make_schedule(med_name: &str) -> Schedule {
        let now = Utc::now();
        Schedule {
            medication_id: Uuid::new_v4().to_string(),
            medication_name: med_name.to_string(),
            pattern: SchedulePattern::Daily,
            times: vec![],
            created_at: now,
            updated_at: now,
        }
    }

    fn make_dose_log(med_name: &str, status: DoseStatus) -> DoseLog {
        let now = Utc::now();
        DoseLog {
            medication_id: Uuid::new_v4().to_string(),
            medication_name: med_name.to_string(),
            taken_at: now,
            status,
            notes: None,
            created_at: now,
        }
    }

    fn make_export_data(
        meds: Vec<Medication>,
        schedules: Vec<Schedule>,
        dose_logs: Vec<DoseLog>,
    ) -> ExportData {
        ExportData {
            metadata: ExportMetadata {
                export_date: Utc::now().to_rfc3339(),
                vault_name: "My Meds".to_string(),
                pildora_version: env!("CARGO_PKG_VERSION").to_string(),
                medication_count: meds.len(),
                schedule_count: schedules.len(),
                dose_log_count: dose_logs.len(),
            },
            medications: meds,
            schedules,
            dose_logs,
        }
    }

    #[test]
    fn json_roundtrip() {
        let meds = vec![make_med("Aspirin"), make_med("Vitamin D")];
        let schedules = vec![make_schedule("Aspirin")];
        let logs = vec![
            make_dose_log("Aspirin", DoseStatus::Taken),
            make_dose_log("Vitamin D", DoseStatus::Skipped),
        ];
        let data = make_export_data(meds, schedules, logs);

        let json = to_json(&data).unwrap();
        let parsed: serde_json::Value = serde_json::from_str(&json).unwrap();

        assert_eq!(parsed["medications"].as_array().unwrap().len(), 2);
        assert_eq!(parsed["schedules"].as_array().unwrap().len(), 1);
        assert_eq!(parsed["dose_logs"].as_array().unwrap().len(), 2);
        assert_eq!(parsed["medications"][0]["name"], "Aspirin");
    }

    #[test]
    fn json_metadata() {
        let meds = vec![make_med("Ibuprofen")];
        let data = make_export_data(meds, vec![], vec![]);

        let json = to_json(&data).unwrap();
        let parsed: serde_json::Value = serde_json::from_str(&json).unwrap();

        let meta = &parsed["metadata"];
        assert_eq!(meta["vault_name"], "My Meds");
        assert_eq!(meta["pildora_version"], env!("CARGO_PKG_VERSION"));
        assert_eq!(meta["medication_count"], 1);
        assert_eq!(meta["schedule_count"], 0);
        assert_eq!(meta["dose_log_count"], 0);
        assert!(meta["export_date"].as_str().unwrap().contains('T'));
    }

    #[test]
    fn csv_medications_header_and_rows() {
        let meds = vec![make_med("Aspirin"), make_med("Vitamin D")];
        let csv = medications_to_csv(&meds).unwrap();
        let lines: Vec<&str> = csv.lines().collect();

        assert_eq!(
            lines[0],
            "name,generic_name,brand_name,dosage,form,prescriber,pharmacy,notes,start_date,end_date"
        );
        assert_eq!(lines.len(), 3); // header + 2 rows
        assert!(lines[1].starts_with("Aspirin,"));
        assert!(lines[2].starts_with("Vitamin D,"));
    }

    #[test]
    fn csv_dose_logs() {
        let logs = vec![
            make_dose_log("Aspirin", DoseStatus::Taken),
            make_dose_log("Vitamin D", DoseStatus::Skipped),
        ];
        let csv = dose_logs_to_csv(&logs).unwrap();
        let lines: Vec<&str> = csv.lines().collect();

        assert_eq!(lines[0], "medication_name,taken_at,status,notes");
        assert_eq!(lines.len(), 3);
        assert!(lines[1].contains("Aspirin"));
        assert!(lines[1].contains("taken"));
        assert!(lines[2].contains("Vitamin D"));
        assert!(lines[2].contains("skipped"));
    }

    #[test]
    fn empty_vault_export() {
        let data = make_export_data(vec![], vec![], vec![]);
        let json = to_json(&data).unwrap();
        let parsed: serde_json::Value = serde_json::from_str(&json).unwrap();

        assert!(parsed["medications"].as_array().unwrap().is_empty());
        assert!(parsed["schedules"].as_array().unwrap().is_empty());
        assert!(parsed["dose_logs"].as_array().unwrap().is_empty());
        assert_eq!(parsed["metadata"]["medication_count"], 0);
    }

    #[test]
    fn csv_escaping() {
        let mut med = make_med("Med, with comma");
        med.notes = Some("has \"quotes\" and,commas".to_string());

        let csv = medications_to_csv(&[med]).unwrap();
        let lines: Vec<&str> = csv.lines().collect();
        let row = lines[1];

        // Name should be wrapped in double quotes
        assert!(row.starts_with("\"Med, with comma\""));
        // Notes field should have doubled quotes inside double-quote wrapper
        assert!(row.contains("\"has \"\"quotes\"\" and,commas\""));
    }

    #[test]
    fn csv_escape_fn_passthrough() {
        assert_eq!(csv_escape("simple"), "simple");
        assert_eq!(csv_escape("has,comma"), "\"has,comma\"");
        assert_eq!(csv_escape("has\"quote"), "\"has\"\"quote\"");
        assert_eq!(csv_escape("has\nnewline"), "\"has\nnewline\"");
    }
}
