import Foundation
import SwiftData
import UserNotifications

@MainActor
final class AppStore: ObservableObject {
    @Published var accountID: String = UserDefaults.standard.string(forKey: "account_id") ?? ""
    @Published var email: String = UserDefaults.standard.string(forKey: "account_email") ?? ""
    @Published var syncStatus = ""
    @Published var busy = false
    @Published var showError: String?
    @Published var dataRevision = 0

    let context: ModelContext
    let api = APIClient()
    var loggedIn: Bool { !accountID.isEmpty && KeychainVault.read("refresh") != nil }
    init(context: ModelContext) { self.context = context }

    private func allRecords() -> [LocalRecord] {
        (try? context.fetch(FetchDescriptor<LocalRecord>())) ?? []
    }
    private func records(_ kind: String) -> [LocalRecord] {
        allRecords().filter { $0.ownerID == accountID && $0.kind == kind && !$0.isDeleted }
    }
    func entries<T: Decodable & HasLocalID>(_ kind: String, as type: T.Type = T.self) -> [T] {
        records(kind).compactMap { row in
            guard var value = try? JSONDecoder.klar.decode(T.self, from: row.payload) else { return nil }
            value.id = row.id
            return value
        }
    }
    var tasks: [TaskEntry] { entries("tasks") }
    var transactions: [TransactionEntry] { entries("transactions") }
    var recurring: [RecurringEntry] { entries("recurring") }
    var budgets: [BudgetEntry] { entries("budgets") }
    var shoppingLists: [ShoppingListEntry] { entries("shopping_lists") }
    var shoppingItems: [ShoppingItemEntry] { entries("shopping_items") }

    func upsert<T: Encodable>(_ kind: String, id: UUID, value: T) {
        do {
            let data = try JSONEncoder.klar.encode(value)
            if let row = allRecords().first(where: { $0.ownerID == accountID && $0.id == id && $0.kind == kind }) {
                row.payload = data; row.dirty = true; row.isDeleted = false; row.updatedAt = .now
            } else {
                context.insert(LocalRecord(id:id, ownerID:accountID, kind:kind, payload:data))
            }
            try context.save(); dataRevision += 1
            Task { await scheduleNotifications() }
        } catch { showError = "Speichern fehlgeschlagen: \(error.localizedDescription)" }
    }
    func remove(_ kind: String, id: UUID) {
        guard let row = allRecords().first(where: { $0.ownerID == accountID && $0.kind == kind && $0.id == id }) else { return }
        if row.serverVersion == 0 { context.delete(row) }
        else { row.isDeleted = true; row.dirty = true; row.updatedAt = .now }
        do { try context.save(); dataRevision += 1 }
        catch { showError = error.localizedDescription }
    }

    func toggle(_ task: TaskEntry) {
        var copy = task
        copy.completed.toggle()
        upsert("tasks", id:task.id, value:copy)
        if copy.completed && task.repeatRule != "nie" {
            let unit: Calendar.Component
            switch task.repeatRule {
            case "taeglich": unit = .day
            case "woechentlich": unit = .weekOfYear
            default: unit = .month
            }
            let next = Calendar.current.date(byAdding: unit, value:1, to:task.dueAt ?? .now)
            var repeated = task
            repeated.id = UUID(); repeated.completed = false; repeated.dueAt = next
            upsert("tasks", id:repeated.id, value:repeated)
        }
    }

    func bootstrap() async {
        guard loggedIn else { return }
        await sync()
    }

    func authorize(email: String, password: String, create: Bool) async {
        busy = true; defer { busy = false }
        do {
            let payload = try JSONEncoder.klar.encode(["email": email, "password": password])
            let values: AuthResponse = try await api.request(create ? "/v1/auth/register":"/v1/auth/login",
                                                              method:"POST",body:payload)
            KeychainVault.save(values.accessToken, for:"access")
            KeychainVault.save(values.refreshToken, for:"refresh")
            let me: MeResponse = try await api.request("/v1/me",accessToken:values.accessToken)
            accountID = me.id; self.email = me.email
            UserDefaults.standard.set(me.id, forKey:"account_id")
            UserDefaults.standard.set(me.email, forKey:"account_email")
            busy = false
            await sync()
        } catch { showError = error.localizedDescription }
    }

    func accessToken() async throws -> String {
        guard let refresh = KeychainVault.read("refresh") else { throw APIError(statusCode:401, description:"Bitte anmelden") }
        if let access = KeychainVault.read("access") { return access }
        let data = try JSONEncoder.klar.encode(["refresh_token": refresh])
        let response: AuthResponse = try await api.request("/v1/auth/refresh",method:"POST",body:data)
        KeychainVault.save(response.refreshToken,for:"refresh")
        KeychainVault.save(response.accessToken,for:"access")
        return response.accessToken
    }

    private func call<Response: Decodable>(_ path:String, method:String="GET", body:Data?=nil,
                                             as type:Response.Type=Response.self) async throws -> Response {
        let value = try await accessToken()
        do { return try await api.request(path,method:method,body:body,accessToken:value) }
        catch let error as APIError where error.statusCode == 401 {
            KeychainVault.remove("access")
            let refreshed = try await accessToken()
            return try await api.request(path,method:method,body:body,accessToken:refreshed)
        }
    }

    func sync() async {
        guard loggedIn && !busy else { return }
        syncStatus = "Synchronisiere …"
        do {
            let dirty = allRecords().filter { $0.ownerID == accountID && $0.dirty }
            for batchStart in stride(from:0,to:dirty.count,by:100) {
                let batch = Array(dirty[batchStart..<min(batchStart+100,dirty.count)])
                let mutations = batch.map {
                    PushMutation(kind:$0.kind,id:$0.id,baseVersion:$0.serverVersion,deleted:$0.isDeleted,
                                 data:DataValue(raw:$0.isDeleted ? Data("{}".utf8) : $0.payload))
                }
                let payload = try JSONEncoder.klar.encode(["mutations":mutations])
                let response: PushResponse = try await call("/v1/sync/push",method:"POST",body:payload)
                for accepted in response.applied {
                    guard let row = batch.first(where: { $0.id == accepted.id && $0.kind == accepted.kind }) else { continue }
                    row.serverVersion = accepted.version
                    row.dirty = false
                }
                try context.save()
            }
            var cursor = UserDefaults.standard.integer(forKey: "sync_cursor_\(accountID)")
            var hasMore = true
            while hasMore {
                let response: PullResponse = try await call("/v1/sync/pull?after=\(cursor)")
                for remote in response.changes {
                    let local = allRecords().first { $0.ownerID == accountID && $0.id == remote.id && $0.kind == remote.kind }
                    if let local {
                        // Never discard local edits after an optimistic concurrency conflict.
                        if !local.dirty {
                            local.payload = remote.data.raw; local.serverVersion = remote.version
                            local.isDeleted = remote.deleted; local.updatedAt = .now
                        }
                    } else {
                        context.insert(LocalRecord(id:remote.id,ownerID:accountID,kind:remote.kind,
                                     payload:remote.data.raw,serverVersion:remote.version,dirty:false,isDeleted:remote.deleted))
                    }
                }
                try context.save()
                cursor = response.nextCursor
                UserDefaults.standard.set(cursor, forKey:"sync_cursor_\(accountID)")
                hasMore = response.hasMore
            }
            dataRevision += 1; syncStatus = "Aktuell"
            await scheduleNotifications()
        } catch {
            syncStatus = "Offline / Konflikt"
            // Retain local changes and expose the actual sync error for repair.
            if let apiError = error as? APIError, apiError.statusCode == 409 {
                showError = "Synchronisationskonflikt. Lokale Änderungen wurden behalten. \(apiError.description)"
            }
        }
    }

    func logout() async {
        if let refresh = KeychainVault.read("refresh") {
            if let data = try? JSONEncoder.klar.encode(["refresh_token":refresh]) {
                let _: [String: String]? = try? await api.request("/v1/auth/logout",method:"POST",body:data)
            }
        }
        KeychainVault.remove("access"); KeychainVault.remove("refresh")
        accountID = ""; email = ""
        UserDefaults.standard.removeObject(forKey:"account_id")
        UserDefaults.standard.removeObject(forKey:"account_email")
        dataRevision += 1
    }

    func deleteAccount() async {
        do {
            struct Empty: Decodable {}
            let _: Empty = try await call("/v1/account",method:"DELETE")
            let owner = accountID
            for row in allRecords().filter({ $0.ownerID == owner }) { context.delete(row) }
            try context.save()
            await logout()
        } catch { showError = error.localizedDescription }
    }

    func scheduleNotifications() async {
        guard UserDefaults.standard.bool(forKey:"notifications_enabled") else { return }
        let center = UNUserNotificationCenter.current()
        let granted = try? await center.requestAuthorization(options:[.alert,.badge,.sound])
        guard granted == true else { return }
        center.removeAllPendingNotificationRequests()
        for task in tasks.filter({ !$0.completed }).prefix(40) {
            guard let due = task.dueAt, due > .now else { continue }
            let content = UNMutableNotificationContent()
            content.title = "Aufgabe fällig"; content.body = task.title
            let comps = Calendar.current.dateComponents([.year,.month,.day,.hour,.minute],from:due)
            try? await center.add(UNNotificationRequest(identifier:"task-\(task.id)",content:content,
                            trigger:UNCalendarNotificationTrigger(dateMatching:comps,repeats:false)))
        }
        for bill in recurring.filter({ $0.active }).prefix(20) {
            guard let due = DateFormatter.klarDay.date(from:bill.nextDue),
                  let reminder = Calendar.current.date(byAdding:.day,value:-bill.reminderDays,to:due), reminder > .now else { continue }
            let content = UNMutableNotificationContent()
            content.title = "Bald fällig: \(bill.title)"; content.body = "\(bill.amountCents.euros) geplant"
            var comps = Calendar.current.dateComponents([.year,.month,.day],from:reminder)
            comps.hour = 9; comps.minute = 0
            try? await center.add(UNNotificationRequest(identifier:"bill-\(bill.id)",content:content,
                            trigger:UNCalendarNotificationTrigger(dateMatching:comps,repeats:false)))
        }
    }
}
