import SwiftUI
import UIKit
import SwiftData
import Charts
import PhotosUI

struct MainShell: View {
    @State private var tab: Tab = .home
    enum Tab: Hashable { case home, calendar, stats, scanner, more }

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { HomeView(openScanner: { tab = .scanner }) }
                .tabItem { Label("Главная", systemImage: "house") }.tag(Tab.home)
            NavigationStack { CalendarViewKX() }
                .tabItem { Label("Календарь", systemImage: "calendar") }.tag(Tab.calendar)
            NavigationStack { StatsView() }
                .tabItem { Label("Статистика", systemImage: "chart.bar.xaxis") }.tag(Tab.stats)
            NavigationStack { ScannerView() }
                .tabItem { Label("Сканер", systemImage: "qrcode.viewfinder") }.tag(Tab.scanner)
            NavigationStack { MoreView() }
                .tabItem { Label("Ещё", systemImage: "ellipsis") }.tag(Tab.more)
        }
        .toolbarBackground(Color.kxSurface, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}

// MARK: - HOME
struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Shift.date, order: .reverse) private var shifts: [Shift]
    @Query(sort: \Route.date, order: .reverse) private var routes: [Route]
    @Query private var finances: [FinancialEntry]
    @Query private var fuel: [FuelEntry]
    @Query private var advances: [AdvanceEntry]
    @Query private var goals: [Goal]
    let openScanner: () -> Void
    @State private var showStartShift = false
    @State private var showAddRoute = false

    private var activeShift: Shift? { shifts.first { $0.deletedAt == nil && $0.status == .active } }
    private var activeRoutes: [Route] { routes.filter { $0.deletedAt == nil } }
    private var factualOrders: Int { activeRoutes.reduce(0) { $0 + $1.factualOrders } }
    private var tips: Int64 { activeRoutes.reduce(0) { $0 + $1.tipsHellers } }
    private var routeGross: Int64 { activeRoutes.reduce(0) { $0 + $1.grossHellers } }
    private var net: Int64 {
        let fin = finances.filter { $0.deletedAt == nil }.reduce(Int64(0)) { $0 + ($1.kind == .bonus ? $1.amountHellers : -$1.amountHellers) }
        let diesel = fuel.filter { $0.deletedAt == nil }.reduce(Int64(0)) { $0 + $1.amountHellers }
        let adv = advances.filter { $0.deletedAt == nil }.reduce(Int64(0)) { $0 + $1.amountHellers }
        return routeGross + tips + fin - diesel - adv
    }
    private var currentGoal: Goal? { goals.first { $0.month == Date().monthKey } }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack(spacing: 11) {
                    ZStack { RoundedRectangle(cornerRadius: 14).fill(Color.kxGreen.opacity(0.18)); Image(systemName: "shippingbox.fill").foregroundStyle(Color.kxGreen).font(.title2) }.frame(width: 48, height: 48)
                    HStack(spacing: 0) { Text("Kurier").font(.system(size: 31, weight: .black, design: .rounded)); Text("X").font(.system(size: 31, weight: .black, design: .rounded)).foregroundStyle(Color.kxGreen) }
                    Spacer()
                }

                if let goal = currentGoal, goal.targetOrders > 0 {
                    GoalProgressCard(current: factualOrders, target: goal.targetOrders)
                }

                KXCard(content: VStack(alignment: .leading, spacing: 7) {
                    Text("Заработок по обработанным трассам").font(.caption).foregroundStyle(.secondary)
                    Text(moneyKc(net)).font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("\(factualOrders) фактических заказов · чаевые \(moneyKc(tips))").foregroundStyle(.secondary)
                    Text("Итог учитывает трассы, бонусы, штрафы, дизель и авансы.").font(.caption).foregroundStyle(.secondary)
                })

                if let shift = activeShift {
                    ActiveShiftCardIOS(shift: shift, routes: activeRoutes.filter { $0.shiftID == shift.id }, openScanner: openScanner) {
                        shift.endedAt = .now; shift.status = .complete
                        try? context.save()
                    }
                } else {
                    KXCard(content: VStack(alignment: .leading, spacing: 11) {
                        Text("Смена не начата").font(.title3.bold())
                        Text("Рабочее время начнётся после входа в очередь.").foregroundStyle(.secondary)
                        Button("Přihlásit se do fronty") { showStartShift = true }.buttonStyle(.borderedProminent).tint(Color.kxGreen).frame(maxWidth: .infinity)
                    })
                }

                if !activeRoutes.isEmpty {
                    KXHeader(title: "Закрытые трассы")
                    ForEach(activeRoutes.prefix(8)) { route in RouteSummaryCard(route: route) }
                }
            }.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 28)
        }
        .background(Color.kxBackground.ignoresSafeArea())
        .navigationBarHidden(true)
        .sheet(isPresented: $showStartShift) { ShiftEditorView(existing: nil) }
        .sheet(isPresented: $showAddRoute) { EmptyView() }
    }
}

struct GoalProgressCard: View {
    let current: Int; let target: Int
    var body: some View {
        KXCard(content: VStack(spacing: 7) {
            HStack { Text("\(current)").font(.headline).foregroundStyle(Color.kxGreen); Text("/ \(target)"); Spacer(); Text("Цель: \(target) заказов").font(.caption.bold()) }
            ProgressView(value: Double(current), total: Double(max(1, target))).tint(Color.kxGreen)
            let remaining = max(0, target-current)
            Text(remaining == 0 ? "Цель выполнена ✓" : "Осталось \(remaining) заказов").font(.caption).foregroundStyle(remaining == 0 ? Color.kxGreen : .secondary)
        })
    }
}

struct ActiveShiftCardIOS: View {
    let shift: Shift; let routes: [Route]; let openScanner: () -> Void; let close: () -> Void
    var completedRings: Int { routes.reduce(0) { $0 + $1.type.rings } }
    var body: some View {
        KXCard(content: VStack(spacing: 12) {
            HStack { VStack(alignment: .leading) { Text("Смена активна").font(.title3.bold()); Text("Старт \(shift.startedAt?.formatted(date: .omitted, time: .shortened) ?? "—")").foregroundStyle(.secondary) }; Spacer(); Text(shift.plannedRings > 0 ? "\(completedRings)/\(shift.plannedRings) K" : "\(completedRings) K").font(.headline).padding(.horizontal, 12).padding(.vertical, 7).background(Color.kxGreen.opacity(0.16), in: RoundedRectangle(cornerRadius: 12)) }
            if shift.plannedRings > 0 { ProgressView(value: Double(completedRings), total: Double(max(1, shift.plannedRings))).tint(Color.kxGreen) }
            Button("Добавить закрытую трассу", action: openScanner).buttonStyle(.borderedProminent).tint(Color.kxGreen).frame(maxWidth: .infinity)
            Button("Закрыть текущую смену", action: close).buttonStyle(.bordered).frame(maxWidth: .infinity)
        })
    }
}

struct RouteSummaryCard: View {
    let route: Route
    var body: some View {
        KXCard(content: VStack(alignment: .leading, spacing: 5) {
            HStack { Text("✓ \(route.type.rawValue) · \(route.warehouse.rawValue)").font(.headline); Spacer(); if route.grossHellers != 0 { Text(moneyKc(route.grossHellers)).bold() } }
            Text("\(route.type.rings) колечко · \(route.factualOrders) заказов\(route.distanceKm.map { " · \(String(format: "%.1f", $0)) км" } ?? "")").font(.caption).foregroundStyle(.secondary)
            if route.tipsHellers > 0 { Text("Чаевые \(moneyKc(route.tipsHellers))").font(.caption).foregroundStyle(Color.kxGreen) }
        })
    }
}

// MARK: - CALENDAR
struct CalendarViewKX: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \CalendarPlan.date) private var plans: [CalendarPlan]
    @Query(sort: \Shift.date) private var shifts: [Shift]
    @State private var month = Date()
    @State private var showAdd = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)
    private var monthInterval: DateInterval { Calendar.current.dateInterval(of: .month, for: month)! }
    private var days: [Date?] {
        let cal = Calendar.current; let start = monthInterval.start
        let weekday = (cal.component(.weekday, from: start) + 5) % 7
        let count = cal.range(of: .day, in: .month, for: month)?.count ?? 30
        return Array(repeating: nil, count: weekday) + (0..<count).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                KXHeader(title: "Календарь", subtitle: "План смен и колечек")
                KXCard(content: VStack(spacing: 12) {
                    HStack { Button { month = Calendar.current.date(byAdding: .month, value: -1, to: month)! } label: { Image(systemName: "chevron.left.circle.fill").font(.title2) }; Spacer(); Text(month.formatted(.dateTime.month(.wide).year())).font(.title2.bold()).textCase(nil); Spacer(); Button { month = Calendar.current.date(byAdding: .month, value: 1, to: month)! } label: { Image(systemName: "chevron.right.circle.fill").font(.title2) } }
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(["ПН","ВТ","СР","ЧТ","ПТ","СБ","ВС"], id: \.self) { Text($0).font(.caption2.bold()).foregroundStyle(.secondary) }
                        ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                            if let day { CalendarCell(day: day, plan: plans.first { Calendar.current.isDate($0.date, inSameDayAs: day) }, shift: shifts.first { $0.deletedAt == nil && Calendar.current.isDate($0.date, inSameDayAs: day) }) }
                            else { Color.clear.frame(height: 70) }
                        }
                    }
                })
                Button("Добавить / изменить день") { showAdd = true }.buttonStyle(.borderedProminent).tint(Color.kxGreen).frame(maxWidth: .infinity)
            }.padding(16).padding(.bottom, 20)
        }.background(Color.kxBackground.ignoresSafeArea()).navigationBarHidden(true).sheet(isPresented: $showAdd) { CalendarPlanEditor() }
    }
}

struct CalendarCell: View {
    let day: Date; let plan: CalendarPlan?; let shift: Shift?
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(day.formatted(.dateTime.day())).font(.caption.bold())
            if let plan { Text(String(format: "%d:%02d", plan.startMinutes/60, plan.startMinutes%60)).font(.caption2).foregroundStyle(Color.kxGreen); Text("\(plan.plannedRings)K").font(.caption2.bold()) }
            else if let shift { Text(shift.startedAt?.formatted(date: .omitted, time: .shortened) ?? "Смена").font(.caption2).foregroundStyle(.secondary); if shift.plannedRings > 0 { Text("\(shift.plannedRings)K").font(.caption2.bold()) } }
            Spacer(minLength: 0)
        }.padding(6).frame(maxWidth: .infinity, minHeight: 70, alignment: .topLeading)
            .background((plan != nil || shift != nil) ? Color.kxGreen.opacity(0.14) : Color.kxSurface2.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Calendar.current.isDateInToday(day) ? Color.kxGreen : Color.white.opacity(0.05), lineWidth: Calendar.current.isDateInToday(day) ? 2 : 1))
    }
}

// MARK: - STATS
struct StatsView: View {
    @Query private var shifts: [Shift]
    @Query private var routes: [Route]
    @Query private var finances: [FinancialEntry]
    @State private var period: Period = .month
    enum Period: String, CaseIterable, Identifiable { case day="День", week="Неделя", month="Месяц", year="Год", all="Всё"; var id:String{rawValue} }
    private var start: Date? { let c=Calendar.current; switch period { case .day:return c.startOfDay(for:.now); case .week:return c.dateInterval(of:.weekOfYear,for:.now)?.start; case .month:return c.dateInterval(of:.month,for:.now)?.start; case .year:return c.dateInterval(of:.year,for:.now)?.start; case .all:return nil } }
    private var filteredRoutes:[Route] { routes.filter { $0.deletedAt == nil && (start == nil || $0.date >= start!) } }
    private var filteredShifts:[Shift] { shifts.filter { $0.deletedAt == nil && (start == nil || $0.date >= start!) } }
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                KXHeader(title:"Статистика", subtitle:"Заказы, чаевые и смены")
                Picker("Период", selection:$period){ ForEach(Period.allCases){Text($0.rawValue).tag($0)} }.pickerStyle(.segmented)
                let orders = filteredRoutes.reduce(0){$0+$1.factualOrders}; let tips = filteredRoutes.reduce(Int64(0)){$0+$1.tipsHellers}; let gross=filteredRoutes.reduce(Int64(0)){$0+$1.grossHellers}
                HStack(spacing:10){ KXMetric(title:"Заказы",value:"\(orders)",icon:"shippingbox"); KXMetric(title:"Чаевые",value:moneyKc(tips),icon:"banknote") }
                HStack(spacing:10){ KXMetric(title:"Смены",value:"\(filteredShifts.count)",icon:"clock"); KXMetric(title:"Заработок",value:moneyKc(gross+tips),icon:"chart.line.uptrend.xyaxis") }
                KXCard(content: VStack(alignment:.leading,spacing:10){ Text("Заказы по дням").font(.headline); Chart(filteredRoutes){ r in BarMark(x:.value("День",r.date,unit:.day),y:.value("Заказы",r.factualOrders)).foregroundStyle(Color.kxGreen.gradient) }.frame(height:220) })
                if let best = filteredRoutes.max(by: {$0.factualOrders < $1.factualOrders}) { KXCard(content: VStack(alignment:.leading){ Text("Лучший день").font(.caption).foregroundStyle(.secondary); Text(best.date.formatted(date:.abbreviated,time:.omitted)).font(.headline); Text("\(best.factualOrders) заказов · \(moneyKc(best.tipsHellers)) чаевых").foregroundStyle(.secondary) }) }
            }.padding(16).padding(.bottom,24)
        }.background(Color.kxBackground.ignoresSafeArea()).navigationBarHidden(true)
    }
}

// MARK: - SCANNER
struct ScannerView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Shift.date, order: .reverse) private var shifts:[Shift]
    @State private var item: PhotosPickerItem?; @State private var image: UIImage?; @State private var text=""; @State private var busy=false; @State private var showRoute=false
    var body: some View {
        ScrollView { VStack(spacing:14) {
            KXHeader(title:"Сканер", subtitle:"OCR заказников, статистики и финансов")
            KXCard(content: VStack(spacing:12){
                if let image { Image(uiImage:image).resizable().scaledToFit().frame(maxHeight:260).clipShape(RoundedRectangle(cornerRadius:14)) }
                PhotosPicker(selection:$item, matching:.images) { Label(image == nil ? "Выбрать фото" : "Выбрать другое фото", systemImage:"photo").frame(maxWidth:.infinity) }.buttonStyle(.borderedProminent).tint(Color.kxGreen)
                if busy { ProgressView("Распознавание…") }
                if !text.isEmpty {
                    DisclosureGroup("Исходный OCR") { TextEditor(text:$text).frame(minHeight:150).font(.system(.caption,design:.monospaced)).scrollContentBackground(.hidden) }
                    Button("Создать трассу из результата") { showRoute=true }.buttonStyle(.borderedProminent).tint(Color.kxGreen)
                }
            })
            Text("OCR-блок по умолчанию свернут. Перед сохранением можно проверить и исправить распознанный текст.").font(.caption).foregroundStyle(.secondary)
        }.padding(16) }.background(Color.kxBackground.ignoresSafeArea()).navigationBarHidden(true)
        .onChange(of:item){ _,new in guard let new else{return}; Task { busy=true; defer{busy=false}; if let data=try? await new.loadTransferable(type:Data.self), let ui=UIImage(data:data){ image=ui; text=(try? await OCRService.recognize(ui)) ?? "" } } }
        .sheet(isPresented:$showRoute){ RouteEditorView(ocrText:text, shift:shifts.first{$0.deletedAt==nil && $0.status == .active}) }
    }
}

// MARK: - MORE
struct MoreView: View {
    var body: some View {
        ScrollView { VStack(spacing: 10) {
            KXHeader(title:"Ещё", subtitle:"Все разделы KurierX")
            KXCard(content: VStack(spacing:0){
                moreLink("Клиенты","По дням, трассам и чаевым","person.2", CustomersView())
                Divider(); moreLink("Смены","История и редактирование","clock", ShiftsView())
                Divider(); moreLink("Зарплата","Помесячная диаграмма","chart.bar", SalaryView())
                Divider(); moreLink("Бонусы и штрафы","Финансовые операции и OCR","banknote", FinancialView())
                Divider(); moreLink("Дизель","Расходы на топливо","fuelpump", FuelView())
                Divider(); moreLink("Авансы","Полученные авансы","creditcard", AdvancesView())
                Divider(); moreLink("Цели","Заказы и заработок","target", GoalsView())
                Divider(); moreLink("Резервные копии","Экспорт локальных данных","externaldrive", BackupView())
                Divider(); moreLink("Журнал","История действий","list.bullet.rectangle", AuditView())
                Divider(); moreLink("Корзина","Удалённые данные","trash", TrashView())
                Divider(); moreLink("Расширенный режим","Служебные функции","lock.shield", DeveloperView())
                Divider(); moreLink("Настройки","Склад, адрес и аккаунт","gearshape", SettingsView())
            })
        }.padding(16).padding(.bottom,25) }.background(Color.kxBackground.ignoresSafeArea()).navigationBarHidden(true)
    }
    private func moreLink<D:View>(_ title:String,_ subtitle:String,_ icon:String,_ destination:D)->some View { NavigationLink(destination:destination){KXRow(title:title,subtitle:subtitle,icon:icon)}.buttonStyle(.plain) }
}

