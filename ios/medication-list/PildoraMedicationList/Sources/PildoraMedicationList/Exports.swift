// Re-export the shared persistence model types so that consumers of this feature
// module (e.g. the app target) get `Medication`, `InventoryRecord`,
// `MedicationForm`, and `MedicationCategory` via a single
// `import PildoraMedicationList`, and so every file in this module can reference
// them without importing the data layer individually.
//
// Full model unification (issue #48): the feature previously defined its own
// duplicate `Medication` / `InventoryRecord` value types. Those have been removed
// in favor of the production `PildoraDataLayer` records, which are the single
// source of truth for the encrypted, vault-scoped store.
@_exported import PildoraDataLayer

// The local drug index (autocomplete). Re-exported so the app can construct a
// `DrugIndex` without a separate import.
@_exported import PildoraDrugIndex
