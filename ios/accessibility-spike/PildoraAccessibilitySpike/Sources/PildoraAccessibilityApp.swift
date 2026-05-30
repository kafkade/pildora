import SwiftUI

// MARK: - App Entry Point

@main
struct PildoraAccessibilityApp: App {
    @State private var showAudit = false

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                MedicationListView(medications: SampleData.medications)
                    .toolbar {
                        ToolbarItem(placement: .automatic) {
                            Button {
                                showAudit = true
                            } label: {
                                Label("Audit", systemImage: "checklist")
                            }
                            .accessibilityLabel("Run accessibility audit")
                            .accessibilityHint("Shows programmatic accessibility check results")
                        }
                    }
                    .sheet(isPresented: $showAudit) {
                        AuditResultsView()
                    }
            }
        }
    }
}

// MARK: - Audit Results View

struct AuditResultsView: View {
    @Environment(\.dismiss) private var dismiss
    private let findings = AccessibilityAudit.runAll()

    var body: some View {
        NavigationStack {
            List {
                let passes = findings.filter { $0.severity == .pass }
                let warnings = findings.filter { $0.severity == .warning }
                let failures = findings.filter { $0.severity == .fail }

                Section {
                    HStack {
                        Label("\(passes.count) passed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Spacer()
                        Label("\(warnings.count) warnings", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Spacer()
                        Label("\(failures.count) failed", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .font(.headline)
                } header: {
                    Text("Summary")
                }

                if !failures.isEmpty {
                    Section {
                        ForEach(Array(failures.enumerated()), id: \.offset) { _, finding in
                            findingRow(finding)
                        }
                    } header: {
                        Text("Failures")
                    }
                }

                if !warnings.isEmpty {
                    Section {
                        ForEach(Array(warnings.enumerated()), id: \.offset) { _, finding in
                            findingRow(finding)
                        }
                    } header: {
                        Text("Warnings")
                    }
                }

                Section {
                    ForEach(Array(passes.enumerated()), id: \.offset) { _, finding in
                        findingRow(finding)
                    }
                } header: {
                    Text("Passed")
                }
            }
            .navigationTitle("Accessibility Audit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func findingRow(_ finding: AccessibilityAudit.Finding) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(finding.check)
                .font(.subheadline.weight(.medium))
            Text(finding.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
