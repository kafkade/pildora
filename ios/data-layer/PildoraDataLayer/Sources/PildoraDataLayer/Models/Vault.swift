import Foundation
import GRDB

// MARK: - Vault

/// One vault = one encryption boundary. Each vault is persisted in its own
/// SQLCipher database file (see `VaultDatabaseManager`), so a vault DB normally
/// holds exactly one `Vault` row describing the profile, plus all of that
/// vault's health data referencing it via `vaultId`.
///
/// Vault metadata (name, icon, color) is health-sensitive — a name like
/// "Mom's Heart Meds" leaks a condition — so it only ever lives inside the
/// encrypted database, never in plaintext.
public struct Vault: Codable, Identifiable, FetchableRecord, PersistableRecord, Hashable, Sendable {
    public static let databaseTableName = "vault"

    public var id: String
    public var name: String
    public var icon: String?
    public var color: String?
    public var profileType: VaultProfileType
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        name: String,
        icon: String? = nil,
        color: String? = nil,
        profileType: VaultProfileType = .personal,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.color = color
        self.profileType = profileType
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let name = Column(CodingKeys.name)
        public static let profileType = Column(CodingKeys.profileType)
        public static let createdAt = Column(CodingKeys.createdAt)
        public static let updatedAt = Column(CodingKeys.updatedAt)
    }

    /// Associations use the vault's primary key as the parent of all health data.
    public static let medications = hasMany(Medication.self)
}
