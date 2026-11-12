import SwiftUI

struct TasksView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selection = "Heute"
    @State private var search = ""
    @State private var editing: TaskEntry?
    @State private var showNew = false
    private let options = ["Heute","Diese Woche","Alle"]

    private var visible: [TaskEntry] {
        store.tasks.filter { task in
            let matches = search.isEmpty || task.title.localizedCaseInsensitiveContains(search) || task.project.localizedCaseInsensitiveContains(search)
            guard matches else { return false }
            switch selection {
            case "Heute": return task.dueAt == nil || Calendar.current.isDateInToday(task.dueAt!)
            case "Diese Woche":
                return task.dueAt == nil || Calendar.current.isDate(task.dueAt!,equalTo:.now,toGranularity:.weekOfYear)
            default: return true
            }
        }.sorted { a,b in
            if a.completed != b.completed { return !a.completed }
            return (a.dueAt ?? .distantFuture) < (b.dueAt ?? .distantFuture)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:18) {
                    ScreenTitle(title:"Aufgaben")
                    Picker("Zeitraum",selection:$selection) {
                        ForEach(options,id:\.self) { Text($0).tag($0) }
                    }.pickerStyle(.segmented)
                    KlarCard {
                        let done = visible.filter(\.completed).count
                        HStack {
                            Image(systemName:"checkmark.circle.fill").font(.largeTitle).foregroundStyle(Color.klarGreen)
                            VStack(alignment:.leading) {
                                Text("\(done) von \(visible.count) erledigt").font(.headline)
                                ProgressView(value:Double(done),total:Double(max(1,visible.count))).tint(.klarGreen)
                            }
                            Text("\(Int(Double(done)/Double(max(1,visible.count))*100)) %")
                                .font(.subheadline.weight(.medium))
                        }
                    }
                    HStack {
                        SectionLabel(title:"\(selection) (\(visible.filter{ !$0.completed }.count))")
                        Spacer()
                        Button { showNew = true } label: { Image(systemName:"plus.circle.fill").font(.title2) }
                    }
                    KlarCard {
                        if visible.isEmpty {
                            EmptyHint(symbol:"checkmark.circle",title:"Noch keine Aufgaben",message:"Erstelle deine erste Aufgabe mit dem Plus-Symbol.")
                        } else {
                            ForEach(visible) { task in
                                HStack(spacing:8) {
                                    TaskRow(task:task) { store.toggle(task) }
                                    Button { editing = task } label: {
                                        Image(systemName:"chevron.right").foregroundStyle(.tertiary)
                                    }.accessibilityLabel("Aufgabe bearbeiten")
                                }
                                if task.id != visible.last?.id { Divider() }
                            }
                        }
                    }
                }.padding(17)
            }
            .klarScreen()
            .searchable(text:$search,prompt:"Aufgaben suchen")
            .refreshable { await store.sync() }
            .sheet(isPresented:$showNew) { TaskEditor() }
            .sheet(item:$editing) { TaskEditor(existing:$0) }
            .toolbar {
                ToolbarItem(placement:.topBarTrailing) {
                    Button { showNew = true } label: { Image(systemName:"plus") }
                }
            }
        }
    }
}
