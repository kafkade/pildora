import PildoraMedicationList
import SwiftUI

/// App root: bootstraps the encrypted vault + drug index, then hosts the
/// medication UI. Shows a loading state while the vault opens and a recoverable
/// error state if bootstrap fails.
struct ContentView: View {
    @State private var phase: Phase = .loading

    enum Phase {
        case loading
        case ready(MedicationStore)
        case failed(String)
    }

    var body: some View {
        switch phase {
        case .loading:
            ProgressView("Preparing your vault…")
                .task { await bootstrap() }
        case .ready(let store):
            MainTabView(store: store)
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
            phase = .ready(try AppBootstrap.makeStore())
        } catch {
            phase = .failed(String(describing: error))
        }
    }
}

/// Two-tab shell: the medication tracker and the developer diagnostics screen.
struct MainTabView: View {
    let store: MedicationStore

    var body: some View {
        TabView {
            MedicationListView(store: store)
                .tabItem { Label("Medications", systemImage: "pills") }

            DiagnosticsView()
                .tabItem { Label("Diagnostics", systemImage: "lock.shield") }
        }
    }
}

#Preview {
    MainTabView(store: .sample())
}
