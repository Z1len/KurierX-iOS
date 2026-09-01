import SwiftUI
import SwiftData
import PhotosUI
import UIKit
import Charts

// MARK: - STATS
struct StatsView: View {
    @Query(sort: \Shift.date, order: .reverse) private var shifts: [Shift]
    @Query(sort: \Route.date, order: .reverse) private var routes: [Route]
    @Query private var finances: [FinancialEntry]
    @Query private var fuel: [FuelEntry]
    @Query private var advances: [AdvanceEntry]
    @State private var period: Period = .month
    enum Period: String, CaseIterable, Identifiable { case day="День", week="Неделя", month="Месяц", custom="Период", all="Всё"; var id:String{rawValue} }

    private var filteredRoutes: [Route] { routes.filter { $0.deletedAt == nil && included($0.date) } }
    private var filteredShifts: [Shift] { shifts.filter { $0.deletedAt == nil && included($0.date) } }
    private var orders: Int { filteredRoutes.reduce(0){$0+$1.factualOrders} }
    private var rings: Int { filteredRoutes.count }
    private var minutes: Int { filteredShifts.reduce(0){$0+$1.durationMinutes} }
    private var base: Int64 { filteredRoutes.reduce(0){$0+EarningsService.routeGross($1)} }
    private var tips: Int64 { filteredRoutes.reduce(0){$0+$1.tipsHellers} }
    private var extras: Int64 { finances.filter{$0.deletedAt==nil && included($0.date)}.reduce(0){$0+($1.kind.positive ? $1.amountHellers : -$1.amountHellers)} }
    private var diesel: Int64 { fuel.filter{$0.deletedAt==nil && included($0.date)}.reduce(0){$0+$1.amountHellers} }
    private var advance: Int64 { advances.filter{$0.deletedAt==nil && included($0.date)}.reduce(0){$0+$1.amountHellers} }
    private var total: Int64 { base+tips+extras-diesel-advance }

    private func included(_ date: Date) -> Bool {
        let c=Calendar.current; let now=Date.now
        switch period {
        case .day:return c.isDateInToday(date)
        case .week:return c.dateInterval(of:.weekOfYear,for:now)?.contains(date) ?? true
        case .month:return date.monthKey==now.monthKey
        case .custom:return date.monthKey==now.monthKey
        case .all:return true
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing:16) {
                KXHeader(title:"Статистика",subtitle:"Удалённые трассы исключаются из расчётов до восстановления из корзины.").padding(.top,10)
                ScrollView(.horizontal,showsIndicators:false){HStack{ForEach(Period.allCases){p in Button(p.rawValue){period=p}.buttonStyle(.bordered).tint(period==p ? Color.kxPurple : .gray).background(period==p ? Color.kxPurple.opacity(0.6):Color.clear,in:RoundedRectangle(cornerRadius:10))}}}
                KXCard {
                    VStack(alignment:.leading,spacing:10){
                        Text("\(orders) заказов").font(.system(size:34,weight:.bold,design:.rounded))
                        Text("\(rings) колечек · \(filteredShifts.count) смен · \(minutesLabel(minutes))").foregroundStyle(.secondary)
                        Divider()
                        Text("OT \(filteredRoutes.filter{$0.type == .ot}.count) · Region \(filteredRoutes.filter{$0.type == .region}.count) · Express \(filteredRoutes.filter{$0.type == .express}.count)")
                        Text("Базовая оплата \(moneyKc(base))")
                        Text("Region / чаевые \(moneyKc(tips))")
                        Text("По трассам \(moneyKc(base+tips))").font(.title2.bold())
                    }
                }
                LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:12){
                    metric(moneyKc(orders>0 ? total/Int64(orders):0),"Kč / заказ")
                    metric(moneyKc(minutes>0 ? total*60/Int64(minutes):0),"Kč / час")
                    metric(String(format:"%.2f",minutes>0 ? Double(orders)*60/Double(minutes):0),"Заказов / час")
                    metric(String(format:"%.2f",minutes>0 ? Double(rings)*60/Double(minutes):0),"Колечек / час")
                    metric(moneyKc(orders>0 ? tips/Int64(orders):0),"Чаевые / заказ")
                    metric(moneyKc(total),"Итого")
                }
                KXCard { VStack(alignment:.leading,spacing:9){Text("Финансы за выбранный период").font(.title2.bold());LabeledContent("Трассы",value:moneyKc(base));LabeledContent("Чаевые",value:moneyKc(tips));LabeledContent("Бонусы / штрафы",value:moneyKc(extras));LabeledContent("Дизель",value:"− \(moneyKc(diesel))");LabeledContent("Авансы",value:"− \(moneyKc(advance))");Divider();LabeledContent("Итог",value:moneyKc(total)).font(.headline)} }
                if !filteredRoutes.isEmpty { Chart(filteredRoutes.prefix(30)){r in BarMark(x:.value("Дата",r.date,unit:.day),y:.value("Kč",Double(EarningsService.routeGross(r))/100)).foregroundStyle(Color.kxGreen)}.frame(height:180).padding().background(Color.kxSurface,in:RoundedRectangle(cornerRadius:20)) }
            }.padding(.horizontal,18).padding(.bottom,22)
        }.background(Color.kxBackground.ignoresSafeArea()).navigationBarHidden(true)
    }
    private func metric(_ value:String,_ title:String)->some View{KXCard{VStack(alignment:.leading,spacing:5){Text(value).font(.title2.bold());Text(title).font(.caption).foregroundStyle(.secondary)}}}
}

// MARK: - SCANNER
struct ScannerView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Shift.date, order: .reverse) private var shifts:[Shift]
    @State private var mode: ScanMode = .route
    @State private var routeType: RouteType = .ot
    @State private var orders=""; @State private var tips=""; @State private var km=""; @State private var gross=""
    @State private var photos:[PhotosPickerItem]=[]; @State private var recognized=""; @State private var busy=false; @State private var message=""
    enum ScanMode:String,CaseIterable,Identifiable{case route="Трасса",customers="Заказники",stats="Статистика курьера",finance="Бонусы / штрафы";var id:String{rawValue};var subtitle:String{switch self{case .route:return "Фото сообщения после завершения трассы";case .customers:return "Одна или несколько фотографий списка клиентов";case .stats:return "Снимок накопительной статистики";case .finance:return "Бонус / компенсация или штраф"}}}
    private var activeShift:Shift?{shifts.first{$0.deletedAt==nil && $0.status == .active}}

    var body: some View {
        ScrollView{
            VStack(spacing:14){
                KXHeader(title:"Сканер",subtitle:"Каждый тип экрана распознаётся отдельно — так надёжнее.").padding(.top,10)
                ForEach(ScanMode.allCases){m in Button{mode=m}label:{VStack(alignment:.leading,spacing:5){Text(m.rawValue).font(.headline);Text(m.subtitle).font(.caption).foregroundStyle(mode==m ? Color.white.opacity(0.8):.secondary)}.frame(maxWidth:.infinity,alignment:.leading).padding(16).background(mode==m ? Color.kxPurple : Color.kxSurface2,in:RoundedRectangle(cornerRadius:16))}.buttonStyle(.plain)}
                HStack(spacing:10){PhotosPicker(selection:$photos,maxSelectionCount:8,matching:.images){Text("Галерея").frame(maxWidth:.infinity)}.buttonStyle(.borderedProminent).tint(Color.kxGreen);Button("Очистить"){photos=[];recognized=""}.buttonStyle(.bordered).frame(maxWidth:.infinity)}
                if mode == .route {
                    Text("Проверка трассы").font(.title2.bold()).frame(maxWidth:.infinity,alignment:.leading)
                    Text("Тип трассы всегда выбирается вручную.").foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading)
                    Picker("Тип",selection:$routeType){ForEach(RouteType.allCases){Text($0.rawValue).tag($0)}}.pickerStyle(.segmented)
                    TextField("Количество заказов",text:$orders).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                    TextField("Чаевые Kč",text:$tips).keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                    TextField("Километраж",text:$km).keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                    TextField("Итог по трассе Kč",text:$gross).keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                    Button("Сохранить закрытую трассу"){saveRoute()}.buttonStyle(.borderedProminent).tint(Color.kxGreen).controlSize(.large).frame(maxWidth:.infinity).disabled(activeShift==nil)
                    if activeShift==nil{Text("Сначала начни смену на Главной.").font(.footnote).foregroundStyle(.orange)}
                } else if mode == .finance {
                    HStack{Button("Бонус / компенсация"){saveFinance(.bonus)}.buttonStyle(.borderedProminent).tint(Color.kxGreen);Button("Штраф"){saveFinance(.penalty)}.buttonStyle(.bordered).tint(.red)}
                } else {
                    Button("Распознать выбранные фото"){Task{await recognize()}}.buttonStyle(.borderedProminent).tint(Color.kxGreen).frame(maxWidth:.infinity).disabled(photos.isEmpty||busy)
                }
                if !recognized.isEmpty { KXCard{VStack(alignment:.leading,spacing:7){Text("Распознано").font(.headline);Text(recognized).font(.caption).textSelection(.enabled)}} }
                if !message.isEmpty{Text(message).foregroundStyle(Color.kxGreen).frame(maxWidth:.infinity,alignment:.leading)}
            }.padding(.horizontal,18).padding(.bottom,22)
        }.background(Color.kxBackground.ignoresSafeArea()).navigationBarHidden(true).scrollDismissesKeyboard(.interactively).toolbar{KeyboardDoneToolbar()}
        .onChange(of:photos){_,_ in Task{await recognize()}}
    }

    private func saveRoute(){guard let shift=activeShift else{return};let seq=(try? context.fetch(FetchDescriptor<Route>()).filter{$0.shiftID==shift.id}.count) ?? 0;let o=Int(orders) ?? 0;let t=Int64((Double(tips.replacingOccurrences(of:",",with:".")) ?? 0)*100);let g=Int64((Double(gross.replacingOccurrences(of:",",with:".")) ?? 0)*100);let r=Route(shiftID:shift.id,sequence:seq+1,type:routeType,warehouse:shift.warehouse,plannedOrders:o,factualOrders:o,tipsHellers:t,distanceKm:Double(km.replacingOccurrences(of:",",with:".")),grossHellers:g);context.insert(r);context.insert(AuditEntry(kind:.create,title:"Добавлена трасса",details:"\(routeType.rawValue), \(o) заказов"));try? context.save();orders="";tips="";km="";gross="";message="Трасса сохранена"}
    private func saveFinance(_ kind:FinancialKind){let amount=Int64((Double(tips.replacingOccurrences(of:",",with:".")) ?? 0)*100);context.insert(FinancialEntry(kind:kind,amountHellers:amount,note:recognized));try? context.save();message="Операция сохранена"}
    private func recognize() async {busy=true;defer{busy=false};var blocks:[String]=[];for item in photos{guard let data=try? await item.loadTransferable(type:Data.self),let image=UIImage(data:data),let text=try? await OCRService.recognize(image) else{continue};blocks.append(text)};recognized=blocks.joined(separator:"\n\n---\n\n")}
}

// MARK: - MORE
struct MoreView: View {
    @EnvironmentObject var session:SessionStore
    let isOwner:Bool
    var body: some View {
        ScrollView{
            VStack(spacing:10){
                HStack{Text("Ещё").font(.system(size:34,weight:.black,design:.rounded));Spacer();NavigationLink{SettingsView()}label:{Image(systemName:"gearshape.fill").font(.title).foregroundStyle(Color.kxGreen)}}.padding(.top,12).padding(.bottom,6)
                NavigationLink{AccountView()}label:{KXSectionRow(title:"Аккаунт",subtitle:"Профиль, лицензия и устройство",icon:"person.crop.circle.fill")}.buttonStyle(.plain)
                if isOwner{NavigationLink{OwnerControlView()}label:{KXSectionRow(title:"KurierX Control",subtitle:"Ключи, пользователи и блокировки",icon:"person.badge.shield.checkmark.fill")}.buttonStyle(.plain)}
                Divider().padding(.vertical,3)
                NavigationLink{ClientsView()}label:{KXSectionRow(title:"Клиенты",subtitle:"Все клиенты и история",icon:"person")}.buttonStyle(.plain)
                NavigationLink{ShiftsView()}label:{KXSectionRow(title:"Смены",subtitle:"Все смены и их параметры",icon:"calendar")}.buttonStyle(.plain)
                NavigationLink{FinanceView(filter:.positive)}label:{KXSectionRow(title:"Бонусы и компенсации",subtitle:"Бонусы, компенсации и доплаты",icon:"gift")}.buttonStyle(.plain)
                NavigationLink{FinanceView(filter:.penalty)}label:{KXSectionRow(title:"Штрафы",subtitle:"Просмотр и добавление штрафов",icon:"exclamationmark.triangle")}.buttonStyle(.plain)
                NavigationLink{FuelView()}label:{KXSectionRow(title:"Дизель и авторасходы",subtitle:"Расходы на топливо и поездки",icon:"fuelpump")}.buttonStyle(.plain)
                NavigationLink{AdvancesView()}label:{KXSectionRow(title:"Авансы",subtitle:"Полученные авансы и возвраты",icon:"wallet.pass")}.buttonStyle(.plain)
                Divider().padding(.vertical,3)
                NavigationLink{SalaryView()}label:{KXSectionRow(title:"Зарплата",subtitle:"Выплаты и сверка с фактом",icon:"banknote")}.buttonStyle(.plain)
                NavigationLink{GoalsView()}label:{KXSectionRow(title:"Цели",subtitle:"Планирование и цели",icon:"scope")}.buttonStyle(.plain)
                Divider().padding(.vertical,3)
                NavigationLink{BackupView()}label:{KXSectionRow(title:"Резервные копии",subtitle:"Создание и восстановление резервных копий",icon:"externaldrive")}.buttonStyle(.plain)
                NavigationLink{AuditView()}label:{KXSectionRow(title:"Журнал",subtitle:"История действий в приложении",icon:"doc.text")}.buttonStyle(.plain)
                NavigationLink{TrashView()}label:{KXSectionRow(title:"Корзина",subtitle:"Удалённые данные и восстановление",icon:"trash")}.buttonStyle(.plain)
                Divider().padding(.vertical,3)
                NavigationLink{DeveloperView()}label:{KXSectionRow(title:"Расширенный режим",subtitle:"Доступ к дополнительным возможностям",icon:"shield")}.buttonStyle(.plain)
                NavigationLink{SettingsView()}label:{KXSectionRow(title:"Настройки",subtitle:"Параметры приложения",icon:"gearshape")}.buttonStyle(.plain)
                HStack(spacing:10){NavigationLink{MileageView()}label:{Text("Километраж").frame(maxWidth:.infinity)}.buttonStyle(.bordered);NavigationLink{TutorialView()}label:{Text("Обучение / Как пользоваться").frame(maxWidth:.infinity)}.buttonStyle(.borderedProminent).tint(Color.kxGreen)}.padding(.top,6)
            }.padding(.horizontal,18).padding(.bottom,22)
        }.background(Color.kxBackground.ignoresSafeArea()).navigationBarHidden(true)
    }
}
