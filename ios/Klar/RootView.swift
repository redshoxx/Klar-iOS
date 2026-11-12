import SwiftUI

private enum AppTab: String,CaseIterable {
    case today = "Heute", tasks = "Aufgaben", finances = "Finanzen", shopping = "Einkaufen", more = "Mehr"
    var icon: String {
        switch self {
        case .today:"house.fill"
        case .tasks:"checkmark.circle"
        case .finances:"chart.bar.fill"
        case .shopping:"cart"
        case .more:"ellipsis"
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.scenePhase) private var phase
    @StateObject private var gate = UnlockGate()
    @State private var selected: AppTab = .today
    @AppStorage("app_lock") private var appLock = false
    @AppStorage("appearance") private var appearance = "system"

    var body: some View {
        Group {
            if !store.loggedIn {
                AuthScreen()
            } else if appLock && !gate.unlocked {
                VStack(spacing:22) {
                    Spacer()
                    Image(systemName:"lock.shield.fill").font(.system(size:64)).foregroundStyle(Color.klarGreen)
                    Text("Klar.").font(.system(size:38,weight:.bold,design:.rounded))
                    Text("Deine persönlichen Daten sind geschützt.").foregroundStyle(.secondary)
                    PrimaryButton(title:"Mit Face ID oder Code entsperren",symbol:"faceid") {
                        Task { await gate.authenticate() }
                    }.padding(.horizontal,30)
                    if let error = gate.error { Text(error).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center) }
                    Spacer()
                }.task { await gate.authenticate() }
            } else {
                VStack(spacing:0) {
                    Group {
                        switch selected {
                        case .today: DashboardView(goTo:selectedTab)
                        case .tasks: TasksView()
                        case .finances: FinanceView()
                        case .shopping: ShoppingView()
                        case .more: MoreView()
                        }
                    }.frame(maxWidth:.infinity,maxHeight:.infinity)
                }
                .safeAreaInset(edge:.bottom,spacing:0) {
                    HStack(spacing:2) {
                        ForEach(AppTab.allCases,id:\.self) { tab in
                            Button {
                                selected = tab
                            } label: {
                                VStack(spacing:5) {
                                    Image(systemName:tab.icon).font(.system(size:19,weight:.semibold))
                                    Text(tab.rawValue).font(.system(size:10,weight:selected == tab ? .semibold:.regular))
                                }
                                .foregroundStyle(selected == tab ? Color.klarGreen : Color.secondary)
                                .frame(maxWidth:.infinity)
                                .padding(.vertical,9)
                                .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal,8)
                    .background(.regularMaterial,in:RoundedRectangle(cornerRadius:22,style:.continuous))
                    .overlay(RoundedRectangle(cornerRadius:22).stroke(.white.opacity(0.35),lineWidth:1))
                    .padding(.horizontal,13).padding(.bottom,4)
                }
            }
        }
        .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
        .alert("Hinweis",isPresented:Binding(get:{ store.showError != nil },set:{ if !$0 { store.showError = nil } })) {
            Button("OK") { store.showError = nil }
        } message: { Text(store.showError ?? "") }
        .onChange(of:store.accountID) { _, _ in
            // Do not reuse a previous device-unlock state after switching accounts.
            gate.unlocked = false
        }
        .onChange(of:phase) { _, next in
            if next == .background && appLock { gate.unlocked = false }
            if next == .active && store.loggedIn { Task { await store.sync() } }
        }
    }
    private func selectedTab(_ name: String) {
        if let tab = AppTab(rawValue:name) { selected = tab }
    }
}
