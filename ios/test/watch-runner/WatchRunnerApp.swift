import SwiftUI
import Darwin

@main
struct WatchRunnerApp: App {
    var body: some Scene {
        WindowGroup {
            RunnerView()
        }
    }
}

private struct RunnerView: View {
    @State private var hasStarted = false
    @State private var status = "Preparing Perl tests..."

    var body: some View {
        Text(status)
            .font(.caption2)
            .task {
                guard !hasStarted else { return }
                hasStarted = true
                status = "Running Perl tests..."
                let result = await Task.detached(priority: .userInitiated) {
                    RunWatchPerlTests()
                }.value
                status = "Finished: \(result)"
                exit(result == 0 ? EXIT_SUCCESS : EXIT_FAILURE)
            }
    }
}
