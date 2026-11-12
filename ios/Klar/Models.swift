import Foundation
import SwiftData

@Model
final class LocalRecord {
    @Attribute(.unique) var id: UUID
    var ownerID: String
    var kind: String
    var payload: Data
    var serverVersion: Int
    var dirty: Bool
    var isDeleted: Bool
    var updatedAt: Date

    init(id: UUID, ownerID: String, kind: String, payload: Data, serverVersion: Int = 0,
         dirty: Bool = true, isDeleted: Bool = false, updatedAt: Date = .now) {
        self.id = id
        self.ownerID = ownerID
        self.kind = kind
        self.payload = payload
        self.serverVersion = serverVersion
        self.dirty = dirty
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
    }
}

protocol HasLocalID { var id: UUID { get set } }

struct TaskEntry: Codable, Identifiable, HasLocalID {
    var id: UUID = UUID()
    var title: String
    var completed: Bool = false
    var dueAt: Date? = nil
    var priority: String = "mittel"
    var project: String = ""
    var notes: String = ""
    var repeatRule: String = "nie"

    enum CodingKeys: String, CodingKey {
        case title, completed, priority, project, notes
        case dueAt = "due_at", repeatRule = "repeat"
    }
}

struct TransactionEntry: Codable, Identifiable, HasLocalID {
    var id: UUID = UUID()
    var title: String
    var amountCents: Int
    var category: String
    var bookedAt: Date = .now
    var merchant: String = ""
    var notes: String = ""

    enum CodingKeys: String, CodingKey {
        case title, category, merchant, notes
        case amountCents = "amount_cents", bookedAt = "booked_at"
    }
}

struct RecurringEntry: Codable, Identifiable, HasLocalID {
    var id: UUID = UUID()
    var title: String
    var amountCents: Int
    var category: String
    var kind: String = "fixkosten"
    var cadence: String = "monatlich"
    var nextDue: String
    var reminderDays: Int = 3
    var active: Bool = true

    enum CodingKeys: String, CodingKey {
        case title, category, kind, cadence, active
        case amountCents = "amount_cents", nextDue = "next_due", reminderDays = "reminder_days"
    }
}

struct BudgetEntry: Codable, Identifiable, HasLocalID {
    var id: UUID = UUID()
    var category: String = "Gesamt"
    var monthlyLimitCents: Int = 200_000
    enum CodingKeys: String, CodingKey { case category; case monthlyLimitCents = "monthly_limit_cents" }
}

struct ShoppingListEntry: Codable, Identifiable, HasLocalID {
    var id: UUID = UUID()
    var name: String
    var archived: Bool = false
    enum CodingKeys: String, CodingKey { case name, archived }
}

struct ShoppingItemEntry: Codable, Identifiable, HasLocalID {
    var id: UUID = UUID()
    var listID: UUID
    var name: String
    var quantity: Double = 1
    var unit: String = "Stk"
    var unitPriceCents: Int = 0
    var checked: Bool = false
    enum CodingKeys: String, CodingKey {
        case name, quantity, unit, checked
        case listID = "list_id", unitPriceCents = "unit_price_cents"
    }
    var totalCents: Int { NSDecimalNumber(decimal: (Decimal(unitPriceCents) * Decimal(quantity)).rounded(0)).intValue }
}

extension Decimal {
    func rounded(_ scale: Int) -> Decimal {
        var original = self
        var result = Decimal()
        NSDecimalRound(&result, &original, scale, .plain)
        return result
    }
}

struct ProfileEntry: Codable, Identifiable, HasLocalID {
    var id: UUID = UUID()
    var displayName: String = ""
    var defaultCurrency: String = "EUR"
    enum CodingKeys: String, CodingKey {
        case displayName = "display_name", defaultCurrency = "default_currency"
    }
}

struct RemoteRecord: Codable {
    let kind: String
    let id: UUID
    let version: Int
    let deleted: Bool
    let data: DataValue
}

// Preserves arbitrary validated API JSON without requiring a type-erased Encodable.
struct DataValue: Codable {
    let raw: Data
    init(raw: Data) { self.raw = raw }
    init(from decoder: Decoder) throws {
        let value = try JSONTree(from: decoder)
        raw = try JSONEncoder().encode(value)
    }
    func encode(to encoder: Encoder) throws {
        try JSONDecoder().decode(JSONTree.self, from: raw).encode(to: encoder)
    }
}

indirect enum JSONTree: Codable {
    case object([String: JSONTree]), array([JSONTree]), text(String), integer(Int), number(Double), bool(Bool), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let value = try? c.decode(Bool.self) { self = .bool(value) }
        else if let value = try? c.decode(String.self) { self = .text(value) }
        else if let value = try? c.decode(Int.self) { self = .integer(value) }
        else if let value = try? c.decode(Double.self) { self = .number(value) }
        else if let value = try? c.decode([JSONTree].self) { self = .array(value) }
        else { self = .object(try c.decode([String: JSONTree].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .text(let v): try c.encode(v)
        case .integer(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
}

struct PushMutation: Encodable {
    let kind: String
    let id: UUID
    let baseVersion: Int
    let deleted: Bool
    let data: DataValue
    enum CodingKeys: String, CodingKey {
        case kind, id, deleted, data
        case baseVersion = "base_version"
    }
}

struct PushResponse: Decodable { let applied: [RemoteRecord] }
struct PullChange: Decodable {
    let seq: Int
    let kind: String
    let id: UUID
    let version: Int
    let deleted: Bool
    let data: DataValue
}
struct PullResponse: Decodable {
    let changes: [PullChange]
    let nextCursor: Int
    let hasMore: Bool
    enum CodingKeys: String, CodingKey {
        case changes
        case nextCursor = "next_cursor", hasMore = "has_more"
    }
}
struct AuthResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token", refreshToken = "refresh_token", expiresIn = "expires_in"
    }
}
struct MeResponse: Decodable { let id: String; let email: String }

extension DateFormatter {
    static let klarDay: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

extension Int {
    var euros: String {
        (Decimal(self) / 100).formatted(.currency(code: "EUR").locale(Locale(identifier: "de_AT")))
    }
}

extension String {
    var cents: Int? {
        let stripped = replacingOccurrences(of: "€", with: "").replacingOccurrences(of: " ", with: "")
        let normal = stripped.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        guard let decimal = Decimal(string: normal, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        let scaled = (decimal * 100).rounded(0)
        return NSDecimalNumber(decimal: scaled).intValue
    }
}
