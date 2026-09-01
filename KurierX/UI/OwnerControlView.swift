import SwiftUI
import FirebaseFirestore
import CryptoKit
import UIKit

struct OwnerControlView: View {
    @EnvironmentObject var session: SessionStore
    @State private var users:[AdminUser]=[]
    @State private var keys:[AdminKey]=[]
    @State private var generated=""
    @State private var selectedUser:AdminUser?
    @State private var deleteKey:AdminKey?
    @State private var userListener:ListenerRegistration?
    @State private var keyListener:ListenerRegistration?

    var body: some View {
        ScrollView {
            VStack(spacing:14) {
                HStack(alignment:.top){VStack(alignment:.leading,spacing:4){Text("KurierX\nControl").font(.system(size:34,weight:.black,design:.rounded));Text("Пользователи, лицензии\nи устройства").foregroundStyle(.secondary)};Spacer();Button{Task{await session.leaveOwnerToActivation()}}label:{Image(systemName:"rectangle.portrait.and.arrow.right").font(.title2).padding(12).background(Color.kxGreen.opacity(0.25),in:RoundedRectangle(cornerRadius:12))}}
                KXCard { VStack(spacing:10){Button{createKey()}label:{Label("Создать ключ",systemImage:"key.fill").frame(maxWidth:.infinity)}.buttonStyle(.borderedProminent).tint(Color.kxGreen).controlSize(.large);if !generated.isEmpty{HStack{Text(generated).font(.system(.body,design:.monospaced)).bold();Spacer();Button{UIPasteboard.general.string=generated}label:{Image(systemName:"doc.on.doc")}}} } }
                KXHeader(title:"Ключи",subtitle:"\(keys.count) всего")
                KXCard { VStack(spacing:0){ForEach(keys){key in HStack(spacing:10){VStack(alignment:.leading,spacing:3){Text(key.display).font(.system(.body,design:.monospaced)).lineLimit(1);Text(key.status).font(.caption).foregroundStyle(key.status=="UNUSED" ? Color.kxGreen:.secondary)};Spacer();Button{UIPasteboard.general.string=key.display}label:{Image(systemName:"doc.on.doc")};if key.status=="UNUSED"{Button(role:.destructive){deleteKey=key}label:{Image(systemName:"trash")}}}.padding(.vertical,10);if key.id != keys.last?.id{Divider()}}} }
                KXHeader(title:"Пользователи",subtitle:"\(users.count) зарегистрировано")
                ForEach(users){u in Button{selectedUser=u}label:{KXCard{HStack(spacing:12){ZStack{Circle().fill(statusColor(u.status).opacity(0.16));Image(systemName:"person.fill").foregroundStyle(statusColor(u.status))}.frame(width:46,height:46);VStack(alignment:.leading,spacing:4){Text("\(u.firstName) \(u.lastName)").font(.headline).foregroundStyle(.primary);Text("#\(u.courierID) · \(u.status)").font(.caption).foregroundStyle(.secondary);if !u.deviceID.isEmpty{Text("Device: \(String(u.deviceID.prefix(12)))…").font(.caption2).foregroundStyle(.tertiary)}};Spacer();Image(systemName:"chevron.right").foregroundStyle(.tertiary)}}}.buttonStyle(.plain)}
            }.padding(18).padding(.bottom,20)
        }.background(Color.kxBackground.ignoresSafeArea()).navigationBarTitleDisplayMode(.inline).onAppear(perform:load).onDisappear{userListener?.remove();keyListener?.remove()}.sheet(item:$selectedUser){UserAdminSheet(user:$0)}.alert("Удалить ключ?",isPresented:Binding(get:{deleteKey != nil},set:{if !$0{deleteKey=nil}})){Button("Удалить",role:.destructive){if let k=deleteKey{Firestore.firestore().collection("activation_keys").document(k.id).delete();deleteKey=nil}};Button("Отмена",role:.cancel){deleteKey=nil}}
    }
    private func statusColor(_ s:String)->Color{switch s{case "ACTIVE":return .kxGreen;case "FROZEN":return .orange;case "BLACKLISTED":return .red;default:return .secondary}}
    private func load(){let db=Firestore.firestore();userListener?.remove();keyListener?.remove();userListener=db.collection("users").addSnapshotListener{snap,_ in users=snap?.documents.map{AdminUser(id:$0.documentID,data:$0.data())}.sorted{$0.firstName<$1.firstName} ?? []};keyListener=db.collection("activation_keys").addSnapshotListener{snap,_ in keys=snap?.documents.map{AdminKey(id:$0.documentID,data:$0.data())}.sorted{$0.display>$1.display} ?? []}}
    private func createKey(){let chars=Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789");func part()->String{String((0..<4).compactMap{_ in chars.randomElement()})};let key="KX-\(part())-\(part())-\(part())";let normalized=key.filter{$0.isLetter||$0.isNumber};let hash=SHA256.hash(data:Data(normalized.utf8)).map{String(format:"%02x",$0)}.joined();Firestore.firestore().collection("activation_keys").document(hash).setData(["status":"UNUSED","createdAt":FieldValue.serverTimestamp(),"createdBy":session.ownerUID,"keySuffix":String(key.suffix(4)),"displayKey":key]);generated=key;UIPasteboard.general.string=key}
}

struct AdminKey:Identifiable{let id:String;let display:String;let status:String;init(id:String,data:[String:Any]){self.id=id;display=data["displayKey"] as? String ?? "••••-\(data["keySuffix"] as? String ?? "")";status=data["status"] as? String ?? "UNKNOWN"}}
struct AdminUser:Identifiable{let id:String;var firstName:String;var lastName:String;var courierID:String;var status:String;var deviceID:String;init(id:String,data:[String:Any]){self.id=id;firstName=data["firstName"] as? String ?? "";lastName=data["lastName"] as? String ?? "";courierID=data["courierId"] as? String ?? "";status=data["status"] as? String ?? "UNKNOWN";deviceID=data["deviceId"] as? String ?? ""}}

struct UserAdminSheet: View {
    @Environment(\.dismiss) private var dismiss
    let user: AdminUser
    @State private var first = ""
    @State private var last = ""
    @State private var courier = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Профиль") {
                    TextField("Имя", text: $first)
                    TextField("Фамилия", text: $last)
                    TextField("Courier ID", text: $courier)
                }
                Section("Статус") {
                    LabeledContent("Текущий", value: user.status)
                    Button("Активировать") { updateStatus("ACTIVE") }.foregroundStyle(Color.kxGreen)
                    Button("Заморозить") { updateStatus("FROZEN") }.foregroundStyle(.orange)
                    Button("В чёрный список") { updateStatus("BLACKLISTED") }.foregroundStyle(.red)
                }
                if !user.deviceID.isEmpty {
                    Section("Устройство") { Text(user.deviceID).font(.caption).textSelection(.enabled) }
                }
                Section {
                    Button("Удалить пользователя", role: .destructive) {
                        Firestore.firestore().collection("users").document(user.id).delete()
                        dismiss()
                    }
                }
            }
            .navigationTitle("Пользователь")
            .toolbar {
                KeyboardDoneToolbar()
                ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        Firestore.firestore().collection("users").document(user.id).updateData([
                            "firstName": first,
                            "lastName": last,
                            "courierId": courier,
                            "updatedAt": FieldValue.serverTimestamp()
                        ])
                        dismiss()
                    }
                }
            }
        }
        .onAppear { first = user.firstName; last = user.lastName; courier = user.courierID }
    }

    private func updateStatus(_ status: String) {
        Firestore.firestore().collection("users").document(user.id).updateData([
            "status": status,
            "updatedAt": FieldValue.serverTimestamp()
        ])
        dismiss()
    }
}
