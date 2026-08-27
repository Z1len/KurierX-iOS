import SwiftUI

struct RootView: View {
    @EnvironmentObject var session: SessionStore
    var body: some View {
        Group {
            switch session.state {
            case .loading: ProgressView("KurierX")
            case .needsFirebase: FirebaseSetupView()
            case .registration: ActivationView()
            case .active: MainShell()
            case .owner: OwnerView()
            case .frozen: BlockedView(title:"Аккаунт заморожен", text:"Обратитесь к владельцу KurierX.")
            case .revoked: BlockedView(title:"Лицензия недействительна", text:"Необходимо выполнить новую активацию.")
            }
        }.preferredColorScheme(.dark)
    }
}

struct FirebaseSetupView: View { var body: some View { ContentUnavailableView("Firebase не настроен", systemImage:"flame.fill", description:Text("Добавьте GoogleService-Info.plist в target KurierX и пересоберите приложение.")) } }
struct BlockedView: View { let title:String; let text:String; var body: some View { ContentUnavailableView(title, systemImage:"lock.fill", description:Text(text)) } }
