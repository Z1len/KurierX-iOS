import SwiftUI
import UIKit

struct ActivationView: View {
    @EnvironmentObject var session: SessionStore
    @State private var first = ""; @State private var last = ""; @State private var courier = ""; @State private var key = ""
    @State private var error = ""; @State private var busy = false; @State private var showOwner = false
    @State private var email = ""; @State private var password = ""
    @FocusState private var focused: Field?
    enum Field { case first,last,courier,key,email,password }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 22).fill(Color.kxGreen.opacity(0.18))
                            Image(systemName: "shippingbox.fill").font(.system(size: 34)).foregroundStyle(Color.kxGreen)
                        }.frame(width: 72, height: 72)
                        HStack(spacing: 0) { Text("Kurier").font(.system(size: 36, weight: .black, design: .rounded)); Text("X").font(.system(size: 36, weight: .black, design: .rounded)).foregroundStyle(Color.kxGreen) }
                        Text("Активация приложения").foregroundStyle(.secondary)
                    }.padding(.top, 18)

                    KXCard(content: VStack(spacing: 12) {
                        field("Имя", text: $first, focus: .first)
                        field("Фамилия", text: $last, focus: .last)
                        field("Courier ID", text: $courier, focus: .courier, keyboard: .numberPad)
                        field("KX-XXXX-XXXX-XXXX", text: $key, focus: .key)
                            .textInputAutocapitalization(.characters)
                        if !error.isEmpty { Text(error).font(.footnote).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading) }
                        Button {
                            Task { busy = true; defer { busy = false }; do { try await session.activate(firstName: first, lastName: last, courierID: courier, key: key) } catch { self.error = error.localizedDescription } }
                        } label: {
                            HStack { if busy { ProgressView() }; Text(busy ? "Проверка…" : "Активировать") }.frame(maxWidth: .infinity)
                        }.buttonStyle(.borderedProminent).tint(Color.kxGreen).disabled(busy || first.isEmpty || courier.isEmpty || key.isEmpty)
                    })

                    Button { withAnimation(.snappy) { showOwner.toggle() } } label: {
                        Label(showOwner ? "Скрыть OWNER-вход" : "OWNER / Developer", systemImage: "lock.shield").frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered)

                    if showOwner {
                        KXCard(content: VStack(spacing: 12) {
                            Text("KurierX Control").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                            field("Email", text: $email, focus: .email).textInputAutocapitalization(.never).keyboardType(.emailAddress)
                            SecureField("Пароль", text: $password).focused($focused, equals: .password).textFieldStyle(.roundedBorder)
                            Button("Войти как OWNER") {
                                Task { do { try await session.ownerLogin(email: email, password: password) } catch { self.error = error.localizedDescription } }
                            }.buttonStyle(.borderedProminent).tint(Color.kxGreen).frame(maxWidth: .infinity)
                        })
                    }
                }.padding(.horizontal, 18).padding(.bottom, 30)
            }
            .background(Color.kxBackground.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .contentShape(Rectangle()).onTapGesture { focused = nil }
            .toolbar { KeyboardDoneToolbar() }
            .navigationBarHidden(true)
        }
    }

    private func field(_ title: String, text: Binding<String>, focus: Field, keyboard: UIKeyboardType = .default) -> some View {
        TextField(title, text: text).focused($focused, equals: focus).keyboardType(keyboard).textFieldStyle(.roundedBorder).submitLabel(.next)
    }
}
