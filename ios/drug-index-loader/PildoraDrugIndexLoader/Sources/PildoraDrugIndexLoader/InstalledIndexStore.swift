import Foundation

// MARK: - InstalledIndexStore

/// Owns the on-disk location of the **downloaded full index** and its version
/// marker, and installs new indexes atomically.
///
/// This is public, plaintext reference data — it lives in Application Support,
/// entirely separate from the encrypted vault database (per the Data Boundary
/// Rule). It is intentionally excluded from iCloud/iTunes backup.
public struct InstalledIndexStore: Sendable {

    /// Directory holding the installed index + version marker.
    public let directory: URL

    private var indexURL: URL { directory.appendingPathComponent("full-index.db", isDirectory: false) }
    private var versionURL: URL { directory.appendingPathComponent("full-index.version", isDirectory: false) }

    /// Create a store rooted at `directory`, or at the default Application
    /// Support location (`…/PildoraDrugIndex/`) when `nil`.
    public init(directory: URL? = nil) throws {
        if let directory {
            self.directory = directory
        } else {
            self.directory = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("PildoraDrugIndex", isDirectory: true)
        }
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    /// Filesystem path of the installed full index (may not exist yet).
    public var installedFullIndexURL: URL { indexURL }

    /// Whether a full index has been installed.
    public func hasInstalledFullIndex() -> Bool {
        FileManager.default.fileExists(atPath: indexURL.path)
    }

    /// The `index_version` of the installed full index, if any. Returns `nil`
    /// when no index is installed or the marker is missing/unreadable — callers
    /// should then treat any manifest version as newer.
    public func installedVersion() -> String? {
        guard hasInstalledFullIndex(),
              let raw = try? String(contentsOf: versionURL, encoding: .utf8)
        else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Atomically install a validated index from a temporary file, recording its
    /// version. The move replaces any previously installed index in one step, so
    /// a crash mid-install can never leave a half-written index behind.
    public func install(databaseAt tempURL: URL, version: String) throws {
        let fm = FileManager.default

        // Stage inside the destination directory so the final replace is a same
        // volume atomic move.
        let staged = directory.appendingPathComponent("full-index.staging.db", isDirectory: false)
        try? fm.removeItem(at: staged)
        try fm.moveItem(at: tempURL, to: staged)
        excludeFromBackup(staged)

        if fm.fileExists(atPath: indexURL.path) {
            _ = try fm.replaceItemAt(indexURL, withItemAt: staged)
        } else {
            try fm.moveItem(at: staged, to: indexURL)
        }
        excludeFromBackup(indexURL)

        try version.write(to: versionURL, atomically: true, encoding: .utf8)
    }

    /// Remove the installed index + version marker (e.g. to force a re-download).
    public func removeInstalled() throws {
        let fm = FileManager.default
        for url in [indexURL, versionURL] where fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
    }

    private func excludeFromBackup(_ url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }
}
