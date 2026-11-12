import SwiftUI

struct AuthScreen:View {
    @EnvironmentObject private var store: AppStore
    @AppStorage("api_base_url") private var serverURL="https://api.152.53.206.242.sslip.io"
    @State private var email=""
    @State private var password=""
    @State private var createAccount=false
    @State private var showServer=false

    var body:some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:22) {
                    Spacer(minLength:55)
                    HStack(spacing:0) {
                        Text("Klar").foregroundStyle(.primary)
                        Text(".").foregroundStyle(Color.klarGreen)
                    }.font(.system(size:51,weight:.bold,design:.rounded))
                    Text("Aufgaben. Finanzen. Einkaufen.")
                        .font(.title3.weight(.medium)).foregroundStyle(.secondary)
                    Text("Alles Wichtige für deinen Alltag an einem Ort – sicher auf deinem eigenen Server.")
                        .foregroundStyle(.secondary).font(.subheadline)
                    KlarCard {
                        VStack(alignment:.leading,spacing:17) {
                            Text(createAccount ? "Konto erstellen":"Anmelden").font(.system(.title2,design:.rounded).weight(.bold))
                            TextField("E-Mail-Adresse",text:$email)
                                .textContentType(.username).keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .padding(12).background(Color(uiColor:.tertiarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:12))
                            SecureField("Passwort (mind. 12 Zeichen)",text:$password)
                                .textContentType(createAccount ? .newPassword:.password)
                                .padding(12).background(Color(uiColor:.tertiarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:12))
                            PrimaryButton(title:createAccount ? "Registrieren":"Anmelden",symbol:"arrow.right") {
                                Task { await store.authorize(email:email,password:password,create:createAccount) }
                            }
                            .disabled(store.busy || !email.contains("@") || password.count < 12)
                            Button(createAccount ? "Schon ein Konto? Anmelden":"Noch kein Konto? Registrieren") {
                                createAccount.toggle()
                            }.font(.footnote).frame(maxWidth:.infinity)
                        }
                    }
                    Button {showServer.toggle()} label: {
                        Label("Eigenen VPS konfigurieren",systemImage:"server.rack")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    if showServer {
                        KlarCard {
                            VStack(alignment:.leading,spacing:9) {
                                Text("API-URL").font(.caption.weight(.semibold))
                                TextField("https://api.deine-domain.at",text:$serverURL)
                                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                                    .keyboardType(.URL)
                                Text("HTTPS mit gültigem Zertifikat erforderlich. Keine Zugangsdaten in der URL verwenden.")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }.padding(22)
            }.klarScreen()
        }
    }
}
