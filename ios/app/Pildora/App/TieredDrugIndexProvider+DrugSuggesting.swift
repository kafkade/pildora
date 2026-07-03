import PildoraDrugIndexLoader
import PildoraMedicationList

/// Bridges the tiered loader's provider to the medication editor's autocomplete
/// seam. `TieredDrugIndexProvider` already exposes a matching
/// `suggestions(matching:limit:)`, so this conformance is a thin declaration —
/// kept in the app target so the loader package stays free of a medication-list
/// dependency.
extension TieredDrugIndexProvider: DrugSuggesting {}
