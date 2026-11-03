import Foundation

/// A cancelled/older load must never open its result over a newer selection.
struct MediaImportState {
  private(set) var requestID: UUID?
  private(set) var failure: String?
  var isLoading: Bool { requestID != nil }

  mutating func begin() -> UUID {
    let id = UUID()
    requestID = id
    failure = nil
    return id
  }

  func accepts(_ id: UUID) -> Bool { requestID == id }

  mutating func finish(_ id: UUID) {
    if accepts(id) { requestID = nil }
  }

  mutating func fail(_ error: Error, for id: UUID) {
    guard accepts(id) else { return }
    failure = ImportRecovery.message(for: error)
  }

  mutating func report(_ error: Error) { failure = ImportRecovery.message(for: error) }
  mutating func dismissFailure() { failure = nil }
  mutating func cancel() {
    requestID = nil
    failure = nil
  }
}

enum ImportRecovery {
  /// Closing a picker or cancelling a download isn't a failed import.
  static func message(for error: Error) -> String? {
    if error is CancellationError { return nil }
    let value = error as NSError
    if (value.domain == NSCocoaErrorDomain && value.code == NSUserCancelledError)
      || (value.domain == NSURLErrorDomain && value.code == NSURLErrorCancelled)
    {
      return nil
    }
    if value.domain == NSCocoaErrorDomain {
      switch value.code {
      case NSFileReadNoPermissionError:
        return
          "Cod couldn't access this file. Choose it again in Files, or save a local copy and try that."
      case NSFileNoSuchFileError, NSFileReadNoSuchFileError:
        return "This file is no longer available. Choose it again from its current location."
      default: break
      }
    }
    if value.domain == NSURLErrorDomain {
      return
        "The download didn't finish. Open the item in Photos or Files, let it download, then choose it again."
    }
    return error.localizedDescription
  }
}
