import LocalAuthentication
import SwiftData
import SwiftUI

struct MoreView: View {
    let isOwner: Bool

    var body: some View {
        List {
            Section {
                if isOwner {
                    NavigationLink("KurierX Control") { OwnerControlView() }
                }

                NavigationLink("Клиенты") { ClientsView() }
                NavigationLink("Смены") { ShiftsView() }
                NavigationLink("Бонусы и компенсации") { FinanceView(filter: .positive) }
                NavigationLink("Штрафы") { FinanceView(filter: .penalty) }
                NavigationLink("Дизель и авторасходы") { FuelView() }
                NavigationLink("Цели") { GoalsView() }
                NavigationLink("Developer Mode") { DeveloperView() }
            }
        }
        .navigationTitle("Ещё")
    }
}

struct ClientsView: View {
    @Environment(\.modelContext) var ctx
    @Query(sort: \Customer.date, order: .reverse) var cs: [Customer]
    @State var add = false

    var body: some View {
        List {
            ForEach(cs.filter { $0.deletedAt == nil }) { c in
                VStack(alignment: .leading) {
                    Text(
                        (c.firstName + " " + c.lastName)
                            .trimmingCharacters(in: .whitespaces)
                    )
                    .bold()

                    Text(c.address)
                        .foregroundStyle(.secondary)
                }
                .swipeActions {
                    Button(role: .destructive) {
                        c.deletedAt = Date.now
                        try? ctx.save()
                    } label: {
                        Label("Удалить", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Клиенты")
        .toolbar {
            Button {
                add = true
            } label: {
                Image(systemName: "plus")
            }
        }
        .sheet(isPresented: $add) {
            CustomerEditor()
        }
    }
}

struct CustomerEditor: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var ctx

    @State var first = ""
    @State var last = ""
    @State var address = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Имя", text: $first)
                TextField("Фамилия", text: $last)
                TextField("Адрес", text: $address)
            }
            .navigationTitle("Новый клиент")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Добавить") {
                        ctx.insert(
                            Customer(
                                firstName: first,
                                lastName: last,
                                address: address
                            )
                        )
                        try? ctx.save()
                        dismiss()
                    }
                }
            }
        }
    }
}

struct ShiftsView: View {
    @Environment(\.modelContext) var ctx
    @Query(sort: \Shift.date, order: .reverse) var shifts: [Shift]
    @Query var routes: [Route]
    @State var edit: Shift?

    var body: some View {
        List {
            ForEach(shifts.filter { $0.deletedAt == nil }) { s in
                Button {
                    edit = s
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(
                            s.date.formatted(
                                date: .long,
                                time: .omitted
                            )
                        )
                        .bold()

                        Text(
                            "\(s.warehouse.rawValue) · \(s.plannedRings)K · \(s.status.rawValue)"
                        )
                        .foregroundStyle(.secondary)

                        let rs = routes.filter {
                            $0.shiftID == s.id && $0.deletedAt == nil
                        }

                        if !rs.isEmpty {
                            Text(
                                "Трассы: "
                                    + rs.map {
                                        "#\($0.sequence) \($0.type.rawValue)"
                                    }
                                    .joined(separator: ", ")
                            )
                            .font(.caption)
                        }
                    }
                }
                .buttonStyle(.plain)
                .swipeActions {
                    Button(role: .destructive) {
                        s.deletedAt = Date.now
                        try? ctx.save()
                    } label: {
                        Label("Удалить", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Смены")
        .sheet(item: $edit) {
            ShiftEditExisting(shift: $0)
        }
    }
}

struct ShiftEditExisting: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var ctx

    let shift: Shift

    @State var plan = 4
    @State var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Stepper("План: \(plan)K", value: $plan, in: 1...20)
                TextField("Комментарий", text: $note)

                if !shift.closeReason.isEmpty {
                    LabeledContent(
                        "Причина закрытия",
                        value: shift.closeReason
                    )
                }
            }
            .navigationTitle("Изменить смену")
            .onAppear {
                plan = shift.plannedRings
                note = shift.note
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        shift.plannedRings = plan
                        shift.note = note
                        try? ctx.save()
                        dismiss()
                    }
                }
            }
        }
    }
}

enum FinanceFilter {
    case positive
    case penalty
}

struct FinanceView: View {
    @Environment(\.modelContext) var ctx
    @Query(sort: \FinancialEntry.date, order: .reverse) var es: [FinancialEntry]

    let filter: FinanceFilter

    @State var add = false
    @State var importPhoto = false

    var vis: [FinancialEntry] {
        es.filter {
            $0.deletedAt == nil
                && (filter == .positive
                    ? $0.kind.positive
                    : $0.kind == .penalty)
        }
    }

    var body: some View {
        List {
            Section {
                Button("Добавить вручную") {
                    add = true
                }

                Button("Добавить по фото / OCR") {
                    importPhoto = true
                }
            }

            ForEach(vis) { e in
                HStack {
                    VStack(alignment: .leading) {
                        Text(e.kind.rawValue).bold()

                        Text(e.source + " · " + e.note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(moneyKc(e.amountHellers))
                }
                .swipeActions {
                    Button(role: .destructive) {
                        e.deletedAt = Date.now
                        try? ctx.save()
                    } label: {
                        Label("Удалить", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle(
            filter == .positive ? "Бонусы" : "Штрафы"
        )
        .sheet(isPresented: $add) {
            FinanceEditor(
                kind: filter == .positive ? .bonus : .penalty
            )
        }
        .sheet(isPresented: $importPhoto) {
            FinanceOCRImport(
                kind: filter == .positive ? .bonus : .penalty
            )
        }
    }
}

struct FinanceEditor: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var ctx

    let kind: FinancialKind

    @State var amount = ""
    @State var note = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Сумма Kč", text: $amount)
                    .keyboardType(.decimalPad)

                TextField("Комментарий", text: $note)
            }
            .navigationTitle(kind.rawValue)
            .toolbar {
                KeyboardDoneToolbar()

                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        ctx.insert(
                            FinancialEntry(
                                kind: kind,
                                amountHellers: Int64(
                                    (
                                        Double(
                                            amount.replacingOccurrences(
                                                of: ",",
                                                with: "."
                                            )
                                        ) ?? 0
                                    ) * 100
                                ),
                                note: note
                            )
                        )
                        try? ctx.save()
                        dismiss()
                    }
                }
            }
        }
    }
}

struct FinanceOCRImport: View {
    let kind: FinancialKind

    var body: some View {
        ScannerView()
            .navigationTitle(kind.rawValue)
    }
}

struct FuelView: View {
    @Environment(\.modelContext) var ctx
    @Query(sort: \FuelEntry.date, order: .reverse) var es: [FuelEntry]

    @State var add = false

    var body: some View {
        List {
            ForEach(es.filter { $0.deletedAt == nil }) { e in
                VStack(alignment: .leading) {
                    Text(moneyKc(e.amountHellers)).bold()

                    Text(
                        "\(e.liters, specifier: "%.1f") л · \(e.distanceKm, specifier: "%.1f") км · \(e.note)"
                    )
                    .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Дизель и авторасходы")
        .toolbar {
            Button {
                add = true
            } label: {
                Image(systemName: "plus")
            }
        }
        .sheet(isPresented: $add) {
            FuelEditor()
        }
    }
}

struct FuelEditor: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var ctx

    @State var amount = ""
    @State var liters = ""
    @State var km = ""
    @State var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Заправка / расход") {
                    TextField("Сумма Kč", text: $amount)
                        .keyboardType(.decimalPad)

                    TextField("Литры", text: $liters)
                        .keyboardType(.decimalPad)

                    TextField("Километраж", text: $km)
                        .keyboardType(.decimalPad)

                    TextField("Комментарий", text: $note)
                }
            }
            .navigationTitle("Авторасход")
            .toolbar {
                KeyboardDoneToolbar()

                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        ctx.insert(
                            FuelEntry(
                                amountHellers: Int64(
                                    (
                                        Double(
                                            amount.replacingOccurrences(
                                                of: ",",
                                                with: "."
                                            )
                                        ) ?? 0
                                    ) * 100
                                ),
                                liters: Double(
                                    liters.replacingOccurrences(
                                        of: ",",
                                        with: "."
                                    )
                                ) ?? 0,
                                distanceKm: Double(
                                    km.replacingOccurrences(
                                        of: ",",
                                        with: "."
                                    )
                                ) ?? 0,
                                note: note
                            )
                        )
                        try? ctx.save()
                        dismiss()
                    }
                }
            }
        }
    }
}

struct GoalsView: View {
    @Environment(\.modelContext) var ctx
    @Query var gs: [Goal]

    @State var add = false
    @State var edit: Goal?

    var body: some View {
        List {
            Button("Добавить цель") {
                add = true
            }

            ForEach(gs) { g in
                Button {
                    edit = g
                } label: {
                    HStack {
                        Text(g.month)
                        Spacer()
                        Text("\(g.targetOrders) заказов")
                    }
                }
                .swipeActions {
                    Button(role: .destructive) {
                        ctx.delete(g)
                        try? ctx.save()
                    } label: {
                        Label("Удалить", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Цели")
        .sheet(isPresented: $add) {
            GoalEditor(goal: nil)
        }
        .sheet(item: $edit) {
            GoalEditor(goal: $0)
        }
    }
}

struct GoalEditor: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var ctx

    let goal: Goal?

    @State var orders = ""
    @State var money = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Цель заказов", text: $orders)
                    .keyboardType(.numberPad)

                TextField("Цель Kč", text: $money)
                    .keyboardType(.decimalPad)
            }
            .navigationTitle(
                goal == nil ? "Новая цель" : "Изменить цель"
            )
            .onAppear {
                if let g = goal {
                    orders = String(g.targetOrders)
                    money = String(Double(g.targetHellers) / 100)
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        if let g = goal {
                            g.targetOrders = Int(orders) ?? 0
                            g.targetHellers = Int64(
                                (Double(money) ?? 0) * 100
                            )
                        } else {
                            ctx.insert(
                                Goal(
                                    month: Date.now.monthKey,
                                    targetOrders: Int(orders) ?? 0,
                                    targetHellers: Int64(
                                        (Double(money) ?? 0) * 100
                                    )
                                )
                            )
                        }

                        try? ctx.save()
                        dismiss()
                    }
                }
            }
        }
    }
}

struct DeveloperView: View {
    @StateObject var sec = DeveloperSecurity()

    @State var p = ""
    @State var p2 = ""

    var body: some View {
        Form {
            if sec.unlocked {
                Section("Developer Mode") {
                    Label(
                        "Разблокирован",
                        systemImage: "checkmark.shield.fill"
                    )
                    .foregroundStyle(Color.kxGreen)

                    Toggle(
                        "Face ID",
                        isOn: $sec.faceEnabled
                    )

                    Button(
                        "Сбросить PIN",
                        role: .destructive
                    ) {
                        sec.reset()
                    }
                }

                Section("Возможности") {
                    Text(
                        "Закрытые трассы и смены можно редактировать из их карточек; Developer Mode снимает ограничения на служебные поля."
                    )
                }
            } else if !sec.hasPIN {
                Section("Создать PIN") {
                    SecureField("Новый PIN", text: $p)
                        .keyboardType(.numberPad)

                    SecureField("Повторите PIN", text: $p2)
                        .keyboardType(.numberPad)

                    Button("Создать PIN") {
                        _ = sec.setPIN(p, p2)
                    }
                }
            } else {
                Section("Вход") {
                    SecureField("PIN", text: $p)
                        .keyboardType(.numberPad)

                    Button("Подтвердить") {
                        sec.verify(p)
                    }

                    if sec.faceEnabled {
                        Button("Войти через Face ID") {
                            Task {
                                await sec.biometric()
                            }
                        }
                    }
                }
            }

            if !sec.error.isEmpty {
                Text(sec.error)
                    .foregroundStyle(.red)
            }
        }
        .navigationTitle("Developer Mode")
        .toolbar {
            KeyboardDoneToolbar()
        }
    }
}
