import SwiftUI

struct ActivationView: View {
    @EnvironmentObject var session: SessionStore

    @State private var first = ""
    @State private var last = ""
    @State private var courier = ""
    @State private var key = ""
    @State private var error = ""
    @State private var busy = false

    @State private var owner = false
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Активация KurierX") {
                    TextField("Имя", text: $first)
                    TextField("Фамилия", text: $last)
                    TextField("Courier ID", text: $courier)
                    TextField("KX-XXXX-XXXX-XXXX", text: $key)
                        .textInputAutocapitalization(.characters)
                }

                if !error.isEmpty {
                    Text(error)
                        .foregroundStyle(.red)
                }

                Button(busy ? "Проверка…" : "Активировать") {
                    Task {
                        busy = true
                        defer { busy = false }
                        do {
                            try await session.activate(
                                firstName: first,
                                lastName: last,
                                courierID: courier,
                                key: key
                            )
                        } catch {
                            self.error = error.localizedDescription
                        }
                    }
                }
                .disabled(busy || first.isEmpty || courier.isEmpty || key.isEmpty)

                Section {
                    Toggle("OWNER-вход", isOn: $owner)

                    if owner {
                        TextField("Email", text: $email)
                            .textInputAutocapitalization(.never)
                        SecureField("Пароль", text: $password)

                        Button("Войти как OWNER") {
                            Task {
                                do {
                                    try await session.ownerLogin(email: email, password: password)
                                } catch {
                                    self.error = error.localizedDescription
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("KurierX")
        }
    }
}
