import SwiftUI
import UIKit

struct ActivationView: View {
    @EnvironmentObject var session: SessionStore
    @State private var first = ""; @State private var last = ""; @State private var courier = ""; @State private var key = ""
    @State private var error = ""; @State private var busy = false; @State private var showOwner = false
    @State private var email = ""; @State private var password = ""
    @FocusState private var focus: Field?
    enum Field { case first,last,courier,key,email,password }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Spacer(minLength: 12)
                    VStack(spacing: 8) {
                        ZStack { RoundedRectangle(cornerRadius: 18).fill(Color.kxGreen.opacity(0.16)); Image(systemName: "shippingbox.fill").font(.system(size: 34)).foregroundStyle(Color.kxGreen) }.frame(width: 72, height: 72)
                        HStack(spacing: 0) { Text("Kurier").font(.system(size: 38, weight: .black, design: .rounded)); Text("X").font(.system(size: 38, weight: .black, design: .rounded)).foregroundStyle(Color.kxGreen) }
                        Text("Активация приложения").font(.title3).foregroundStyle(.secondary)
                    }
                    KXCard {
                        VStack(spacing: 12) {
                            input("Имя", $first, .first)
                            input("Фамилия", $last, .last)
                            input("Courier ID", $courier, .courier, .numberPad)
                            input("KX-XXXX-XXXX-XXXX", $key, .key).textInputAutocapitalization(.characters)
                            if !error.isEmpty { Text(error).font(.footnote).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading) }
                            Button {
                                Task { busy = true; defer { busy = false }; do { try await session.activate(firstName: first, lastName: last, courierID: courier, key: key) } catch { self.error = error.localizedDescription } }
                            } label: { HStack { if busy { ProgressView() }; Text(busy ? "Проверка…" : "Активировать").fontWeight(.semibold) }.frame(maxWidth: .infinity) }
                            .buttonStyle(.borderedProminent).tint(Color.kxGreen).controlSize(.large).disabled(busy || first.isEmpty || courier.isEmpty || key.isEmpty)
                        }
                    }
                    Button { withAnimation { showOwner.toggle() } } label: { Label("OWNER / Developer", systemImage: "lock.shield.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).tint(Color.kxGreen.opacity(0.34)).controlSize(.large)
                    if showOwner {
                        KXCard {
                            VStack(spacing: 12) {
                                Text("KurierX Control").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                                input("Email", $email, .email).textInputAutocapitalization(.never).keyboardType(.emailAddress)
                                SecureField("Пароль", text: $password).focused($focus, equals: .password).textFieldStyle(.roundedBorder)
                                Button("Войти как OWNER") { Task { do { try await session.ownerLogin(email: email, password: password) } catch { self.error = error.localizedDescription } } }
                                    .buttonStyle(.borderedProminent).tint(Color.kxGreen).frame(maxWidth: .infinity)
                            }
                        }
                    }
                    Spacer(minLength: 16)
                }
                .padding(.horizontal, 18).padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
            .kxDismissKeyboardOnTap()
            .background(Color.kxBackground.ignoresSafeArea())
            .toolbar { KeyboardDoneToolbar() }
            .navigationBarHidden(true)
        }
    }

    private func input(_ title: String, _ text: Binding<String>, _ field: Field, _ keyboard: UIKeyboardType = .default) -> some View {
        TextField(title, text: text).focused($focus, equals: field).keyboardType(keyboard).textFieldStyle(.roundedBorder).submitLabel(.next)
    }
}
