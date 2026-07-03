import PildoraDrugIndexLoader
import PildoraMedicationList
import PildoraOnboarding
import SwiftUI

/// App root: on first run it presents the onboarding flow (master password +
/// recovery key), otherwise it opens the existing encrypted vault and hosts the
/// medication UI. Shows a loading state while the vault opens and a recoverable
/// error state if bootstrap fails.
struct ContentView: View {
    @State private var phase: Phase = .loading

    enum Phase {
        case loading
        case onboarding(OnboardingFlowModel)
        case ready(MedicationStore, TieredDrugIndexProvider)
        case failed(String)
    }

    var body: some View {
        switch phase {
        case .loading:
            ProgressView("Preparing your vault…")
                .task { await bootstrap() }
        case .onboarding(let model):
            OnboardingFlowView(model: model)
        case .ready(let store, let drugIndex):
            MainTabView(store: store, drugIndex: drugIndex)
        case .failed(let message):
            failureView(message)
        }
    }

    private func failureView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Couldn't open your vault", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") {
                phase = .loading
            }
        }
    }

    @MainActor
    private func bootstrap() async {
        guard case .loading = phase else { return }
        do {
            // UI tests bypass onboarding and run against a clean in-memory vault.
            if AppBootstrap.isUITesting {
                activate(try AppBootstrap.makeUITestingBootstrap())
                return
            }

            if AppBootstrap.needsOnboarding() {
                let model = AppBootstrap.makeOnboardingModel { bootstrapped in
                    activate(bootstrapped)
                }
                phase = .onboarding(model)
                return
            }

            activate(try AppBootstrap.openVault())
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    /// Move to the ready state and kick off the one-time full-index download.
    @MainActor
    private func activate(_ bootstrapped: AppBootstrap.Bootstrapped) {
        // Non-blocking: kick off the one-time full-index download. Any failure is
        // reflected in the provider's state and leaves the bundled core index
        // serving autocomplete.
        bootstrapped.drugIndex.startFullIndexDownloadIfNeeded()
        phase = .ready(bootstrapped.store, bootstrapped.drugIndex)
    }
}

/// Two-tab shell: the medication tracker and the developer diagnostics screen,
/// with a drug-index update banner across the top.
struct MainTabView: View {
    let store: MedicationStore
    @ObservedObject var drugIndex: TieredDrugIndexProvider

    var body: some View {
        VStack(spacing: 0) {
            DrugIndexStatusView(provider: drugIndex)
            TabView {
                MedicationListView(store: store)
                    .tabItem { Label("Medications", systemImage: "pills") }

                DiagnosticsView(drugIndex: drugIndex)
                    .tabItem { Label("Diagnostics", systemImage: "lock.shield") }
            }
        }
    }
}

#Preview {
    MainTabView(store: .sample(), drugIndex: try! PreviewSupport.makeDrugIndexProvider())
}
