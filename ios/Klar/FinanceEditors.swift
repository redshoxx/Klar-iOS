import SwiftUI

struct TransactionEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    private let existing: TransactionEntry?
    @State private var title: String
    @State private var amount: String
    @State private var category: String
    @State private var income: Bool
    @State private var date: Date
    @State private var merchant: String
    @State private var notes: String
    @State private var showDelete = false
    private let categories = ["Lebensmittel","Wohnen","Mobilität","Freizeit","Shopping","Gesundheit","Gehalt","Sonstiges"]

    init(existing:TransactionEntry? = nil) {
        self.existing=existing
        _title=State(initialValue:existing?.title ?? "")
        _amount=State(initialValue: existing.map { String(format:"%.2f",Double(abs($0.amountCents))/100).replacingOccurrences(of:".",with:",") } ?? "")
        _category=State(initialValue:existing?.category ?? "Lebensmittel")
        _income=State(initialValue:(existing?.amountCents ?? -1) >= 0)
        _date=State(initialValue:existing?.bookedAt ?? .now)
        _merchant=State(initialValue:existing?.merchant ?? "")
        _notes=State(initialValue:existing?.notes ?? "")
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Buchung") {
                    Picker("Art",selection:$income) { Text("Ausgabe").tag(false);Text("Einnahme").tag(true) }.pickerStyle(.segmented)
                    TextField("Bezeichnung",text:$title)
                    HStack { Text("Betrag"); Spacer(); TextField("0,00",text:$amount).keyboardType(.decimalPad).multilineTextAlignment(.trailing);Text("€") }
                    Picker("Kategorie",selection:$category) { ForEach(categories,id:\.self) { Text($0) } }
                    DatePicker("Datum & Uhrzeit",selection:$date)
                    TextField("Händler (optional)",text:$merchant)
                    TextField("Notiz",text:$notes,axis:.vertical)
                }
                if existing != nil { Section { Button("Buchung löschen",role:.destructive) { showDelete=true } } }
            }
            .navigationTitle(existing == nil ? "Neue Buchung":"Buchung bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement:.confirmationAction) {
                    Button("Sichern") {
                        guard let cents=amount.cents else { return }
                        var item=existing ?? TransactionEntry(title:title,amountCents:0,category:category)
                        item.title=title.trimmingCharacters(in:.whitespacesAndNewlines)
                        item.amountCents=income ? abs(cents) : -abs(cents)
                        item.category=category;item.bookedAt=date;item.merchant=merchant;item.notes=notes
                        store.upsert("transactions",id:item.id,value:item)
                        dismiss()
                    }.disabled(title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || amount.cents == nil || amount.cents == 0)
                }
            }
            .confirmationDialog("Buchung löschen?",isPresented:$showDelete) {
                Button("Löschen",role:.destructive) { if let existing { store.remove("transactions",id:existing.id) }; dismiss() }
            }
        }
    }
}

struct RecurringEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store:AppStore
    private let existing:RecurringEntry?
    @State private var title:String
    @State private var amount:String
    @State private var category:String
    @State private var kind:String
    @State private var cadence:String
    @State private var date:Date
    @State private var reminderDays:Int
    @State private var active:Bool
    @State private var showDelete = false
    init(existing:RecurringEntry?=nil) {
        self.existing=existing
        _title=State(initialValue:existing?.title ?? "")
        _amount=State(initialValue:existing.map{String(format:"%.2f",Double($0.amountCents)/100).replacingOccurrences(of:".",with:",")} ?? "")
        _category=State(initialValue:existing?.category ?? "Wohnen")
        _kind=State(initialValue:existing?.kind ?? "fixkosten")
        _cadence=State(initialValue:existing?.cadence ?? "monatlich")
        _date=State(initialValue:existing.flatMap{DateFormatter.klarDay.date(from:$0.nextDue)} ?? .now)
        _reminderDays=State(initialValue:existing?.reminderDays ?? 3)
        _active=State(initialValue:existing?.active ?? true)
    }
    var body:some View {
        Form {
            Section("Regelmäßige Zahlung") {
                TextField("Bezeichnung",text:$title)
                HStack { Text("Betrag"); Spacer(); TextField("0,00",text:$amount).keyboardType(.decimalPad).multilineTextAlignment(.trailing);Text("€") }
                Picker("Typ",selection:$kind) { Text("Fixkosten").tag("fixkosten"); Text("Abo").tag("abo") }
                Picker("Kategorie",selection:$category) {
                    ForEach(["Wohnen","Internet","Versicherung","Streaming","Mobilität","Sonstiges"],id:\.self){Text($0)}
                }
                Picker("Intervall",selection:$cadence) {
                    Text("Wöchentlich").tag("woechentlich")
                    Text("Monatlich").tag("monatlich")
                    Text("Jährlich").tag("jaehrlich")
                }
                DatePicker("Nächste Fälligkeit",selection:$date,displayedComponents:.date)
                Stepper("Erinnerung \(reminderDays) Tage vorher",value:$reminderDays,in:0...30)
                Toggle("Aktiv",isOn:$active).tint(.klarGreen)
            }
            if existing != nil { Section { Button("Dauerauftrag löschen",role:.destructive) { showDelete=true } } }
        }
        .navigationTitle(existing == nil ? "Fixkosten hinzufügen":"Zahlung bearbeiten")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement:.cancellationAction) { Button("Abbrechen") { dismiss() } }
            ToolbarItem(placement:.confirmationAction) {
                Button("Sichern") {
                    guard let cents=amount.cents else { return }
                    var model=existing ?? RecurringEntry(title:title,amountCents:cents,category:category,nextDue:DateFormatter.klarDay.string(from:date))
                    model.title=title.trimmingCharacters(in:.whitespacesAndNewlines)
                    model.amountCents=abs(cents);model.kind=kind;model.cadence=cadence;model.category=category
                    model.nextDue=DateFormatter.klarDay.string(from:date);model.reminderDays=reminderDays;model.active=active
                    store.upsert("recurring",id:model.id,value:model);dismiss()
                }.disabled(title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || amount.cents == nil)
            }
        }
        .confirmationDialog("Zahlung löschen?",isPresented:$showDelete) {
            Button("Löschen",role:.destructive) { if let existing { store.remove("recurring",id:existing.id) };dismiss() }
        }
    }
}

struct BudgetEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store:AppStore
    @State private var amount:String=""
    var body:some View {
        NavigationStack {
            Form { Section("Monatliches Gesamtbudget") {
                HStack { TextField("z. B. 2.000,00",text:$amount).keyboardType(.decimalPad);Text("€") }
                Text("Für diesen Monat und folgende Monate. Fixkosten werden separat ausgewiesen.")
                    .font(.caption).foregroundStyle(.secondary)
            }}
            .navigationTitle("Budget")
            .toolbar {
                ToolbarItem(placement:.cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement:.confirmationAction) {
                    Button("Sichern") {
                        let existing=store.budgets.first{$0.category == "Gesamt"}
                        var model=existing ?? BudgetEntry()
                        model.monthlyLimitCents=max(0,amount.cents ?? 0)
                        store.upsert("budgets",id:model.id,value:model);dismiss()
                    }.disabled(amount.cents == nil)
                }
            }
            .onAppear { amount=store.budgets.first(where:{$0.category == "Gesamt"}).map{String(format:"%.2f",Double($0.monthlyLimitCents)/100).replacingOccurrences(of:".",with:",")} ?? "2000,00" }
        }
    }
}
