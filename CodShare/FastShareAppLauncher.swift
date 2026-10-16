#if COD_FAST_SHARE
import UIKit

/// Intentionally isolated compatibility workaround, NOT an Apple-supported
/// Share-extension launch contract. Calls public methods directly, without
/// UIApplication.shared, private selectors, dynamic lookup or source-app
/// inspection. Keeping extension-safe compilation on does not imply approval.
@MainActor
enum FastShareAppLauncher {
    static func open(_ url: URL, from start: UIResponder) async -> Bool {
        var responder: UIResponder? = start
        var visited = Set<ObjectIdentifier>()
        while let candidate = responder,
              visited.insert(ObjectIdentifier(candidate)).inserted, visited.count <= 32 {
            if let application = candidate as? UIApplication {
                return await withCheckedContinuation { continuation in
                    let attempt = FastShareLaunchAttempt(continuation)
                    attempt.timeout = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        guard !Task.isCancelled else { return }
                        CodDiagnosticLog.record("fast share launch timed out")
                        attempt.finish(false)
                    }
                    application.open(url, options: [:]) { accepted in
                        Task { @MainActor in
                            CodDiagnosticLog.record("fast share launch accepted=\(accepted)")
                            attempt.finish(accepted)
                        }
                    }
                }
            }
            responder = candidate.next
        }
        CodDiagnosticLog.record("fast share launch has no application responder")
        return false
    }
}

@MainActor
private final class FastShareLaunchAttempt {
    private var continuation: CheckedContinuation<Bool, Never>?
    var timeout: Task<Void, Never>?

    init(_ continuation: CheckedContinuation<Bool, Never>) { self.continuation = continuation }

    func finish(_ accepted: Bool) {
        guard let continuation else { return }
        self.continuation = nil
        timeout?.cancel()
        timeout = nil
        continuation.resume(returning: accepted)
    }
}
#endif
