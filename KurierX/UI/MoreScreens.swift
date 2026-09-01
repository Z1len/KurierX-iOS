import SwiftUI
import SwiftData
import UIKit

struct AccountView: View {
    @EnvironmentObject var session: SessionStore
    var body: some View {
        Form {
            Section("Профиль") {
                if session.isOwner {
                    LabeledContent("Роль", value: "OWNER")
                    Text("OWNER использует обычный KurierX и открывает Control через вкладку Ещё.")
                } else if let p = session.profile {
                    LabeledContent("Имя", value: p.firstName + " " + p.lastName)
                    LabeledContent("Courier ID", value: p.courierID)
                    LabeledContent("Статус", value: p.status)
                }
            }
            Section("Устройство") {
                LabeledContent("Модель", value: UIDevice.current.model)
                LabeledContent("Система", value: "iOS \(UIDevice.current.systemVersion)")
                Text(SessionStore.deviceID()).font(.caption2).textSelection(.enabled)
            }
            Section {
                Button(role: .destructive) {
                    Task {
                        if session.isOwner { await session.leaveOwnerToActivation() }
                        else { await session.signOutUser() }
                    }
                } label: { Text(session.isOwner ? "Выйти из OWNER" : "Выйти из аккаунта") }
            }
        }
        .navigationTitle("Аккаунт")
    }
}

struct ClientsView: View {
    @Query(sort: \Customer.date, order: .reverse) private var customers: [Customer]
    @State private var search = ""
    private var visible: [Customer] {
        customers.filter {
            $0.deletedAt == nil && (search.isEmpty || ($0.firstName + " " + $0.lastName + " " + $0.address).localizedCaseInsensitiveContains(search))
        }
    }
    var body: some View {
        List {
            ForEach(visible) { c in
                VStack(alignment: .leading, spacing: 4) {
                    Text((c.firstName + " " + c.lastName).trimmingCharacters(in: .whitespaces)).font(.headline)
                    Text(c.address).foregroundStyle(.secondary)
                    Text(c.date.formatted(date: .abbreviated, time: .omitted) + " · трасса #\(c.routeSequence) · \(c.routeTypeRaw)").font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
        .searchable(text: $search, prompt: "Имя или адрес")
        .navigationTitle("Клиенты")
    }
}

struct ShiftsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Shift.date, order: .reverse) private var shifts: [Shift]
    var body: some View {
        List {
            ForEach(shifts.filter { $0.deletedAt == nil }) { s in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(s.date.formatted(date: .long, time: .omitted)).bold()
                        Spacer()
                        Text(s.status.rawValue.uppercased()).font(.caption).foregroundStyle(s.status == .active ? Color.kxGreen : .secondary)
                    }
                    Text("\(s.warehouse.rawValue) · план \(s.plannedRings)K · \(minutesLabel(s.durationMinutes))").foregroundStyle(.secondary)
                    if let q = s.queueOdometer {
                        Text("Спидометр: \(String(format: "%.1f", q)) → \(String(format: "%.1f", s.closingOdometer ?? q))").font(.caption)
                    }
                }
                .swipeActions {
                    Button(role: .destructive) { s.deletedAt = Date.now; try? context.save() } label: { Label("Удалить", systemImage: "trash") }
                }
            }
        }
        .navigationTitle("Смены")
    }
}

enum FinanceFilter: Equatable { case positive, penalty }

struct FinanceView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FinancialEntry.date, order: .reverse) private var entries: [FinancialEntry]
    let filter: FinanceFilter
    @State private var add = false
    private var visible: [FinancialEntry] {
        entries.filter { $0.deletedAt == nil && (filter == .positive ? $0.kind.positive : $0.kind == .penalty) }
    }
    var body: some View {
        List {
            ForEach(visible) { e in
                HStack {
                    VStack(alignment: .leading) {
                        Text(e.kind.rawValue).bold()
                        Text(e.date.formatted(date: .abbreviated, time: .omitted) + " · " + e.note).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text((e.kind.positive ? "+ " : "− ") + moneyKc(e.amountHellers)).foregroundStyle(e.kind.positive ? Color.kxGreen : .red)
                }
                .swipeActions {
                    Button(role: .destructive) { e.deletedAt = Date.now; try? context.save() } label: { Label("Удалить", systemImage: "trash") }
                }
            }
        }
        .navigationTitle(filter == .positive ? "Бонусы и компенсации" : "Штрафы")
        .toolbar { Button { add = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $add) { FinancialEditor(defaultKind: filter == .positive ? .bonus : .penalty) }
    }
}

struct FinancialEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var kind: FinancialKind
    @State private var amount = ""
    @State private var note = ""
    init(defaultKind: FinancialKind) { _kind = State(initialValue: defaultKind) }
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
                        context.insert(FinancialEntry(kind: kind, amountHellers: value, note: note)); try? context.save(); dismiss()
                    }
                }
            }
        }
    }
}

struct FuelView: View {
    @Query(sort: \FuelEntry.date, order: .reverse) private var entries: [FuelEntry]
    @State private var add = false
    var body: some View {
        List {
            ForEach(entries.filter { $0.deletedAt == nil }) { e in
                HStack {
                    VStack(alignment: .leading) {
                        Text(e.date.formatted(date: .abbreviated, time: .omitted)).bold()
                        Text("\(String(format: "%.1f", e.liters)) л · \(String(format: "%.1f", e.distanceKm)) км · \(e.note)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(); Text(moneyKc(e.amountHellers))
                }
            }
        }
        .navigationTitle("Дизель и авторасходы")
        .toolbar { Button { add = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $add) { FuelEditor() }
    }
}

struct FuelEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var amount = ""; @State private var liters = ""; @State private var km = ""; @State private var note = ""
    var body: some View {
        NavigationStack {
            Form {
                TextField("Сумма Kč", text: $amount).keyboardType(.decimalPad)
                TextField("Литры", text: $liters).keyboardType(.decimalPad)
                TextField("Км", text: $km).keyboardType(.decimalPad)
                TextField("Комментарий", text: $note)
            }
            .navigationTitle("Авторасход")
            .toolbar {
                KeyboardDoneToolbar()
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        context.insert(FuelEntry(amountHellers: Int64((Double(amount.replacingOccurrences(of: ",", with: ".")) ?? 0) * 100), liters: Double(liters.replacingOccurrences(of: ",", with: ".")) ?? 0, distanceKm: Double(km.replacingOccurrences(of: ",", with: ".")) ?? 0, note: note))
                        try? context.save(); dismiss()
                    }
                }
            }
        }
    }
}

struct AdvancesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \AdvanceEntry.date, order: .reverse) private var entries: [AdvanceEntry]
    @State private var add = false
    var body: some View {
        List {
            ForEach(entries.filter { $0.deletedAt == nil }) { e in
                HStack {
                    VStack(alignment: .leading) { Text(e.date.formatted(date: .abbreviated, time: .omitted)); Text(e.note).font(.caption).foregroundStyle(.secondary) }
                    Spacer(); Text(moneyKc(e.amountHellers))
                }
            }
        }
        .navigationTitle("Авансы")
        .toolbar { Button { add = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $add) { SimpleMoneyEditor(title: "Аванс") { v, n in context.insert(AdvanceEntry(amountHellers: v, note: n)); try? context.save() } }
    }
}

struct SalaryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SalaryEntry.paidAt, order: .reverse) private var entries: [SalaryEntry]
    @Query private var routes: [Route]
    @Query private var finances: [FinancialEntry]
    @Query private var fuel: [FuelEntry]
    @Query private var advances: [AdvanceEntry]
    @State private var add = false

    private var expected: Int64 {
        let month = Date.now.monthKey
        let routeValue = routes.filter { $0.deletedAt == nil && $0.date.monthKey == month }.reduce(Int64(0)) { $0 + EarningsService.routeGross($1) + $1.tipsHellers }
        let extraValue = finances.filter { $0.deletedAt == nil && $0.date.monthKey == month }.reduce(Int64(0)) { $0 + ($1.kind.positive ? $1.amountHellers : -$1.amountHellers) }
        let fuelValue = fuel.filter { $0.deletedAt == nil && $0.date.monthKey == month }.reduce(Int64(0)) { $0 + $1.amountHellers }
        let advanceValue = advances.filter { $0.deletedAt == nil && $0.date.monthKey == month }.reduce(Int64(0)) { $0 + $1.amountHellers }
        return routeValue + extraValue - fuelValue - advanceValue
    }
    private var paid: Int64 { entries.filter { $0.month == Date.now.monthKey }.reduce(Int64(0)) { $0 + $1.paidHellers } }

    var body: some View {
        List {
            Section("Текущий месяц") {
                LabeledContent("Расчёт приложения", value: moneyKc(expected))
                LabeledContent("Выплачено", value: moneyKc(paid))
                LabeledContent("Разница", value: moneyKc(expected - paid))
            }
            Section("Выплаты") {
                ForEach(entries) { e in
                    HStack { VStack(alignment: .leading) { Text(e.month).bold(); Text(e.note).font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(moneyKc(e.paidHellers)) }
                }
            }
        }
        .navigationTitle("Зарплата")
        .toolbar { Button { add = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $add) { SimpleMoneyEditor(title: "Выплата") { v, n in context.insert(SalaryEntry(month: Date.now.monthKey, paidHellers: v, note: n)); try? context.save() } }
    }
}

struct SimpleMoneyEditor: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let save: (Int64, String) -> Void
    @State private var amount = ""; @State private var note = ""
    var body: some View {
        NavigationStack {
            Form { TextField("Сумма Kč", text: $amount).keyboardType(.decimalPad); TextField("Комментарий", text: $note) }
                .navigationTitle(title)
                .toolbar {
                    KeyboardDoneToolbar()
                    ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Сохранить") { save(Int64((Double(amount.replacingOccurrences(of: ",", with: ".")) ?? 0) * 100), note); dismiss() } }
                }
        }
    }
}

struct GoalsView: View {
    @Environment(\.modelContext) private var context
    @Query private var goals: [Goal]
    @State private var orders = ""; @State private var money = ""
    var body: some View {
        Form {
            Section("Текущий месяц") {
                TextField("Цель заказов", text: $orders).keyboardType(.numberPad)
                TextField("Цель Kč", text: $money).keyboardType(.decimalPad)
                Button("Сохранить") {
                    let key = Date.now.monthKey; let t = Int(orders) ?? 0; let h = Int64((Double(money.replacingOccurrences(of: ",", with: ".")) ?? 0) * 100)
                    if let g = goals.first(where: { $0.month == key }) { g.targetOrders = t; g.targetHellers = h }
                    else { context.insert(Goal(month: key, targetOrders: t, targetHellers: h)) }
                    try? context.save()
                }
            }
            Section("Цели") {
                ForEach(goals, id: \.month) { g in HStack { Text(g.month); Spacer(); Text("\(g.targetOrders) заказов · \(moneyKc(g.targetHellers))") } }
            }
        }
        .navigationTitle("Цели")
        .onAppear { if let g = goals.first(where: { $0.month == Date.now.monthKey }) { orders = String(g.targetOrders); money = String(Double(g.targetHellers) / 100) } }
        .toolbar { KeyboardDoneToolbar() }
    }
}

struct BackupView: View {
    @Query private var shifts: [Shift]; @Query private var routes: [Route]; @Query private var customers: [Customer]
    private var text: String { "KurierX backup\nСмен: \(shifts.count)\nТрасс: \(routes.count)\nКлиентов: \(customers.count)\nСоздано: \(Date.now.formatted())" }
    var body: some View {
        List {
            Section { ShareLink(item: text) { Label("Поделиться резервной копией", systemImage: "square.and.arrow.up") } }
            Section("Состояние") { LabeledContent("Смен", value: "\(shifts.count)"); LabeledContent("Трасс", value: "\(routes.count)"); LabeledContent("Клиентов", value: "\(customers.count)") }
        }
        .navigationTitle("Резервные копии")
    }
}

struct AuditView: View {
    @Query(sort: \AuditEntry.date, order: .reverse) private var entries: [AuditEntry]
    var body: some View { List(entries) { e in VStack(alignment: .leading) { Text(e.title).bold(); Text(e.details).font(.caption).foregroundStyle(.secondary); Text(e.date.formatted()).font(.caption2).foregroundStyle(.tertiary) } }.navigationTitle("Журнал") }
}

struct TrashView: View {
    @Environment(\.modelContext) private var context
    @Query private var shifts: [Shift]; @Query private var routes: [Route]; @Query private var customers: [Customer]; @Query private var finances: [FinancialEntry]
    var body: some View {
        List {
            Section("Трассы") { ForEach(routes.filter { $0.deletedAt != nil }) { r in restore("\(r.date.formatted(date: .numeric, time: .omitted)) · \(r.type.rawValue)") { r.deletedAt = nil; try? context.save() } } }
            Section("Клиенты") { ForEach(customers.filter { $0.deletedAt != nil }) { c in restore(c.firstName + " " + c.lastName) { c.deletedAt = nil; try? context.save() } } }
            Section("Смены") { ForEach(shifts.filter { $0.deletedAt != nil }) { s in restore(s.date.formatted(date: .numeric, time: .omitted)) { s.deletedAt = nil; try? context.save() } } }
            Section("Финансы") { ForEach(finances.filter { $0.deletedAt != nil }) { e in restore(e.kind.rawValue) { e.deletedAt = nil; try? context.save() } } }
        }
        .navigationTitle("Корзина")
    }
    private func restore(_ title: String, _ action: @escaping () -> Void) -> some View { HStack { Text(title); Spacer(); Button("Восстановить", action: action) } }
}

struct DeveloperView: View {
    @AppStorage("kxDeveloperUnlocked") private var unlocked = false
    @State private var code = ""
    var body: some View {
        Form {
            if unlocked {
                Section("Расширенный режим") { Label("Расширенный доступ активен", systemImage: "checkmark.shield.fill").foregroundStyle(Color.kxGreen); Button("Заблокировать режим") { unlocked = false } }
                Section("Возможности") { Text("Редактирование закрытых данных, изменение километража, восстановление из корзины и диагностические операции.") }
            } else {
                Section("Авторизация") { SecureField("Код расширенного доступа", text: $code).keyboardType(.numberPad); Button("Разблокировать") { if code == "25643" { unlocked = true; code = "" } } }
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
            Section("Работа") { Picker("Склад по умолчанию", selection: $warehouse) { ForEach(Warehouse.allCases) { Text($0.rawValue).tag($0.rawValue) } }; TextField("Адрес проживания", text: $address) }
            Section("Интерфейс") { LabeledContent("Тема", value: "Тёмная KurierX"); LabeledContent("Версия", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") }
            Section("Аккаунт") { Button(role: .destructive) { Task { if session.isOwner { await session.leaveOwnerToActivation() } else { await session.signOutUser() } } } label: { Text("Выйти") } }
        }
        .navigationTitle("Настройки")
        .toolbar { KeyboardDoneToolbar() }
    }
}

struct MileageView: View {
    @Query(sort: \Shift.date, order: .reverse) private var shifts: [Shift]
    @Query private var routes: [Route]
    var body: some View {
        List {
            Section("Смены") {
                ForEach(shifts.filter { $0.deletedAt == nil }) { s in
                    VStack(alignment: .leading) {
                        Text(s.date.formatted(date: .abbreviated, time: .omitted)).bold()
                        Text("Утро \(s.morningOdometer.map { String(format: "%.1f", $0) } ?? "—") · очередь \(s.queueOdometer.map { String(format: "%.1f", $0) } ?? "—") · закрытие \(s.closingOdometer.map { String(format: "%.1f", $0) } ?? "—")").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Трассы") {
                ForEach(routes.filter { $0.deletedAt == nil && $0.distanceKm != nil }) { r in LabeledContent("\(r.date.formatted(date: .numeric, time: .omitted)) · #\(r.sequence)", value: "\(String(format: "%.1f", r.distanceKm ?? 0)) км") }
            }
        }
        .navigationTitle("Километраж")
    }
}

struct TutorialView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                KXHeader(title: "Как пользоваться")
                tutorial("1. Начни смену", "Главная → Přihlásit se do fronty. Укажи план колечек и спидометр.")
                tutorial("2. Закрытая трасса", "Сканер → Трасса. Выбери OT / Region / Express, введи факт и сохрани.")
                tutorial("3. Заказники", "Сканер → Заказники. Выбери несколько фото в правильном порядке.")
                tutorial("4. График", "Календарь → Импорт скриншота, проверь найденный день и колечки.")
                tutorial("5. Финансы", "Ещё содержит бонусы, штрафы, дизель, авансы, зарплату и цели.")
            }.padding(18)
        }
        .navigationTitle("Обучение")
    }
    private func tutorial(_ t: String, _ d: String) -> some View { KXCard { VStack(alignment: .leading, spacing: 5) { Text(t).font(.headline); Text(d).foregroundStyle(.secondary) } } }
}
