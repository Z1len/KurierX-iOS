import SwiftUI
import SwiftData
import PhotosUI
import UIKit

struct MainShell: View {
    let isOwner: Bool
    @State private var tab: Tab = .home
    enum Tab: CaseIterable, Hashable { case home, calendar, stats, scanner, more }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.kxBackground.ignoresSafeArea()
            Group {
                switch tab {
                case .home: NavigationStack { HomeView { tab = .scanner } }
                case .calendar: NavigationStack { CalendarViewKX() }
                case .stats: NavigationStack { StatsView() }
                case .scanner: NavigationStack { ScannerView() }
                case .more: NavigationStack { MoreView(isOwner: isOwner) }
                }
            }
            .padding(.bottom, 78)

            KXBottomBar(selection: $tab)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
}

struct KXBottomBar: View {
    @Binding var selection: MainShell.Tab
    private let items: [(MainShell.Tab,String,String)] = [
        (.home,"Главная","house"),(.calendar,"Календарь","calendar"),(.stats,"Статистика","chart.bar.xaxis"),(.scanner,"Сканер","qrcode.viewfinder"),(.more,"Ещё","ellipsis")
    ]
    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.0) { item in
                Button { selection = item.0 } label: {
                    VStack(spacing: 4) {
                        ZStack {
                            if selection == item.0 { Capsule().fill(Color.kxPurple.opacity(0.75)).frame(width: 54, height: 38) }
                            Image(systemName: item.2).font(.system(size: 23, weight: .semibold)).foregroundStyle(selection == item.0 ? .white : Color.white.opacity(0.72))
                        }.frame(height: 40)
                        Text(item.1).font(.system(size: 11, weight: selection == item.0 ? .semibold : .regular)).foregroundStyle(selection == item.0 ? Color.kxGreen : Color.white.opacity(0.72)).lineLimit(1).minimumScaleFactor(0.7)
                    }.frame(maxWidth: .infinity)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4).padding(.top, 8).padding(.bottom, 6)
        .background(Color.kxSurface2.opacity(0.98))
        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) }
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
    @State private var showStart = false
    @State private var showPlan = false
    @State private var plan = "4"
    @State private var showClose = false

    private var activeShift: Shift? { shifts.first { $0.deletedAt == nil && $0.status == .active } }
    private var visibleRoutes: [Route] { routes.filter { $0.deletedAt == nil } }
    private var factualOrders: Int { visibleRoutes.reduce(0) { $0 + $1.factualOrders } }
    private var tips: Int64 { visibleRoutes.reduce(0) { $0 + $1.tipsHellers } }
    private var routeGross: Int64 { visibleRoutes.reduce(0) { $0 + EarningsService.routeGross($1) } }
    private var net: Int64 {
        let f = finances.filter { $0.deletedAt == nil }.reduce(Int64(0)) { $0 + ($1.kind.positive ? $1.amountHellers : -$1.amountHellers) }
        let diesel = fuel.filter { $0.deletedAt == nil }.reduce(Int64(0)) { $0 + $1.amountHellers }
        let adv = advances.filter { $0.deletedAt == nil }.reduce(Int64(0)) { $0 + $1.amountHellers }
        return routeGross + tips + f - diesel - adv
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                KXBrand().padding(.top, 8)
                if let goal = goals.first(where: { $0.month == Date.now.monthKey }), goal.targetOrders > 0 { GoalProgressCard(current: factualOrders, target: goal.targetOrders) }
                KXCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Заработок по обработанным трассам").font(.system(size: 15, weight: .semibold))
                        Text(moneyKc(net)).font(.system(size: 38, weight: .bold, design: .rounded))
                        Text("\(factualOrders) фактических заказов · чаевые \(moneyKc(tips))").font(.system(size: 16)).foregroundStyle(.secondary)
                        Text("Итог учитывает трассы, бонусы / компенсации, штрафы, дизель и авансы.").font(.system(size: 14)).foregroundStyle(.secondary)
                    }
                }
                if let shift = activeShift {
                    ActiveShiftCard(shift: shift, routes: visibleRoutes.filter { $0.shiftID == shift.id }, onEditPlan: { plan = String(shift.plannedRings); showPlan = true }, onScanner: openScanner, onClose: { showClose = true })
                } else {
                    KXCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Смена не начата").font(.system(size: 23, weight: .bold))
                            Text("Рабочее время начнётся только после входа в очередь.").foregroundStyle(.secondary)
                            Button("Přihlásit se do fronty") { showStart = true }.buttonStyle(.borderedProminent).tint(Color.kxGreen).controlSize(.large).frame(maxWidth: .infinity)
                        }
                    }
                }
                if !visibleRoutes.isEmpty {
                    Text("Закрытые трассы").font(.title2.bold()).frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(visibleRoutes.prefix(8)) { route in RouteSummaryCard(route: route) }
                }
            }.padding(.horizontal, 18).padding(.bottom, 24)
        }
        .background(Color.kxBackground.ignoresSafeArea())
        .navigationBarHidden(true)
        .sheet(isPresented: $showStart) { StartShiftSheet() }
        .alert("Изменить план", isPresented: $showPlan) {
            TextField("Колечек", text: $plan).keyboardType(.numberPad)
            Button("Сохранить") { if let shift = activeShift { shift.plannedRings = max(1, Int(plan) ?? 4); try? context.save() } }
            Button("Отмена", role: .cancel) { }
        }
        .alert("Закрыть текущую смену?", isPresented: $showClose) {
            Button("Закрыть") { if let shift = activeShift { shift.endedAt = Date.now; shift.status = .complete; try? context.save() } }
            Button("Отмена", role: .cancel) { }
        }
    }
}

struct GoalProgressCard: View {
    let current: Int; let target: Int
    var body: some View {
        KXCard {
            VStack(spacing: 8) {
                HStack { Text("\(current)").bold().foregroundStyle(Color.kxGreen); Text("/ \(target)"); Spacer(); Text("Цель: \(target) заказов").font(.caption.bold()) }
                ProgressView(value: Double(current), total: Double(max(1,target))).tint(Color.kxGreen)
                Text(current >= target ? "Цель выполнена ✓" : "Осталось \(target-current) заказов").font(.caption).foregroundStyle(current >= target ? Color.kxGreen : .secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct ActiveShiftCard: View {
    let shift: Shift; let routes: [Route]
    let onEditPlan: () -> Void; let onScanner: () -> Void; let onClose: () -> Void
    private var completed: Int { routes.reduce(0) { $0 + $1.type.rings } }
    var body: some View {
        KXCard {
            VStack(alignment: .leading, spacing: 15) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Смена активна").font(.system(size: 24, weight: .bold))
                        Text("Старт \(shift.startedAt?.formatted(date: .omitted, time: .shortened) ?? "—")").font(.system(size: 17)).foregroundStyle(.secondary)
                    }
                    Spacer(); Text("\(completed)/\(max(1,shift.plannedRings)) K").font(.title3.bold()).padding(.horizontal, 14).padding(.vertical, 10).background(Color.kxPurple, in: RoundedRectangle(cornerRadius: 14))
                }
                Text(completed >= shift.plannedRings ? "План выполнен" : "Осталось по плану: \(max(0, shift.plannedRings-completed)) колечка").font(.system(size: 17))
                Button("Изменить план", action: onEditPlan).foregroundStyle(Color.kxGreen).fontWeight(.semibold)
                Button("Добавить закрытую трассу", action: onScanner).buttonStyle(.borderedProminent).tint(Color.kxGreen).controlSize(.large).frame(maxWidth: .infinity)
                Button("Закрыть текущую смену", action: onClose).buttonStyle(.bordered).controlSize(.large).frame(maxWidth: .infinity)
            }
        }
    }
}

struct StartShiftSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var warehouse = Warehouse.liboc
    @State private var plan = 4
    @State private var queueOdo = ""
    var body: some View {
        NavigationStack {
            Form {
                Picker("Склад", selection: $warehouse) { ForEach(Warehouse.allCases) { Text($0.rawValue).tag($0) } }
                Stepper("План: \(plan) колечка", value: $plan, in: 1...20)
                TextField("Спидометр при входе", text: $queueOdo).keyboardType(.decimalPad)
            }
            .navigationTitle("Начать смену")
            .toolbar {
                KeyboardDoneToolbar()
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Начать") { let s = Shift(date: Date.now, warehouse: warehouse, status: .active, plannedRings: plan); s.startedAt = Date.now; s.queueOdometer = Double(queueOdo.replacingOccurrences(of: ",", with: ".")); context.insert(s); try? context.save(); dismiss() } }
            }
        }
    }
}

struct RouteSummaryCard: View {
    let route: Route
    var body: some View {
        KXCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack { Text("✓ \(route.type.rawValue) · \(route.warehouse.rawValue)").font(.headline); Spacer(); Text(moneyKc(EarningsService.routeGross(route))).bold() }
                Text("1 колечко · трасса #\(route.sequence) · \(route.factualOrders) заказов\(route.distanceKm.map { " · \(String(format:"%.1f",$0)) км" } ?? "")").font(.caption).foregroundStyle(.secondary)
                if route.tipsHellers > 0 { Text("Чаевые \(moneyKc(route.tipsHellers))").font(.caption).foregroundStyle(Color.kxGreen) }
            }
        }
    }
}

// MARK: - CALENDAR
struct CalendarViewKX: View {
    @Query(sort: \CalendarPlan.date) private var plans: [CalendarPlan]
    @State private var month = Date.now
    @State private var pickerItem: PhotosPickerItem?
    @State private var ocrText = ""
    @State private var showImport = false
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)

    private var days: [Date?] {
        let cal = Calendar.current; let interval = cal.dateInterval(of: .month, for: month)!; let first = interval.start
        let leading = (cal.component(.weekday, from: first)+5)%7; let count = cal.range(of: .day, in: .month, for: month)?.count ?? 30
        return Array(repeating: nil, count: leading) + (0..<count).compactMap { cal.date(byAdding: .day, value: $0, to: first) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack { KXHeader(title: "Календарь", subtitle: "План смен и колечек"); Button("Сегодня") { month = Date.now }.foregroundStyle(Color.kxGreen) }.padding(.top, 10)
                KXCard {
                    VStack(spacing: 14) {
                        HStack { Button { month = Calendar.current.date(byAdding: .month, value: -1, to: month)! } label: { Image(systemName: "chevron.left.circle.fill").font(.title) }; Spacer(); Text(month.formatted(.dateTime.month(.wide).year())).font(.system(size: 25, weight: .bold)); Spacer(); Button { month = Calendar.current.date(byAdding: .month, value: 1, to: month)! } label: { Image(systemName: "chevron.right.circle.fill").font(.title) } }
                        LazyVGrid(columns: columns, spacing: 7) {
                            ForEach(["ПН","ВТ","СР","ЧТ","ПТ","СБ","ВС"], id:\.self) { Text($0).font(.caption.bold()).foregroundStyle(.secondary) }
                            ForEach(Array(days.enumerated()), id:\.offset) { _, day in
                                if let day { CalendarDayCell(day: day, plan: plans.first { $0.date.sameDay(as: day) }) } else { Color.clear.frame(height: 83) }
                            }
                        }
                    }
                }
                HStack(spacing: 12) {
                    PhotosPicker(selection: $pickerItem, matching: .images) { Text("Камера / Фото").frame(maxWidth:.infinity) }.buttonStyle(.bordered).controlSize(.large)
                    Button("Импорт скриншота") { showImport = true }.buttonStyle(.borderedProminent).tint(Color.kxGreen).controlSize(.large).frame(maxWidth:.infinity)
                }
                Text("После OCR график сначала открывается на проверку найденных рабочих дней.").font(.footnote).foregroundStyle(.secondary).frame(maxWidth:.infinity, alignment:.leading)
                KXCard { VStack(alignment:.leading,spacing:7) { Text("Цвета плана").font(.headline); Text("Liboc: 6:00 зелёный · 6:30 красный · 7:30 фиолетовый").foregroundStyle(.secondary) } }
            }.padding(.horizontal,18).padding(.bottom,22)
        }
        .background(Color.kxBackground.ignoresSafeArea()).navigationBarHidden(true)
        .onChange(of: pickerItem) { _, item in Task { guard let data = try? await item?.loadTransferable(type: Data.self), let image = UIImage(data:data), let text = try? await OCRService.recognize(image) else { return }; ocrText=text; showImport=true } }
        .sheet(isPresented:$showImport) { CalendarImportSheet(ocrText: ocrText) }
    }
}

struct CalendarDayCell: View {
    let day: Date; let plan: CalendarPlan?
    var body: some View {
        VStack(alignment:.leading,spacing:3) {
            Text(day.formatted(.dateTime.day())).font(.system(size:16,weight:.semibold))
            if let plan { Text(String(format:"%02d:%02d",plan.startMinutes/60,plan.startMinutes%60)).font(.caption2).foregroundStyle(Color.kxGreen); Text("\(plan.plannedRings)K").font(.caption2.bold()) }
            Spacer()
        }.padding(8).frame(maxWidth:.infinity,minHeight:83,alignment:.topLeading)
            .background(Color.kxSurface2,in:RoundedRectangle(cornerRadius:11)).overlay(RoundedRectangle(cornerRadius:11).stroke(Calendar.current.isDateInToday(day) ? Color.kxGreen : Color.white.opacity(0.06),lineWidth: Calendar.current.isDateInToday(day) ? 2 : 1))
    }
}

struct CalendarImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let ocrText: String
    @State private var date = Date.now; @State private var warehouse = Warehouse.liboc; @State private var hour = 6; @State private var minute = 0; @State private var rings = 4
    var body: some View {
        NavigationStack { Form { DatePicker("День",selection:$date,displayedComponents:.date); Picker("Склад",selection:$warehouse){ForEach(Warehouse.allCases){Text($0.rawValue).tag($0)}}; Stepper("Время: \(String(format:"%02d:%02d",hour,minute))",value:$hour,in:0...23); Stepper("Минуты: \(minute)",value:$minute,in:0...59,step:5); Stepper("Колечек: \(rings)",value:$rings,in:1...20); if !ocrText.isEmpty { Section("Распознано") { Text(ocrText).font(.caption).lineLimit(8) } } }
            .navigationTitle("Проверка импорта").toolbar { ToolbarItem(placement:.cancellationAction){Button("Отмена"){dismiss()}};ToolbarItem(placement:.confirmationAction){Button("Сохранить"){context.insert(CalendarPlan(date:date,warehouse:warehouse,startMinutes:hour*60+minute,plannedRings:rings));try? context.save();dismiss()}} } }
    }
}
