import SwiftUI

struct ShoppingView: View {
    @EnvironmentObject private var store:AppStore
    @State private var activeID:UUID?
    @State private var showList = false
    @State private var listName = ""
    @State private var showItem = false
    @State private var showCheckout = false
    @State private var checkoutAmount = ""
    @State private var editItem:ShoppingItemEntry?
    @State private var confirmArchive = false

    private var visibleLists:[ShoppingListEntry] { store.shoppingLists.filter{!$0.archived}.sorted{$0.name < $1.name} }
    private var chosenList:ShoppingListEntry? {
        visibleLists.first{$0.id == activeID} ?? visibleLists.first
    }
    private var items:[ShoppingItemEntry] {
        guard let id = chosenList?.id else { return [] }
        return store.shoppingItems.filter{$0.listID == id}.sorted { a,b in
            if a.checked != b.checked { return !a.checked }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
    private var total:Int { items.reduce(0){$0+$1.totalCents} }
    private var remaining:Int { items.filter{!$0.checked}.reduce(0){$0+$1.totalCents} }

    var body:some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:18) {
                    ScreenTitle(title:"Einkaufsliste")
                    HStack {
                        Menu {
                            ForEach(visibleLists) { list in
                                Button(list.name) { activeID=list.id }
                            }
                            Button("Neue Liste",systemImage:"plus") { listName="";showList=true }
                        } label: {
                            HStack(spacing:10) {
                                Image(systemName:"cart.fill").foregroundStyle(Color.klarGreen)
                                Text(chosenList?.name ?? "Neue Einkaufsliste").font(.headline)
                                Spacer()
                                Image(systemName:"chevron.down").foregroundStyle(.secondary)
                            }.padding(15).background(Color(uiColor:.secondarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:19))
                        }.buttonStyle(.plain)
                        Button { listName="";showList=true } label: { Image(systemName:"plus.circle.fill").font(.title2) }
                    }
                    KlarCard {
                        if chosenList == nil {
                            EmptyHint(symbol:"basket",title:"Noch keine Liste",message:"Erstelle eine Einkaufsliste für deinen nächsten Einkauf.")
                        } else if items.isEmpty {
                            EmptyHint(symbol:"cart",title:"Liste ist leer",message:"Füge Artikel mit Menge und Preis hinzu.")
                        } else {
                            ForEach(items) { item in
                                HStack(spacing:11) {
                                    Button {
                                        var changed = item; changed.checked.toggle()
                                        store.upsert("shopping_items",id:item.id,value:changed)
                                    } label: {
                                        Image(systemName:item.checked ? "checkmark.square.fill":"square")
                                            .font(.system(size:24)).foregroundStyle(item.checked ? Color.klarGreen:.secondary)
                                    }.buttonStyle(.plain)
                                    VStack(alignment:.leading,spacing:3) {
                                        Text(item.name).font(.subheadline.weight(.semibold)).strikethrough(item.checked)
                                        Text("\(item.quantity.formatted()) × \(item.unit)")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength:4)
                                    Text(item.totalCents.euros)
                                        .font(.subheadline.weight(.medium)).foregroundStyle(item.checked ? .secondary:.primary)
                                    Button { editItem=item } label: {Image(systemName:"ellipsis").font(.caption)}
                                        .accessibilityLabel("Artikel bearbeiten")
                                }.padding(.vertical,10)
                                if item.id != items.last?.id { Divider() }
                            }
                        }
                    }
                    PrimaryButton(title:"Artikel hinzufügen",symbol:"plus") {
                        if chosenList == nil { showList=true } else { showItem=true }
                    }
                    if chosenList != nil {
                        KlarCard {
                            HStack {
                                Image(systemName:"cart.fill").foregroundStyle(Color.klarGreen).font(.title2)
                                VStack(alignment:.leading,spacing:3) {
                                    Text("Geschätzter Gesamtpreis").font(.subheadline)
                                    Text("Noch offen: \(remaining.euros)").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(total.euros).font(.system(size:23,weight:.bold,design:.rounded))
                            }
                        }
                        PrimaryButton(title:"Einkauf als Ausgabe verbuchen",symbol:"checkmark.circle") {
                            checkoutAmount=String(format:"%.2f",Double(total)/100).replacingOccurrences(of:".",with:",")
                            showCheckout=true
                        }
                        .disabled(items.isEmpty)
                        Button("Liste archivieren",role:.destructive) { confirmArchive=true }
                            .frame(maxWidth:.infinity).font(.footnote)
                    }
                }.padding(17)
            }.klarScreen()
            .refreshable { await store.sync() }
            .sheet(isPresented:$showList) { createListSheet }
            .sheet(isPresented:$showItem) { if let id=chosenList?.id { ShoppingItemEditor(listID:id) } }
            .sheet(item:$editItem) { ShoppingItemEditor(listID:$0.listID,existing:$0) }
            .alert("Einkauf abschließen",isPresented:$showCheckout) {
                TextField("Tatsächlicher Betrag in €",text:$checkoutAmount).keyboardType(.decimalPad)
                Button("Verbuchen") { checkout() }
                Button("Abbrechen",role:.cancel) {}
            } message: {
                Text("Der tatsächliche Gesamtbetrag wird einmalig als Ausgabe in der Kategorie Lebensmittel gebucht.")
            }
            .confirmationDialog("Liste archivieren?",isPresented:$confirmArchive) {
                Button("Archivieren",role:.destructive) {
                    guard var list=chosenList else { return }
                    list.archived=true
                    store.upsert("shopping_lists",id:list.id,value:list)
                    activeID=nil
                }
            }
        }
    }
    private var createListSheet:some View {
        NavigationStack {
            Form { Section("Name") { TextField("z. B. Wocheneinkauf",text:$listName) } }
                .navigationTitle("Neue Liste")
                .toolbar {
                    ToolbarItem(placement:.cancellationAction) { Button("Abbrechen") { showList=false } }
                    ToolbarItem(placement:.confirmationAction) {
                        Button("Erstellen") {
                            let list=ShoppingListEntry(name:listName.trimmingCharacters(in:.whitespacesAndNewlines))
                            store.upsert("shopping_lists",id:list.id,value:list)
                            activeID=list.id;showList=false
                        }.disabled(listName.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                    }
                }
        }
    }
    private func checkout() {
        guard let cost = checkoutAmount.cents, cost >= 0, let list=chosenList else {
            store.showError="Bitte einen gültigen Einkaufsbetrag eingeben.";return
        }
        let value=TransactionEntry(title:"Einkauf: \(list.name)",amountCents:-abs(cost),category:"Lebensmittel")
        store.upsert("transactions",id:value.id,value:value)
        // Archive the completed list so accidental re-taps cannot create a duplicate expense.
        var completedList=list
        completedList.archived=true
        store.upsert("shopping_lists",id:completedList.id,value:completedList)
        activeID=nil
        showCheckout=false
        store.showError="Einkauf wurde in den Finanzen verbucht."
    }
}

struct ShoppingItemEditor:View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store:AppStore
    let listID:UUID
    var existing:ShoppingItemEntry?=nil
    @State private var name=""
    @State private var quantity="1"
    @State private var unit="Stk"
    @State private var price=""
    @State private var showDelete=false

    var body:some View {
        NavigationStack {
            Form {
                Section("Artikel") {
                    TextField("Artikelname",text:$name)
                    HStack { Text("Menge");Spacer();TextField("1",text:$quantity).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                    Picker("Einheit",selection:$unit) { ForEach(["Stk","kg","g","l","ml","Pack"],id:\.self){ Text($0) } }
                    HStack { Text("Einzelpreis");Spacer();TextField("0,00",text:$price).keyboardType(.decimalPad).multilineTextAlignment(.trailing);Text("€") }
                }
                if existing != nil { Section { Button("Artikel löschen",role:.destructive) { showDelete=true } } }
            }
            .navigationTitle(existing == nil ? "Artikel hinzufügen":"Artikel bearbeiten")
            .toolbar {
                ToolbarItem(placement:.cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement:.confirmationAction) {
                    Button("Sichern") {
                        guard let count=Double(quantity.replacingOccurrences(of:",",with:".")), count > 0,
                              let cents=price.cents else { return }
                        var item=existing ?? ShoppingItemEntry(listID:listID,name:name)
                        item.name=name.trimmingCharacters(in:.whitespacesAndNewlines)
                        item.quantity=count;item.unit=unit;item.unitPriceCents=max(0,cents)
                        store.upsert("shopping_items",id:item.id,value:item);dismiss()
                    }.disabled(name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || price.cents == nil)
                }
            }
            .confirmationDialog("Artikel löschen?",isPresented:$showDelete) {
                Button("Löschen",role:.destructive) { if let existing{store.remove("shopping_items",id:existing.id)};dismiss() }
            }
            .onAppear {
                if let existing {
                    name=existing.name;quantity=existing.quantity.formatted();unit=existing.unit
                    price=String(format:"%.2f",Double(existing.unitPriceCents)/100).replacingOccurrences(of:".",with:",")
                }
            }
        }
    }
}
