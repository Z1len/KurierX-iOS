import SwiftUI
import FirebaseFirestore
import CryptoKit

struct OwnerView: View {
 @State private var users:[[String:Any]]=[]; @State private var keys:[[String:Any]]=[]; @State private var generated=""; @State private var listener:ListenerRegistration?
 var body:some View { NavigationStack { List {
   Section { Button("+ Создать ключ") { createKey() }; if !generated.isEmpty { HStack { Text(generated).font(.system(.body,design:.monospaced)); Spacer(); Button { UIPasteboard.general.string=generated } label:{Image(systemName:"doc.on.doc")} } } }
   Section("Ключи") { ForEach(Array(keys.enumerated()),id:\.offset){ _,k in HStack{Text(k["displayKey"] as? String ?? (k["keySuffix"] as? String ?? "Ключ"));Spacer(); if let full=k["displayKey"] as? String { Button{UIPasteboard.general.string=full}label:{Image(systemName:"doc.on.doc")}} } } }
   Section("Пользователи") { ForEach(Array(users.enumerated()),id:\.offset){ _,u in VStack(alignment:.leading){Text("\(u["firstName"] as? String ?? "") \(u["lastName"] as? String ?? "")").bold();Text("#\(u["courierId"] as? String ?? "") · \(u["status"] as? String ?? "")").font(.caption)} } }
 }.navigationTitle("KurierX Control").onAppear{load()} } }
 func load(){ let db=Firestore.firestore(); listener=db.collection("users").addSnapshotListener{snap,_ in users=snap?.documents.map{$0.data()} ?? []}; db.collection("activation_keys").addSnapshotListener{snap,_ in keys=snap?.documents.map{$0.data()} ?? []} }
 func createKey(){ let chars=Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789"); func part()->String{String((0..<4).compactMap{_ in chars.randomElement()})}; let key="KX-\(part())-\(part())-\(part())"; let normalized=key.filter{$0.isLetter||$0.isNumber}; let hash=SHA256.hash(data:Data(normalized.utf8)).map{String(format:"%02x",$0)}.joined(); Firestore.firestore().collection("activation_keys").document(hash).setData(["status":"UNUSED","createdAt":FieldValue.serverTimestamp(),"createdBy":"dDUHublQoTccwtzPa1hmpyiDTd23","keySuffix":String(key.suffix(4)),"displayKey":key]); generated=key; UIPasteboard.general.string=key }
}
