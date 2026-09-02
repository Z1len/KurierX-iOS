import SwiftUI

struct RootView: View {
  @EnvironmentObject var session: SessionStore
  var body: some View {
    ZStack {
      Color.kxBackground.ignoresSafeArea()
      switch session.state {
      case .loading: ProgressView("KurierX")
      case .needsFirebase: ContentUnavailableView("Firebase не настроен", systemImage: "flame.fill")
      case .registration: ActivationView()
      case .active: MainShell(isOwner: false)
      case .owner: MainShell(isOwner: true)
      case .frozen: ContentUnavailableView("Аккаунт заморожен", systemImage: "lock.fill")
      case .revoked: ContentUnavailableView("Лицензия недействительна", systemImage: "lock.fill")
      }
    }.preferredColorScheme(.dark).tint(Color.kxGreen)
  }
}
