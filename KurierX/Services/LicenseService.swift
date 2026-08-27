import Foundation
import FirebaseAuth
import FirebaseFirestore
import CryptoKit
import UIKit
import FirebaseCore

@MainActor final class SessionStore: ObservableObject {
    @Published var state: State = .loading
    @Published var profile: UserProfile?
    enum State: Equatable { case loading, needsFirebase, registration, active, frozen, revoked, owner }
    private var listener: ListenerRegistration?
    private let ownerUID = "dDUHublQoTccwtzPa1hmpyiDTd23"

    init() { Task { await bootstrap() } }

    func bootstrap() async {
        guard FirebaseApp.app() != nil else { state = .needsFirebase; return }
        if Auth.auth().currentUser == nil {
            do { _ = try await Auth.auth().signInAnonymously() } catch { state = .registration; return }
        }
        guard let uid = Auth.auth().currentUser?.uid else { state = .registration; return }
        if uid == ownerUID { state = .owner; return }
        listen(uid: uid)
    }

    private func listen(uid: String) {
        listener?.remove()
        listener = Firestore.firestore().collection("users").document(uid).addSnapshotListener { [weak self] snap, _ in
            guard let self else { return }
            Task { @MainActor in
                guard let data = snap?.data() else { self.state = .registration; return }
                self.profile = UserProfile(data: data)
                switch (data["status"] as? String ?? "") {
                case "ACTIVE": self.state = .active
                case "FROZEN": self.state = .frozen
                default: self.state = .revoked
                }
            }
        }
    }

    func activate(firstName: String, lastName: String, courierID: String, key: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw LicenseError.noUser }
        let normalized = key.uppercased().filter { $0.isLetter || $0.isNumber }
        guard normalized.hasPrefix("KX"), normalized.count >= 14 else { throw LicenseError.badFormat }
        let hash = SHA256.hash(data: Data(normalized.utf8)).map { String(format: "%02x", $0) }.joined()
        let db = Firestore.firestore(); let keyRef = db.collection("activation_keys").document(hash)
        let deviceID = Self.deviceID(); let userRef = db.collection("users").document(uid); let deviceRef = db.collection("devices").document(deviceID)
        _ = try await db.runTransaction { tx, errorPointer -> Any? in
            do {
                let keyDoc = try tx.getDocument(keyRef)
                guard keyDoc.exists, keyDoc.data()?["status"] as? String == "UNUSED" else { throw LicenseError.invalidKey }
                let now = FieldValue.serverTimestamp()
                tx.updateData(["status":"USED", "userId":uid, "deviceId":deviceID, "activatedAt":now], forDocument:keyRef)
                tx.setData(["uid":uid,"firstName":firstName,"lastName":lastName,"courierId":courierID,"deviceId":deviceID,"activationKeyId":hash,"status":"ACTIVE","role":"USER","createdAt":now,"updatedAt":now], forDocument:userRef)
                tx.setData(["uid":uid,"deviceId":deviceID,"platform":"IOS","manufacturer":"Apple","model":UIDevice.current.model,"androidVersion":"iOS \(UIDevice.current.systemVersion)","appVersion":Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0","status":"ACTIVE","createdAt":now,"lastSeenAt":now], forDocument:deviceRef)
                return nil
            } catch { errorPointer?.pointee = error as NSError; return nil }
        }
        listen(uid: uid)
    }

    func ownerLogin(email: String, password: String) async throws {
        listener?.remove(); try? Auth.auth().signOut()
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        guard result.user.uid == ownerUID else { try? Auth.auth().signOut(); throw LicenseError.notOwner }
        state = .owner
    }

    static func deviceID() -> String {
        let seed = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        return SHA256.hash(data: Data(("IOS|" + seed).utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

struct UserProfile { let firstName:String; let lastName:String; let courierID:String
    init(data:[String:Any]) { firstName=data["firstName"] as? String ?? ""; lastName=data["lastName"] as? String ?? ""; courierID=data["courierId"] as? String ?? "" }
}
enum LicenseError: LocalizedError { case noUser,badFormat,invalidKey,notOwner
    var errorDescription:String? { switch self { case .noUser:return "Нет Firebase-сессии"; case .badFormat:return "Ключ неверного формата"; case .invalidKey:return "Ключ недействителен или уже использован"; case .notOwner:return "Нет OWNER-доступа" } }
}
