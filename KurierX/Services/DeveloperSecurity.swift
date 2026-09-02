import CryptoKit
import Foundation
import LocalAuthentication

@MainActor final class DeveloperSecurity: ObservableObject {
  @Published var unlocked = false
  @Published var error = ""
  private let pinKey = "kx.dev.pin.v6"
  private let faceKey = "kx.dev.face.v6"
  var hasPIN: Bool { UserDefaults.standard.string(forKey: pinKey) != nil }
  var faceEnabled: Bool {
    get { UserDefaults.standard.bool(forKey: faceKey) }
    set { UserDefaults.standard.set(newValue, forKey: faceKey) }
  }
  func setPIN(_ p: String, _ p2: String) -> Bool {
    let a = p.filter(\.isNumber)
    guard a.count >= 4 else {
      error = "PIN должен содержать минимум 4 цифры"
      return false
    }
    guard a == p2.filter(\.isNumber) else {
      error = "PIN-коды не совпадают"
      return false
    }
    UserDefaults.standard.set(hash(a), forKey: pinKey)
    error = ""
    unlocked = true
    return true
  }
  func verify(_ p: String) {
    guard let s = UserDefaults.standard.string(forKey: pinKey) else {
      error = "PIN ещё не создан"
      return
    }
    if hash(p.filter(\.isNumber)) == s {
      unlocked = true
      error = ""
    } else {
      error = "Неверный PIN"
    }
  }
  func reset() {
    UserDefaults.standard.removeObject(forKey: pinKey)
    UserDefaults.standard.removeObject(forKey: faceKey)
    unlocked = false
    error = ""
  }
  func biometric() async {
    let c = LAContext()
    var e: NSError?
    guard c.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &e) else {
      error = "Face ID недоступен"
      return
    }
    do {
      if try await c.evaluatePolicy(
        .deviceOwnerAuthenticationWithBiometrics, localizedReason: "Разблокировать Developer Mode")
      {
        unlocked = true
        error = ""
      }
    } catch { self.error = "Face ID не подтверждён" }
  }
  private func hash(_ s: String) -> String {
    SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}
