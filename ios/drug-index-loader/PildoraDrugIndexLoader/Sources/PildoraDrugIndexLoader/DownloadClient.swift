import Foundation

// MARK: - IndexDownloadClient

/// Network seam for the tiered loader. Abstracts URLSession so tests can drive
/// success, failure, and retry behaviour deterministically with no real I/O.
///
/// Zero-knowledge note: these methods only ever fetch **public** reference-data
/// URLs (the manifest and the compressed index). No user data, query text, or
/// health information is ever sent — the only observable fact is that the device
/// downloaded the public drug database. See the package README for the full
/// metadata-exposure analysis.
public protocol IndexDownloadClient: Sendable {
    /// Fetch a small resource fully into memory (used for `manifest.json`).
    func fetchData(from url: URL) async throws -> Data

    /// Download a (possibly large) resource to a temporary file, reporting
    /// fractional progress in `0...1`. The returned URL is owned by the caller,
    /// which must move or delete it.
    func downloadToFile(
        from url: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL
}

// MARK: - URLSessionDownloadClient

/// Production `IndexDownloadClient` backed by `URLSession`.
///
/// Large downloads use a `URLSessionDownloadTask` (streamed to disk, never fully
/// buffered in memory) with byte-accurate progress. On a recoverable failure it
/// retries using URLSession **resume data** so an interrupted transfer continues
/// rather than restarting.
public final class URLSessionDownloadClient: NSObject, IndexDownloadClient, @unchecked Sendable {

    private let session: URLSession
    /// How many times a single download is retried using resume data before the
    /// error is surfaced (the higher-level downloader adds its own outer retries).
    private let resumeRetries: Int

    public init(configuration: URLSessionConfiguration = .ephemeral, resumeRetries: Int = 2) {
        // A short, cache-free ephemeral config keeps no cookies and sends no
        // credentials — the request is an anonymous GET of a public asset.
        self.session = URLSession(configuration: configuration)
        self.resumeRetries = resumeRetries
        super.init()
    }

    public func fetchData(from url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        try Self.validate(response)
        return data
    }

    public func downloadToFile(
        from url: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        var resumeData: Data?
        var lastError: Error?

        for attempt in 0...resumeRetries {
            do {
                return try await runDownload(url: url, resumeData: resumeData, onProgress: onProgress)
            } catch let error as ResumableError {
                lastError = error.underlying
                resumeData = error.resumeData  // continue where we left off
                if attempt == resumeRetries { break }
            } catch {
                lastError = error
                break
            }
        }
        throw DrugIndexLoaderError.downloadFailed(
            lastError.map { String(describing: $0) } ?? "unknown"
        )
    }

    // MARK: Private

    /// Wraps an error together with any resume data URLSession handed back.
    private struct ResumableError: Error {
        let underlying: Error
        let resumeData: Data?
    }

    private func runDownload(
        url: URL,
        resumeData: Data?,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let observer = ProgressObserver(onProgress)
        // The completion handler already relocates the file to a stable temp URL
        // that outlives URLSession's auto-deleted location, so just validate and
        // return it here.
        let (fileURL, response) = try await downloadTask(
            url: url, resumeData: resumeData, observer: observer
        )
        do {
            try Self.validate(response)
        } catch {
            try? FileManager.default.removeItem(at: fileURL)
            throw ResumableError(underlying: error, resumeData: nil)
        }
        return fileURL
    }

    private func downloadTask(
        url: URL,
        resumeData: Data?,
        observer: ProgressObserver
    ) async throws -> (URL, URLResponse?) {
        try await withCheckedThrowingContinuation { continuation in
            let handler: @Sendable (URL?, URLResponse?, Error?) -> Void = { location, response, error in
                if let location {
                    // The temp file is deleted when this handler returns, so copy
                    // it out synchronously here.
                    let copy = FileManager.default.temporaryDirectory
                        .appendingPathComponent("pildora-dl-\(UUID().uuidString).gz")
                    do {
                        try FileManager.default.moveItem(at: location, to: copy)
                        continuation.resume(returning: (copy, response))
                    } catch {
                        continuation.resume(throwing: ResumableError(underlying: error, resumeData: nil))
                    }
                    return
                }
                let nsError = error as NSError?
                let resume = nsError?.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
                continuation.resume(
                    throwing: ResumableError(
                        underlying: error ?? DrugIndexLoaderError.downloadFailed("no file, no error"),
                        resumeData: resume
                    )
                )
            }

            let task: URLSessionDownloadTask
            if let resumeData {
                task = session.downloadTask(withResumeData: resumeData, completionHandler: handler)
            } else {
                task = session.downloadTask(with: url, completionHandler: handler)
            }
            observer.observe(task)
            task.resume()
        }
    }

    private static func validate(_ response: URLResponse?) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw DrugIndexLoaderError.downloadFailed("HTTP \(http.statusCode)")
        }
    }
}

// MARK: - ProgressObserver

/// Bridges `URLSessionTask.progress` (KVO) to a progress callback and keeps the
/// observation alive for the task's lifetime.
private final class ProgressObserver: @unchecked Sendable {
    private let onProgress: @Sendable (Double) -> Void
    private var observation: NSKeyValueObservation?

    init(_ onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func observe(_ task: URLSessionTask) {
        observation = task.progress.observe(\.fractionCompleted, options: [.initial, .new]) { [onProgress] progress, _ in
            onProgress(progress.fractionCompleted)
        }
    }
}
