import SwiftUI
import Charts

struct FinanceView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showTransaction = false
    @State private var showRecurring = false
    @State private var showBudget = false
    @State private var editTransaction: TransactionEntry?
    @State private var detail = "Übersicht"
    private let categories = ["Wohnen","Lebensmittel","Mobilität","Freizeit","Shopping","Gesundheit","Sonstiges"]

    private var thisMonth: [TransactionEntry] {
        store.transactions.filter { Calendar.current.isDate($0.bookedAt,equalTo:.now,toGranularity:.month) }
    }
    private var income: Int { thisMonth.filter{ $0.amountCents > 0 }.reduce(0){$0+$1.amountCents} }
    private var spent: Int { -thisMonth.filter{ $0.amountCents < 0 }.reduce(0){$0+$1.amountCents} }
    private var fixed: Int {
        store.recurring.filter{$0.active && $0.kind == "fixkosten"}.reduce(0) { $0 + monthlyEquivalent($1) }
    }
    private var subscriptions: Int {
        store.recurring.filter{$0.active && $0.kind == "abo"}.reduce(0) { $0 + monthlyEquivalent($1) }
    }
    private var budget: Int { store.budgets.first(where:{$0.category == "Gesamt"})?.monthlyLimitCents ?? 200_000 }
    private var available: Int { income - spent - fixed - subscriptions }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:18) {
                    ScreenTitle(title:"Finanzen")
                    Picker("Bereich",selection:$detail) {
                        Text("Übersicht").tag("Übersicht")
                        Text("Buchungen").tag("Buchungen")
                        Text("Fixkosten").tag("Fixkosten")
                    }.pickerStyle(.segmented)
                    if detail == "Übersicht" { overview }
                    else if detail == "Buchungen" { transactionsList }
                    else { recurringList }
                }.padding(17)
            }.klarScreen().refreshable { await store.sync() }
            .toolbar {
                ToolbarItem(placement:.topBarTrailing) {
                    Menu {
                        Button("Ausgabe oder Einnahme",systemImage:"plus") { showTransaction = true }
                        Button("Fixkosten oder Abo",systemImage:"repeat") { showRecurring = true }
                        Button("Budget einstellen",systemImage:"slider.horizontal.3") { showBudget = true }
                    } label: { Image(systemName:"plus.circle.fill").font(.title3) }
                }
            }
            .sheet(isPresented:$showTransaction) { TransactionEditor() }
            .sheet(item:$editTransaction) { TransactionEditor(existing:$0) }
            .sheet(isPresented:$showRecurring) { NavigationStack { RecurringEditor() } }
            .sheet(isPresented:$showBudget) { BudgetEditor() }
        }
    }

    private var overview: some View {
        VStack(alignment:.leading,spacing:17) {
            KlarCard {
                VStack(alignment:.leading,spacing:9) {
                    HStack { Text("Voraussichtlich verfügbar").font(.subheadline); Spacer(); Image(systemName:"wallet.pass.fill").font(.title2) }
                    Text(available.euros).font(.system(size:36,weight:.bold,design:.rounded))
                    Text("Einnahmen abzüglich erfasster Ausgaben und geplanter Fixkosten")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.background(Color.klarSoftGreen.opacity(0.25),in:RoundedRectangle(cornerRadius:20))
            HStack(spacing:10) {
                metric("Fixkosten",value:fixed,symbol:"house",subtitle:"pro Monat")
                metric("Abos",value:subscriptions,symbol:"repeat",subtitle:"pro Monat")
                metric("Ausgaben",value:spent,symbol:"bag",subtitle:"dieser Monat")
            }
            SectionLabel(title:"Ausgaben im Überblick")
            KlarCard {
                Chart(monthlyPoints) { point in
                    BarMark(x:.value("Monat",point.label),y:.value("Euro",point.total))
                        .foregroundStyle(Color.klarGreen.gradient)
                        .cornerRadius(4)
                }
                .chartYAxis { AxisMarks(position:.leading) }
                .frame(height:180)
            }
            HStack {
                SectionLabel(title:"Monatsbudget")
                Button("Anpassen") { showBudget = true }.font(.caption)
            }
            KlarCard {
                VStack(alignment:.leading,spacing:8) {
                    HStack { Text("\(spent.euros) von \(budget.euros)"); Spacer(); Text("\(max(0,budget-spent).euros) übrig") }
                        .font(.subheadline)
                    ProgressView(value:Double(min(spent,budget)),total:Double(max(1,budget))).tint(.klarGreen)
                }
            }
            SectionLabel(title:"Nächste Abbuchungen")
            KlarCard {
                let bills = store.recurring.filter(\.active).sorted{$0.nextDue < $1.nextDue}
                if bills.isEmpty { EmptyHint(symbol:"calendar",title:"Keine Abbuchungen",message:"Erfasse deine Fixkosten und Abos.") }
                else { ForEach(bills.prefix(4)) { RecurringRow(recurring:$0) } }
            }
            PrimaryButton(title:"Buchung hinzufügen",symbol:"plus") { showTransaction = true }
        }
    }

    private func metric(_ title:String,value:Int,symbol:String,subtitle:String) -> some View {
        KlarCard {
            VStack(alignment:.leading,spacing:8) {
                Image(systemName:symbol).font(.title3).foregroundStyle(Color.klarGreen)
                Text(title).font(.system(size:11,weight:.medium))
                Text(value.euros).font(.system(size:15,weight:.bold,design:.rounded)).minimumScaleFactor(0.7).lineLimit(1)
                Text(subtitle).font(.system(size:10)).foregroundStyle(.secondary)
            }
        }
    }

    private var transactionsList: some View {
        VStack(alignment:.leading,spacing:15) {
            HStack { SectionLabel(title:"Alle Buchungen"); Spacer(); Button("Hinzufügen") { showTransaction=true }.font(.subheadline) }
            KlarCard {
                let rows = store.transactions.sorted{$0.bookedAt > $1.bookedAt}
                if rows.isEmpty { EmptyHint(symbol:"creditcard",title:"Noch keine Buchungen",message:"Erfasse Einnahmen und Ausgaben mit dem Plus-Symbol.") }
                else {
                    ForEach(rows) { row in
                        Button { editTransaction = row } label: {
                            HStack(spacing:10) {
                                Image(systemName:row.amountCents >= 0 ? "arrow.down.left":"arrow.up.right")
                                    .foregroundStyle(row.amountCents >= 0 ? .green:.primary)
                                VStack(alignment:.leading,spacing:3) {
                                    Text(row.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                                    Text("\(row.category) · \(row.bookedAt.formatted(date:.abbreviated,time:.shortened))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(row.amountCents.euros)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(row.amountCents >= 0 ? .green:.primary)
                            }.padding(.vertical,7)
                        }.buttonStyle(.plain)
                        if row.id != rows.last?.id { Divider() }
                    }
                }
            }
        }
    }

    private var recurringList: some View {
        VStack(alignment:.leading,spacing:15) {
            HStack { SectionLabel(title:"Fixkosten & Abos"); Spacer(); Button("Hinzufügen") { showRecurring=true }.font(.subheadline) }
            KlarCard {
                VStack(alignment:.leading,spacing:7) {
                    Text("Regelmäßige Monatsbelastung").font(.subheadline).foregroundStyle(.secondary)
                    Text((fixed+subscriptions).euros).font(.system(size:28,weight:.bold,design:.rounded))
                }
            }
            KlarCard {
                if store.recurring.isEmpty { EmptyHint(symbol:"repeat",title:"Keine Fixkosten",message:"Erfasse Miete, Internet, Versicherungen oder Abos.") }
                else {
                    ForEach(store.recurring.sorted{$0.nextDue < $1.nextDue}) { row in
                        NavigationLink { RecurringEditor(existing:row) } label: { RecurringRow(recurring:row) }
                            .buttonStyle(.plain)
                        Divider()
                    }
                }
            }
        }
    }

    private var monthlyPoints: [MonthlyPoint] {
        let cal = Calendar.current
        return (0..<6).reversed().compactMap { offset -> MonthlyPoint? in
            guard let date = cal.date(byAdding:.month,value:-offset,to:.now) else { return nil }
            let amount = -store.transactions.filter { cal.isDate($0.bookedAt,equalTo:date,toGranularity:.month) && $0.amountCents < 0 }
                .reduce(0){$0+$1.amountCents}
            return MonthlyPoint(label:date.formatted(.dateTime.month(.abbreviated)),total:Double(amount)/100)
        }
    }
}

private struct MonthlyPoint: Identifiable {
    let id = UUID()
    let label: String
    let total: Double
}

func monthlyEquivalent(_ recurring: RecurringEntry) -> Int {
    switch recurring.cadence {
    case "woechentlich": NSDecimalNumber(decimal:(Decimal(recurring.amountCents) * Decimal(52) / Decimal(12)).rounded(0)).intValue
    case "jaehrlich": recurring.amountCents / 12
    default: recurring.amountCents
    }
}
