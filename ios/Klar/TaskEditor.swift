import SwiftUI

struct TaskEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    private let existing: TaskEntry?
    @State private var title: String
    @State private var notes: String
    @State private var project: String
    @State private var priority: String
    @State private var useDue: Bool
    @State private var due: Date
    @State private var repeatRule: String
    @State private var showDelete = false

    init(existing: TaskEntry? = nil) {
        self.existing = existing
        _title = State(initialValue:existing?.title ?? "")
        _notes = State(initialValue:existing?.notes ?? "")
        _project = State(initialValue:existing?.project ?? "")
        _priority = State(initialValue:existing?.priority ?? "mittel")
        _useDue = State(initialValue:existing?.dueAt != nil)
        _due = State(initialValue:existing?.dueAt ?? .now)
        _repeatRule = State(initialValue:existing?.repeatRule ?? "nie")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Aufgabe") {
                    TextField("Was möchtest du erledigen?",text:$title)
                    TextField("Projekt (optional)",text:$project)
                    TextField("Notizen",text:$notes,axis:.vertical).lineLimit(2...5)
                }
                Section("Planung") {
                    Picker("Priorität",selection:$priority) {
                        Text("Niedrig").tag("niedrig")
                        Text("Mittel").tag("mittel")
                        Text("Hoch").tag("hoch")
                    }
                    Toggle("Fälligkeit",isOn:$useDue).tint(.klarGreen)
                    if useDue { DatePicker("Wann?",selection:$due,displayedComponents:[.date,.hourAndMinute]) }
                    Picker("Wiederholung",selection:$repeatRule) {
                        Text("Nie").tag("nie")
                        Text("Täglich").tag("taeglich")
                        Text("Wöchentlich").tag("woechentlich")
                        Text("Monatlich").tag("monatlich")
                    }
                }
                if existing != nil {
                    Section { Button("Aufgabe löschen",role:.destructive) { showDelete = true } }
                }
            }
            .navigationTitle(existing == nil ? "Neue Aufgabe":"Aufgabe bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement:.confirmationAction) {
                    Button("Sichern") {
                        var model = existing ?? TaskEntry(title:title)
                        model.title=title.trimmingCharacters(in:.whitespacesAndNewlines)
                        model.notes=notes; model.project=project; model.priority=priority
                        model.dueAt=useDue ? due:nil; model.repeatRule=repeatRule
                        store.upsert("tasks",id:model.id,value:model); dismiss()
                    }.disabled(title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                }
            }
            .confirmationDialog("Aufgabe wirklich löschen?",isPresented:$showDelete) {
                Button("Löschen",role:.destructive) {
                    if let existing { store.remove("tasks",id:existing.id) }
                    dismiss()
                }
            }
        }
    }
}
