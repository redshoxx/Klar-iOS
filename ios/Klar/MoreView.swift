import SwiftUI
import UniformTypeIdentifiers

struct MoreView:View {
    @EnvironmentObject private var store:AppStore
    @State private var showCalendar=false
    @State private var showSettings=false
    @State private var showRecurring=false

    var body:some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:18) {
                    ScreenTitle(title:"Mehr",subtitle:"Planung und persönliche Einstellungen")
                    KlarCard {
                        NavigationLink { CalendarView() } label: { row("Kalender",symbol:"calendar",subtitle:"Aufgaben, Termine und Zahlungen") }
                        Divider()
                        NavigationLink { SettingsView() } label: { row("Einstellungen",symbol:"gearshape",subtitle:"Sicherheit, Design, Synchronisation") }
                        Divider()
                        NavigationLink { RecurringOverview() } label: { row("Fixkosten & Abos",symbol:"repeat",subtitle:"Regelmäßige Zahlungen") }
                    }
                    KlarCard {
                        HStack {
                            Image(systemName:"checkmark.shield.fill").foregroundStyle(Color.klarGreen)
                            VStack(alignment:.leading,spacing:5) {
                                Text("Deine Daten bleiben unter deiner Kontrolle").font(.subheadline.weight(.semibold))
                                Text("Offline verfügbar, verschlüsselte Übertragung zum eigenen VPS und Geräte-Sperre.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }.padding(17)
            }.klarScreen()
        }
    }
    private func row(_ title:String,symbol:String,subtitle:String)->some View {
        HStack(spacing:15) {
            Image(systemName:symbol).font(.title3).frame(width:30).foregroundStyle(Color.klarGreen)
            VStack(alignment:.leading,spacing:4) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName:"chevron.right").font(.caption).foregroundStyle(.tertiary)
        }.foregroundStyle(.primary).padding(.vertical,10)
    }
}

struct CalendarView:View {
    @EnvironmentObject private var store:AppStore
    @State private var selected:Date = .now
    private var tasks:[TaskEntry] {
        store.tasks.filter{ task in task.dueAt.map{Calendar.current.isDate($0,inSameDayAs:selected)} ?? false }
    }
    private var bills:[RecurringEntry] {
        store.recurring.filter { row in
            row.active && DateFormatter.klarDay.date(from:row.nextDue).map { Calendar.current.isDate($0,inSameDayAs:selected) } == true
        }
    }
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                ScreenTitle(title:"Kalender",subtitle:"Deine Planung auf einen Blick")
                DatePicker("Tag wählen",selection:$selected,displayedComponents:.date)
                    .datePickerStyle(.graphical)
                    .tint(.klarGreen)
                    .padding(8)
                    .background(Color(uiColor:.secondarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:20))
                SectionLabel(title:selected.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                KlarCard {
                    if tasks.isEmpty && bills.isEmpty {
                        EmptyHint(symbol:"calendar.badge.checkmark",title:"Keine Einträge",message:"Für diesen Tag sind keine Aufgaben oder Zahlungen geplant.")
                    } else {
                        ForEach(tasks) { task in TaskRow(task:task) { store.toggle(task) } }
                        ForEach(bills) { bill in RecurringRow(recurring:bill) }
                    }
                }
            }.padding(17)
        }
        .navigationTitle("Kalender")
        .navigationBarTitleDisplayMode(.inline)
        .klarScreen()
    }
}

struct RecurringOverview:View {
    @EnvironmentObject private var store:AppStore
    @State private var add=false
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                ScreenTitle(title:"Fixkosten & Abos")
                KlarCard {
                    Text("Monatlich geplant").font(.subheadline).foregroundStyle(.secondary)
                    Text(store.recurring.filter{$0.active}.reduce(0){$0+monthlyEquivalent($1)}.euros)
                        .font(.system(size:30,weight:.bold,design:.rounded))
                }
                KlarCard {
                    if store.recurring.isEmpty { EmptyHint(symbol:"repeat",title:"Noch keine Zahlungen",message:"Lege eine Fixkostenposition oder ein Abo an.") }
                    else { ForEach(store.recurring.sorted{$0.nextDue < $1.nextDue}) { bill in NavigationLink {RecurringEditor(existing:bill)} label: {RecurringRow(recurring:bill)} } }
                }
                PrimaryButton(title:"Zahlung hinzufügen",symbol:"plus") {add=true}
            }.padding(17)
        }.navigationTitle("Fixkosten").navigationBarTitleDisplayMode(.inline).klarScreen()
            .sheet(isPresented:$add) { NavigationStack {RecurringEditor()} }
    }
}

struct SettingsView:View {
    @EnvironmentObject private var store:AppStore
    @AppStorage("api_base_url") private var serverURL="https://api.152.53.206.242.sslip.io"
    @AppStorage("app_lock") private var appLock=false
    @AppStorage("notifications_enabled") private var notifications=false
    @AppStorage("appearance") private var appearance="system"
    @State private var confirmDelete=false
    @State private var exportURL:URL?
    var body:some View {
        Form {
            Section("Konto") {
                LabeledContent("E-Mail",value:store.email)
                LabeledContent("Synchronisation",value:store.syncStatus)
                Button("Jetzt synchronisieren") { Task{await store.sync()} }
            }
            Section("Eigener VPS") {
                TextField("API-Adresse (HTTPS)",text:$serverURL)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                Text("Die App verwendet ausschließlich diese HTTPS-Adresse für dein Konto.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Sicherheit & Erinnerungen") {
                Toggle("Face ID / iPhone-Code",isOn:$appLock).tint(.klarGreen)
                Toggle("Benachrichtigungen",isOn:$notifications).tint(.klarGreen)
                    .onChange(of:notifications) { _,_ in Task { await store.scheduleNotifications() } }
            }
            Section("Darstellung") {
                Picker("Design",selection:$appearance) {
                    Text("System").tag("system")
                    Text("Hell").tag("light")
                    Text("Dunkel").tag("dark")
                }
            }
            Section("Daten") {
                Button("Finanzen als CSV exportieren") { exportCSV() }
                if let exportURL {
                    ShareLink(item:exportURL) { Label("Export teilen",systemImage:"square.and.arrow.up") }
                }
                Button("Abmelden") { Task { await store.logout() } }
                Button("Konto und Serverdaten löschen",role:.destructive) {confirmDelete=true}
            }
            Section { Text("Klar. 1.0.0 · Für iPhone 12 · Offline-First").font(.caption).foregroundStyle(.secondary) }
        }
        .navigationTitle("Einstellungen").navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Konto unwiderruflich löschen?",isPresented:$confirmDelete,titleVisibility:.visible) {
            Button("Konto dauerhaft löschen",role:.destructive) {Task {await store.deleteAccount()} }
        } message: { Text("Alle mit dem Konto synchronisierten Datensätze werden auf dem Server entfernt.") }
    }
    private func exportCSV() {
        func csv(_ s:String) -> String { "\"" + s.replacingOccurrences(of:"\"",with:"\"\"") + "\"" }
        var lines = ["Datum;Titel;Kategorie;Betrag_EUR;Händler;Notiz"]
        for row in store.transactions.sorted(by:{$0.bookedAt < $1.bookedAt}) {
            let amount=String(format:"%.2f",Double(row.amountCents)/100).replacingOccurrences(of:".",with:",")
            lines.append([row.bookedAt.formatted(.iso8601),row.title,row.category,amount,row.merchant,row.notes].map(csv).joined(separator:";"))
        }
        do {
            let url=FileManager.default.temporaryDirectory.appendingPathComponent("Klar_Finanzen_\(Int(Date.now.timeIntervalSince1970)).csv")
            try ("\u{FEFF}" + lines.joined(separator:"\n")).write(to:url,atomically:true,encoding:.utf8)
            exportURL=url
        } catch {store.showError="CSV-Export fehlgeschlagen: \(error.localizedDescription)"}
    }
}
