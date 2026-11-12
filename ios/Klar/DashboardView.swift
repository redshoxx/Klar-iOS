import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: AppStore
    let goTo: (String) -> Void
    @State private var showAddTask = false
    private var monthTransactions: [TransactionEntry] {
        store.transactions.filter { Calendar.current.isDate($0.bookedAt,equalTo:.now,toGranularity:.month) }
    }
    private var expenses: Int { -monthTransactions.filter { $0.amountCents < 0 }.reduce(0) { $0 + $1.amountCents } }
    private var budget: Int { store.budgets.first(where:{$0.category == "Gesamt"})?.monthlyLimitCents ?? 200_000 }
    private var todayTasks: [TaskEntry] {
        store.tasks.filter { !$0.completed && ($0.dueAt == nil || Calendar.current.isDateInToday($0.dueAt!)) }
    }
    private var comingBills: [RecurringEntry] {
        store.recurring.filter(\.active).sorted { $0.nextDue < $1.nextDue }.prefix(3).map{$0}
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:20) {
                    HStack {
                        Text("Klar.").font(.system(size:32,weight:.bold,design:.rounded))
                        Text("•").font(.system(size:31,weight:.bold)).foregroundStyle(Color.klarGreen)
                        Spacer()
                        Button { Task { await store.sync() } } label: {
                            Image(systemName:"arrow.clockwise").font(.system(size:19))
                        }.accessibilityLabel("Synchronisieren")
                    }
                    VStack(alignment:.leading,spacing:4) {
                        Text("Guten \(greeting)").font(.system(size:23,weight:.bold,design:.rounded))
                        Text(Date.now,format:.dateTime.weekday(.wide).day().month(.wide))
                            .foregroundStyle(.secondary).font(.subheadline)
                    }
                    KlarCard {
                        Button { goTo("Aufgaben") } label: {
                            HStack(spacing:13) {
                                Image(systemName:"checkmark.circle.fill").font(.system(size:30)).foregroundStyle(Color.klarGreen)
                                VStack(alignment:.leading,spacing:6) {
                                    Text("\(store.tasks.filter(\.completed).count) von \(store.tasks.count) Aufgaben erledigt")
                                        .font(.system(.subheadline,design:.rounded).weight(.semibold))
                                    ProgressView(value:Double(store.tasks.filter(\.completed).count),
                                                 total:Double(max(1,store.tasks.count))).tint(.klarGreen)
                                }
                                Image(systemName:"chevron.right").foregroundStyle(.tertiary)
                            }
                        }.buttonStyle(.plain)
                    }
                    KlarCard {
                        VStack(alignment:.leading,spacing:10) {
                            Text("Monatsbudget").font(.headline)
                            Text("Verbleibend bis Monatsende").font(.caption).foregroundStyle(.secondary)
                            Text(max(0,budget-expenses).euros)
                                .font(.system(size:34,weight:.bold,design:.rounded))
                            ProgressView(value:Double(min(budget,expenses)),total:Double(max(1,budget))).tint(.klarGreen)
                            HStack {
                                Text("\(expenses.euros) von \(budget.euros) ausgegeben")
                                Spacer()
                                Text("\(Int(Double(expenses)/Double(max(1,budget))*100)) %")
                            }.font(.caption).foregroundStyle(.secondary)
                        }
                    }.background(Color.klarSoftGreen.opacity(0.38),in:RoundedRectangle(cornerRadius:20))
                    HStack {
                        SectionLabel(title:"Heutige Aufgaben")
                        Button("Alle anzeigen") { goTo("Aufgaben") }.font(.caption)
                    }
                    KlarCard {
                        if todayTasks.isEmpty {
                            EmptyHint(symbol:"checkmark.seal",title:"Alles erledigt",message:"Für heute sind keine Aufgaben offen.")
                        } else {
                            ForEach(todayTasks.prefix(4)) { task in
                                TaskRow(task:task) { store.toggle(task) }
                                if task.id != todayTasks.prefix(4).last?.id { Divider() }
                            }
                        }
                    }
                    SectionLabel(title:"Demnächst")
                    KlarCard {
                        if comingBills.isEmpty { EmptyHint(symbol:"calendar.badge.clock",title:"Keine Fälligkeiten",message:"Lege Fixkosten oder Abos an.") }
                        else {
                            ForEach(comingBills) { bill in
                                RecurringRow(recurring:bill)
                                if bill.id != comingBills.last?.id { Divider() }
                            }
                        }
                    }
                    Text(store.syncStatus).font(.caption).foregroundStyle(.secondary)
                }.padding(17)
            }
            .klarScreen()
            .refreshable { await store.sync() }
            .toolbar {
                ToolbarItem(placement:.topBarTrailing) {
                    Button { showAddTask = true } label: { Image(systemName:"plus.circle.fill") }
                }
            }
            .sheet(isPresented:$showAddTask) { TaskEditor() }
        }
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour,from:.now)
        return h < 11 ? "Morgen" : h < 18 ? "Tag" : "Abend"
    }
}
