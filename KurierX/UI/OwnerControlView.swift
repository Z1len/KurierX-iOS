import CryptoKit
import FirebaseFirestore
import SwiftUI
import UIKit

struct OwnerControlView: View {
  @EnvironmentObject var session: SessionStore
  @State var keys: [AdminKey] = []
  @State var users: [AdminUser] = []
  @State var keyListener: ListenerRegistration?
  @State var userListener: ListenerRegistration?
  var body: some View {
    List {
      Section {
        Button("Создать ключ") { createKey() }
      } header: {
        Text("KurierX Control")
      }
      Section("Ключи") {
        ForEach(keys) { k in
          HStack {
            Text(k.display).font(.system(.body, design: .monospaced))
            Spacer()
            Text(k.status)
          }
        }
      }
      Section("Пользователи") {
        ForEach(users) { u in
          VStack(alignment: .leading) {
            Text(u.name).bold()
            Text("#\(u.courier) · \(u.status)").foregroundStyle(.secondary)
          }
        }
      }
      Section {
        Button("Выйти из OWNER", role: .destructive) {
          Task { await session.leaveOwnerToActivation() }
        }
      }
    }.navigationTitle("KurierX Control").onAppear { load() }.onDisappear {
      keyListener?.remove()
      userListener?.remove()
    }
  }
  func load() {
    let db = Firestore.firestore()
    keyListener = db.collection("activation_keys").addSnapshotListener { s, _ in
      keys = s?.documents.map { AdminKey(id: $0.documentID, data: $0.data()) } ?? []
    }
    userListener = db.collection("users").addSnapshotListener { s, _ in
      users = s?.documents.map { AdminUser(id: $0.documentID, data: $0.data()) } ?? []
    }
  }
  func createKey() {
    let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    func part() -> String { String((0..<4).compactMap { _ in chars.randomElement() }) }
    let key = "KX-\(part())-\(part())-\(part())"
    let n = key.filter { $0.isLetter || $0.isNumber }
    let h = SHA256.hash(data: Data(n.utf8)).map { String(format: "%02x", $0) }.joined()
    Firestore.firestore().collection("activation_keys").document(h).setData([
      "status": "UNUSED", "displayKey": key, "createdAt": FieldValue.serverTimestamp(),
    ])
    UIPasteboard.general.string = key
  }
}
struct AdminKey: Identifiable {
  let id: String, display: String, status: String
  init(id: String, data: [String: Any]) {
    self.id = id
    display = data["displayKey"] as? String ?? "••••"
    status = data["status"] as? String ?? "UNKNOWN"
  }
}
struct AdminUser: Identifiable {
  let id: String, name: String, courier: String, status: String
  init(id: String, data: [String: Any]) {
    self.id = id
    name = ((data["firstName"] as? String ?? "") + " " + (data["lastName"] as? String ?? ""))
    courier = data["courierId"] as? String ?? ""
    status = data["status"] as? String ?? "UNKNOWN"
  }
}
