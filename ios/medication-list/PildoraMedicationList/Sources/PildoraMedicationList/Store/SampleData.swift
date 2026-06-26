import Foundation

// MARK: - Sample Data

/// Seeded in-memory data backing the feature while the real persistence layer
/// (#44/#48) and drug index (ETL output) are still in progress.
///
/// Chosen to exercise edge cases: prescriptions, OTC, supplements and vitamins;
/// a very long name (Dynamic Type wrapping); critical and low inventory; and a
/// medication without reference data.
public enum SampleData {

    public static let vaultId = "vault-default"

    /// Drug reference entries keyed by their `id`. Public, plaintext data.
    public static func drugReferences(now: Date = Date()) -> [DrugReference] {
        let cal = Calendar.current
        let fdaDate = cal.date(byAdding: .day, value: -45, to: now) ?? now
        let rxnormDate = cal.date(byAdding: .day, value: -60, to: now) ?? now
        return [
            DrugReference(
                id: "ref-levothyroxine",
                drugClass: "Thyroid hormone (levothyroxine sodium)",
                commonSideEffects: ["Headache", "Insomnia", "Palpitations", "Weight changes"],
                source: "openFDA",
                sourceDate: fdaDate
            ),
            DrugReference(
                id: "ref-metformin",
                drugClass: "Biguanide (antidiabetic)",
                commonSideEffects: ["Nausea", "Diarrhea", "Abdominal discomfort", "Metallic taste"],
                source: "openFDA",
                sourceDate: fdaDate
            ),
            DrugReference(
                id: "ref-vitamin-d3",
                drugClass: "Fat-soluble vitamin (cholecalciferol)",
                commonSideEffects: ["Generally well tolerated at recommended intake"],
                source: "RxNorm",
                sourceDate: rxnormDate
            ),
            DrugReference(
                id: "ref-gabapentin",
                drugClass: "Anticonvulsant / nerve pain (GABA analog)",
                commonSideEffects: ["Drowsiness", "Dizziness", "Peripheral edema", "Fatigue"],
                source: "openFDA",
                sourceDate: fdaDate
            ),
        ]
    }

    public static let medications: [Medication] = [
        Medication(
            id: "med-1",
            vaultId: vaultId,
            name: "Levothyroxine",
            genericName: nil,
            dosage: "88 mcg",
            form: .tablet,
            category: .prescription,
            frequency: "Once daily, morning on empty stomach",
            prescriber: "Dr. Chen",
            rxnormId: "10582",
            drugReferenceId: "ref-levothyroxine"
        ),
        Medication(
            id: "med-2",
            vaultId: vaultId,
            name: "Metformin",
            genericName: "metformin hydrochloride",
            dosage: "500 mg",
            form: .tablet,
            category: .prescription,
            frequency: "Twice daily with meals",
            prescriber: "Dr. Patel",
            rxnormId: "6809",
            drugReferenceId: "ref-metformin"
        ),
        Medication(
            id: "med-3",
            vaultId: vaultId,
            name: "Cholecalciferol (Vitamin D3)",
            genericName: "cholecalciferol",
            dosage: "5,000 IU",
            form: .capsule,
            category: .vitamin,
            frequency: "Once daily",
            drugReferenceId: "ref-vitamin-d3"
        ),
        Medication(
            id: "med-4",
            vaultId: vaultId,
            name: "Magnesium Glycinate",
            genericName: nil,
            dosage: "400 mg",
            form: .capsule,
            category: .supplement,
            frequency: "Once daily at bedtime"
        ),
        Medication(
            id: "med-5",
            vaultId: vaultId,
            name: "Gabapentin",
            genericName: nil,
            dosage: "300 mg",
            form: .capsule,
            category: .prescription,
            frequency: "Three times daily",
            prescriber: "Dr. Rivera",
            rxnormId: "25480",
            drugReferenceId: "ref-gabapentin"
        ),
        Medication(
            id: "med-6",
            vaultId: vaultId,
            name: "Ibuprofen",
            genericName: nil,
            dosage: "200 mg",
            form: .tablet,
            category: .overTheCounter,
            frequency: "As needed for pain"
        ),
    ]

    public static func inventory(now: Date = Date()) -> [InventoryRecord] {
        let cal = Calendar.current
        return [
            InventoryRecord(medicationId: "med-1", currentCount: 22, refillThreshold: 7,
                            lastRefillDate: cal.date(byAdding: .day, value: -8, to: now)),
            InventoryRecord(medicationId: "med-2", currentCount: 45, refillThreshold: 10,
                            lastRefillDate: cal.date(byAdding: .day, value: -2, to: now)),
            InventoryRecord(medicationId: "med-3", currentCount: 90, refillThreshold: 14),
            // Low + critical: drives the low-stock alert + refill reminder paths.
            InventoryRecord(medicationId: "med-4", currentCount: 3, refillThreshold: 7),
            InventoryRecord(medicationId: "med-5", currentCount: 15, refillThreshold: 9),
            InventoryRecord(medicationId: "med-6", currentCount: 24, refillThreshold: 5),
        ]
    }
}
