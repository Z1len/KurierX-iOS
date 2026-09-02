import SwiftUI

struct ActivationView: View {
    @EnvironmentObject var session: SessionStore

    @State private var first = ""
    @State private var last = ""
    @State private var courier = ""
    @State private var key = ""
    @State private var error = ""
    @State private var email = ""
    @State private var password = ""
    @State private var showOwner = false
    @State private var busy = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Spacer(minLength: 30)

                    Text("KurierX")
                        .font(.system(size: 42, weight: .black, design: .rounded))

                    Text("Активация приложения")
                        .foregroundStyle(.secondary)

                    KXCard {
                        VStack(spacing: 12) {
                            TextField("Имя", text: $first)
                                .textFieldStyle(.roundedBorder)

                            TextField("Фамилия", text: $last)
                                .textFieldStyle(.roundedBorder)

                            TextField("Courier ID", text: $courier)
                                .keyboardType(.numberPad)
                                .textFieldStyle(.roundedBorder)

                            TextField("KX-XXXX-XXXX-XXXX", text: $key)
                                .textFieldStyle(.roundedBorder)

                            if !error.isEmpty {
                                Text(error)
                                    .foregroundStyle(.red)
                            }

                            Button("Активировать") {
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
                            .buttonStyle(.borderedProminent)
                            .tint(Color.kxGreen)
                            .disabled(busy)
                        }
                    }

                    Button("OWNER / Developer") {
                        showOwner.toggle()
                    }
                    .buttonStyle(.bordered)

                    if showOwner {
                        KXCard {
                            VStack(spacing: 12) {
                                TextField("Email", text: $email)
                                    .textFieldStyle(.roundedBorder)

                                SecureField("Пароль", text: $password)
                                    .textFieldStyle(.roundedBorder)

                                Button("Войти как OWNER") {
                                    Task {
                                        do {
                                            try await session.ownerLogin(
                                                email: email,
                                                password: password
                                            )
                                        } catch {
                                            self.error = error.localizedDescription
                                        }
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(Color.kxGreen)
                            }
                        }
                    }
                }
                .padding(18)
            }
        }
        .toolbar {
            KeyboardDoneToolbar()
        }
    }
}
