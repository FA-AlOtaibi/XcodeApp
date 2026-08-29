import Foundation
import UIKit

final class HammelAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        BackgroundDownloadBroker.shared.backgroundCompletionHandler = completionHandler
        _ = BackgroundDownloadBroker.shared.session
    }
}

final class BackgroundDownloadBroker: NSObject, URLSessionDownloadDelegate, URLSessionTaskDelegate {
    static let shared = BackgroundDownloadBroker()

    var backgroundCompletionHandler: (() -> Void)?

    private var continuations: [Int: CheckedContinuation<URL, Error>] = [:]
    private var progressBlocks: [Int: (Double) -> Void] = [:]
    private let lock = NSLock()

    lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "com.fahad.Hammel.backgroundDownloads")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.waitsForConnectivity = true
        config.httpMaximumConnectionsPerHost = 8
        config.timeoutIntervalForRequest = 180
        config.timeoutIntervalForResource = 60 * 60
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    func download(_ request: URLRequest, progress: @escaping (Double) -> Void) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let task = session.downloadTask(with: request)
            lock.lock()
            continuations[task.taskIdentifier] = continuation
            progressBlocks[task.taskIdentifier] = progress
            lock.unlock()
            task.resume()
        }
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = min(1, max(0, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
        lock.lock(); let block = progressBlocks[downloadTask.taskIdentifier]; lock.unlock()
        block?(fraction)
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        let suggested = downloadTask.response?.suggestedFilename ?? "download.part"
        let ext = (suggested as NSString).pathExtension.isEmpty ? "part" : (suggested as NSString).pathExtension
        let dst = FileManager.default.temporaryDirectory.appendingPathComponent("bg-\(UUID().uuidString).\(ext)")
        do {
            try? FileManager.default.removeItem(at: dst)
            try FileManager.default.moveItem(at: location, to: dst)
            finish(taskID: downloadTask.taskIdentifier, result: .success(dst))
        } catch {
            finish(taskID: downloadTask.taskIdentifier, result: .failure(error))
        }
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        if let error { finish(taskID: task.taskIdentifier, result: .failure(error)) }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            self.backgroundCompletionHandler?()
            self.backgroundCompletionHandler = nil
        }
    }

    private func finish(taskID: Int, result: Result<URL, Error>) {
        lock.lock()
        let continuation = continuations.removeValue(forKey: taskID)
        progressBlocks.removeValue(forKey: taskID)
        lock.unlock()
        guard let continuation else { return }
        switch result {
        case .success(let url): continuation.resume(returning: url)
        case .failure(let error): continuation.resume(throwing: error)
        }
    }
}

@MainActor
func beginHammelBackgroundTask(_ name: String) -> UIBackgroundTaskIdentifier {
    var identifier: UIBackgroundTaskIdentifier = .invalid
    identifier = UIApplication.shared.beginBackgroundTask(withName: name) {
        if identifier != .invalid {
            UIApplication.shared.endBackgroundTask(identifier)
            identifier = .invalid
        }
    }
    return identifier
}

@MainActor
func endHammelBackgroundTask(_ identifier: UIBackgroundTaskIdentifier) {
    guard identifier != .invalid else { return }
    UIApplication.shared.endBackgroundTask(identifier)
}
