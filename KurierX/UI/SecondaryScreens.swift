import SwiftUI
import SwiftData
import Charts

// MARK: - Editors
struct ShiftEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let existing: Shift?

    @State private var date = Date()
    @State private var warehouse = Warehouse.liboc
    @State private var rings = 4

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Дата", selection: $date, displayedComponents: .date)
                Picker("Склад", selection: $warehouse) {
                    ForEach(Warehouse.allCases) { Text($0.rawValue).tag($0) }
                }
                Stepper("План: \(rings) K", value: $rings, in: 1...20)
            }
            .navigationTitle(existing == nil ? "Начать смену" : "Смена")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        if let existing {
                            existing.date = date
                            existing.warehouse = warehouse
                            existing.plannedRings = rings
                        } else {
                            let shift = Shift(date: date, warehouse: warehouse, status: .active, plannedRings: rings)
                            shift.startedAt = .now
                            context.insert(shift)
                        }
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            guard let existing else { return }
            date = existing.date
            warehouse = existing.warehouse
            rings = existing.plannedRings
        }
    }
}

struct RouteEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let ocrText: String
    let shift: Shift?

    @State private var type = RouteType.ot
    @State private var warehouse = Warehouse.liboc
    @State private var orders = 0
    @State private var tips = ""
    @State private var km = ""
    @State private var gross = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker("Тип", selection: $type) { ForEach(RouteType.allCases) { Text($0.rawValue).tag($0) } }
                Picker("Склад", selection: $warehouse) { ForEach(Warehouse.allCases) { Text($0.rawValue).tag($0) } }
                TextField("Факт заказов", value: $orders, format: .number).keyboardType(.numberPad)
                TextField("Чаевые Kč", text: $tips).keyboardType(.decimalPad)
                TextField("Км", text: $km).keyboardType(.decimalPad)
                TextField("Заработок Kč", text: $gross).keyboardType(.decimalPad)
                if !ocrText.isEmpty {
                    Section("OCR") { Text(ocrText).font(.caption).lineLimit(8) }
                }
            }
            .navigationTitle("Закрытая трасса")
            .toolbar {
                KeyboardDoneToolbar()
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        let route = Route(
                            shiftID: shift?.id ?? UUID(),
                            date: .now,
                            sequence: 1,
                            type: type,
                            warehouse: warehouse,
                            factualOrders: orders,
                            tipsHellers: Int64((Double(tips.replacingOccurrences(of: ",", with: ".")) ?? 0) * 100)
                        )
                        route.distanceKm = Double(km.replacingOccurrences(of: ",", with: "."))
                        route.grossHellers = Int64((Double(gross.replacingOccurrences(of: ",", with: ".")) ?? 0) * 100)
                        context.insert(route)
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
    }
}

struct CalendarPlanEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var date = Date()
    @State private var warehouse = Warehouse.liboc
    @State private var time = Date()
    @State private var rings = 4

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Дата", selection: $date, displayedComponents: .date)
                DatePicker("Начало", selection: $time, displayedComponents: .hourAndMinute)
                Picker("Склад", selection: $warehouse) { ForEach(Warehouse.allCases) { Text($0.rawValue).tag($0) } }
                Stepper("Колечки: \(rings)K", value: $rings, in: 1...20)
            }
            .navigationTitle("План смены")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        let c = Calendar.current
                        let mins = c.component(.hour, from: time) * 60 + c.component(.minute, from: time)
                        context.insert(CalendarPlan(date: date, warehouse: warehouse, startMinutes: mins, plannedRings: rings))
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Lists
struct CustomersView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Customer.date, order: .reverse) private var customers: [Customer]

    private var grouped: [String: [Customer]] {
        Dictionary(grouping: customers.filter { $0.deletedAt == nil }, by: { $0.date.dayKey })
    }

    var body: some View {
        List {
            ForEach(grouped.keys.sorted(by: >), id: \.self) { day in
                Section(day) {
                    ForEach(grouped[day]!.sorted { $0.routeSequence < $1.routeSequence }) { customer in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(customer.routeSequence) kolo · \(customer.routeTypeRaw)").font(.caption).foregroundStyle(Color.kxGreen)
                            Text("\(customer.firstName) \(customer.lastName)").bold()
                            Text(customer.address).font(.caption).foregroundStyle(.secondary)
                            if customer.tipsHellers > 0 { Text("Чаевые \(moneyKc(customer.tipsHellers))").font(.caption) }
                        }
                        .swipeActions {
                            Button(role: .destructive) { customer.deletedAt = .now; try? context.save() } label: { Label("Удалить", systemImage: "trash") }
                        }
                    }
                }
            }
        }
        .navigationTitle("Клиенты")
    }
}

struct ShiftsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Shift.date, order: .reverse) private var shifts: [Shift]
    @State private var add = false

    var body: some View {
        List {
            ForEach(shifts.filter { $0.deletedAt == nil }) { shift in
                VStack(alignment: .leading) {
                    HStack {
                        Text(shift.date.formatted(date: .abbreviated, time: .omitted)).bold()
                        Spacer()
                        Text(shift.statusRaw.uppercased()).font(.caption).foregroundStyle(Color.kxGreen)
                    }
                    Text("\(shift.warehouse.rawValue) · план \(shift.plannedRings)K").font(.caption).foregroundStyle(.secondary)
                }
                .swipeActions {
                    Button(role: .destructive) { shift.deletedAt = .now; try? context.save() } label: { Label("Удалить", systemImage: "trash") }
                }
            }
        }
        .navigationTitle("Смены")
        .toolbar { Button { add = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $add) { ShiftEditorView(existing: nil) }
    }
}

struct SalaryView: View {
    @Query private var routes: [Route]
    @Query private var finances: [FinancialEntry]
    @Query private var fuel: [FuelEntry]
    @Query private var advances: [AdvanceEntry]

    private var months: [String] { Array(Set(routes.filter { $0.deletedAt == nil }.map { $0.date.monthKey })).sorted() }

    private func total(_ month: String) -> Int64 {
        let monthRoutes = routes.filter { $0.deletedAt == nil && $0.date.monthKey == month }
        let base = monthRoutes.reduce(Int64(0)) { $0 + $1.grossHellers + $1.tipsHellers }
        let financial = finances.filter { $0.deletedAt == nil && $0.date.monthKey == month }.reduce(Int64(0)) { $0 + ($1.kind == .bonus ? $1.amountHellers : -$1.amountHellers) }
        let diesel = fuel.filter { $0.deletedAt == nil && $0.date.monthKey == month }.reduce(Int64(0)) { $0 + $1.amountHellers }
        let adv = advances.filter { $0.deletedAt == nil && $0.date.monthKey == month }.reduce(Int64(0)) { $0 + $1.amountHellers }
        return base + financial - diesel - adv
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                KXHeader(title: "Зарплата", subtitle: "Сравнение заработка по месяцам")
                KXCard(content:
                    Chart(months, id: \.self) { month in
                        BarMark(x: .value("Месяц", month), y: .value("Kč", Double(total(month))/100)).foregroundStyle(Color.kxGreen.gradient)
                    }.frame(height: 260)
                )
                ForEach(months.reversed(), id: \.self) { month in
                    let rs = routes.filter { $0.deletedAt == nil && $0.date.monthKey == month }
                    KXCard(content: VStack(alignment: .leading, spacing: 6) {
                        HStack { Text(month).font(.headline); Spacer(); Text(moneyKc(total(month))).bold() }
                        Text("Заказы: \(rs.reduce(0) { $0 + $1.factualOrders }) · чаевые: \(moneyKc(rs.reduce(Int64(0)) { $0 + $1.tipsHellers }))").font(.caption).foregroundStyle(.secondary)
                        Text("Колечки: \(rs.reduce(0) { $0 + $1.type.rings }) · OT \(rs.filter { $0.type == .ot }.count) · REG \(rs.filter { $0.type == .region }.count) · EXP \(rs.filter { $0.type == .express }.count)").font(.caption).foregroundStyle(.secondary)
                    })
                }
            }.padding(16)
        }
        .background(Color.kxBackground.ignoresSafeArea())
        .navigationTitle("Зарплата")
    }
}

struct FinancialView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FinancialEntry.date, order: .reverse) private var entries: [FinancialEntry]
    @State private var add = false

    var body: some View {
        List {
            ForEach(entries.filter { $0.deletedAt == nil }) { entry in
                HStack {
                    VStack(alignment: .leading) {
                        Text(entry.kind.rawValue).bold()
                        Text(entry.date.formatted(date: .abbreviated, time: .omitted) + " · " + entry.note).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(moneyKc(entry.amountHellers)).foregroundStyle(entry.kind == .bonus ? Color.kxGreen : .red)
                }
                .swipeActions {
                    Button(role: .destructive) { entry.deletedAt = .now; try? context.save() } label: { Label("Удалить", systemImage: "trash") }
                }
            }
        }
        .navigationTitle("Бонусы и штрафы")
        .toolbar { Button { add = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $add) { FinancialEditor() }
    }
}

struct FinancialEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var kind = FinancialKind.bonus
    @State private var amount = ""
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker("Тип", selection: $kind) { ForEach(FinancialKind.allCases) { Text($0.rawValue).tag($0) } }
                TextField("Сумма Kč", text: $amount).keyboardType(.decimalPad)
                TextField("Комментарий", text: $note)
            }
            .navigationTitle("Операция")
            .toolbar {
                KeyboardDoneToolbar()
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        let value = Int64((Double(amount.replacingOccurrences(of: ",", with: ".")) ?? 0) * 100)
                        context.insert(FinancialEntry(kind: kind, amountHellers: value, note: note))
                        try? context.save(); dismiss()
                    }
                }
            }
        }
    }
}

struct FuelView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FuelEntry.date, order: .reverse) private var entries: [FuelEntry]
    @State private var add = false
    var body: some View {
        List {
            ForEach(entries.filter { $0.deletedAt == nil }) { entry in
                HStack {
                    VStack(alignment: .leading) {
                        Text(entry.date.formatted(date: .abbreviated, time: .omitted)).bold()
                        Text("\(String(format: "%.1f", entry.distanceKm)) км · \(entry.note)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(); Text(moneyKc(entry.amountHellers))
                }
            }
        }
        .navigationTitle("Дизель")
        .toolbar { Button { add = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $add) { SimpleMoneyEditor(title: "Дизель") { amount, note in context.insert(FuelEntry(amountHellers: amount, note: note)); try? context.save() } }
    }
}

struct AdvancesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \AdvanceEntry.date, order: .reverse) private var entries: [AdvanceEntry]
    @State private var add = false
    var body: some View {
        List { ForEach(entries.filter { $0.deletedAt == nil }) { entry in HStack { Text(entry.date.formatted(date: .abbreviated, time: .omitted)); Spacer(); Text(moneyKc(entry.amountHellers)) } } }
            .navigationTitle("Авансы")
            .toolbar { Button { add = true } label: { Image(systemName: "plus") } }
            .sheet(isPresented: $add) { SimpleMoneyEditor(title: "Аванс") { amount, note in context.insert(AdvanceEntry(amountHellers: amount, note: note)); try? context.save() } }
    }
}

struct SimpleMoneyEditor: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let save: (Int64, String) -> Void
    @State private var amount = ""
    @State private var note = ""
    var body: some View {
        NavigationStack {
            Form {
                TextField("Сумма Kč", text: $amount).keyboardType(.decimalPad)
                TextField("Комментарий", text: $note)
            }
            .navigationTitle(title)
            .toolbar {
                KeyboardDoneToolbar()
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        let value = Int64((Double(amount.replacingOccurrences(of: ",", with: ".")) ?? 0) * 100)
                        save(value, note); dismiss()
                    }
                }
            }
        }
    }
}

struct GoalsView: View {
    @Environment(\.modelContext) private var context
    @Query private var goals: [Goal]
    @State private var orders = ""
    var body: some View {
        Form {
            Section("Текущий месяц") {
                TextField("Цель заказов", text: $orders).keyboardType(.numberPad)
                Button("Сохранить") {
                    let key = Date().monthKey
                    if let goal = goals.first(where: { $0.month == key }) { goal.targetOrders = Int(orders) ?? 0 }
                    else { context.insert(Goal(month: key, targetOrders: Int(orders) ?? 0)) }
                    try? context.save()
                }
            }
            Section("Цели") { ForEach(goals, id: \.month) { goal in HStack { Text(goal.month); Spacer(); Text("\(goal.targetOrders) заказов") } } }
        }
        .navigationTitle("Цели")
        .onAppear { orders = goals.first(where: { $0.month == Date().monthKey }).map { String($0.targetOrders) } ?? "" }
        .toolbar { KeyboardDoneToolbar() }
    }
}

struct BackupView: View {
    @Query private var shifts: [Shift]
    @Query private var routes: [Route]
    @Query private var customers: [Customer]
    private var exportText: String { "KurierX backup\nСмен: \(shifts.count)\nТрасс: \(routes.count)\nКлиентов: \(customers.count)\nСоздано: \(Date().formatted())" }
    var body: some View {
        List {
            Section { ShareLink(item: exportText) { Label("Поделиться резервной копией", systemImage: "square.and.arrow.up") } }
            Section("Состояние") { LabeledContent("Смен", value: "\(shifts.count)"); LabeledContent("Трасс", value: "\(routes.count)"); LabeledContent("Клиентов", value: "\(customers.count)") }
        }.navigationTitle("Резервные копии")
    }
}

struct AuditView: View {
    @Query(sort: \AuditEntry.date, order: .reverse) private var entries: [AuditEntry]
    var body: some View {
        List(entries) { entry in
            VStack(alignment: .leading) { Text(entry.title).bold(); Text(entry.details).font(.caption).foregroundStyle(.secondary); Text(entry.date.formatted()).font(.caption2).foregroundStyle(.tertiary) }
        }.navigationTitle("Журнал")
    }
}

struct TrashView: View {
    @Environment(\.modelContext) private var context
    @Query private var shifts: [Shift]
    @Query private var routes: [Route]
    @Query private var customers: [Customer]
    @Query private var finances: [FinancialEntry]
    var body: some View {
        List {
            Section("Трассы") { ForEach(routes.filter { $0.deletedAt != nil }) { route in restoreRow("\(route.date.formatted(date: .numeric, time: .omitted)) · \(route.type.rawValue)") { route.deletedAt = nil; try? context.save() } } }
            Section("Клиенты") { ForEach(customers.filter { $0.deletedAt != nil }) { customer in restoreRow(customer.firstName + " " + customer.lastName) { customer.deletedAt = nil; try? context.save() } } }
            Section("Смены") { ForEach(shifts.filter { $0.deletedAt != nil }) { shift in restoreRow(shift.date.formatted(date: .numeric, time: .omitted)) { shift.deletedAt = nil; try? context.save() } } }
            Section("Финансы") { ForEach(finances.filter { $0.deletedAt != nil }) { entry in restoreRow(entry.kind.rawValue) { entry.deletedAt = nil; try? context.save() } } }
        }.navigationTitle("Корзина")
    }
    private func restoreRow(_ title: String, action: @escaping () -> Void) -> some View { HStack { Text(title); Spacer(); Button("Восстановить", action: action) } }
}

struct DeveloperView: View {
    @AppStorage("kxDeveloperUnlocked") private var unlocked = false
    @State private var code = ""
    var body: some View {
        Form {
            if unlocked {
                Section("Расширенный режим") {
                    Label("Расширенный доступ активен", systemImage: "checkmark.shield.fill").foregroundStyle(Color.kxGreen)
                    Button("Заблокировать режим") { unlocked = false }
                }
                Section("Служебные функции") { Text("В расширенном режиме доступны редактирование и удаление закрытых данных, восстановление из корзины и диагностические операции.") }
            } else {
                Section("Авторизация") {
                    SecureField("Код расширенного доступа", text: $code).keyboardType(.numberPad)
                    Button("Разблокировать") { if code == "25643" { unlocked = true; code = "" } }
                }
            }
        }
        .navigationTitle("Расширенный режим")
        .toolbar { KeyboardDoneToolbar() }
    }
}

struct SettingsView: View {
    @EnvironmentObject var session: SessionStore
    @AppStorage("defaultWarehouse") private var warehouse = "Liboc"
    @AppStorage("homeAddress") private var address = ""
    var body: some View {
        Form {
            Section("Работа") {
                Picker("Склад по умолчанию", selection: $warehouse) { ForEach(Warehouse.allCases) { Text($0.rawValue).tag($0.rawValue) } }
                TextField("Адрес проживания", text: $address)
            }
            Section("Аккаунт") {
                if let profile = session.profile {
                    LabeledContent("Имя", value: profile.firstName + " " + profile.lastName)
                    LabeledContent("Courier ID", value: profile.courierID)
                }
                Button(role: .destructive) { Task { await session.signOutUser() } } label: { Text("Выйти из аккаунта") }
            }
        }
        .navigationTitle("Настройки")
        .toolbar { KeyboardDoneToolbar() }
    }
}
