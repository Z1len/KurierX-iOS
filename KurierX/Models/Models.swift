import Foundation
import SwiftData

enum Warehouse: String, Codable, CaseIterable, Identifiable, Equatable {
    case liboc = "Liboc"
    case chrastany = "Chrášťany"
    case horniPocernice = "Horní Počernice"
    var id: String { rawValue }
}

enum RouteType: String, Codable, CaseIterable, Identifiable, Equatable {
    case ot = "OT"
    case region = "Region"
    case express = "Express"
    var id: String { rawValue }
    var rings: Int { 1 }
}

enum ShiftStatus: String, Codable, CaseIterable, Equatable { case planned, active, complete, partial }

enum FinancialKind: String, Codable, CaseIterable, Identifiable, Equatable {
    case bonus = "Бонус"
    case compensation = "Компенсация"
    case penalty = "Штраф"
    var id: String { rawValue }
    var positive: Bool { self != .penalty }
}

enum AuditKind: String, Codable { case create, edit, delete, restore, importData, security, backup }

@Model final class Shift {
    @Attribute(.unique) var id: UUID
    var date: Date
    var warehouseRaw: String
    var statusRaw: String
    var plannedRings: Int
    var startedAt: Date?
    var endedAt: Date?
    var morningOdometer: Double?
    var queueOdometer: Double?
    var closingOdometer: Double?
    var note: String
    var deletedAt: Date?

    init(date: Date = Date.now, warehouse: Warehouse = .liboc, status: ShiftStatus = .planned, plannedRings: Int = 4) {
        id = UUID(); self.date = date; warehouseRaw = warehouse.rawValue; statusRaw = status.rawValue
        self.plannedRings = plannedRings; note = ""
    }
    var warehouse: Warehouse { get { Warehouse(rawValue: warehouseRaw) ?? .liboc } set { warehouseRaw = newValue.rawValue } }
    var status: ShiftStatus { get { ShiftStatus(rawValue: statusRaw) ?? .planned } set { statusRaw = newValue.rawValue } }
    var durationMinutes: Int {
        guard let startedAt, let endedAt else { return 0 }
        return max(0, Int(endedAt.timeIntervalSince(startedAt) / 60))
    }
}

@Model final class Route {
    @Attribute(.unique) var id: UUID
    var shiftID: UUID
    var date: Date
    var sequence: Int
    var typeRaw: String
    var warehouseRaw: String
    var plannedOrders: Int
    var factualOrders: Int
    var tipsHellers: Int64
    var distanceKm: Double?
    var grossHellers: Int64
    var note: String
    var deletedAt: Date?

    init(shiftID: UUID, date: Date = Date.now, sequence: Int, type: RouteType, warehouse: Warehouse = .liboc, plannedOrders: Int = 0, factualOrders: Int = 0, tipsHellers: Int64 = 0, distanceKm: Double? = nil, grossHellers: Int64 = 0) {
        id = UUID(); self.shiftID = shiftID; self.date = date; self.sequence = sequence; typeRaw = type.rawValue; warehouseRaw = warehouse.rawValue
        self.plannedOrders = plannedOrders; self.factualOrders = factualOrders; self.tipsHellers = tipsHellers; self.distanceKm = distanceKm; self.grossHellers = grossHellers; note = ""
    }
    var type: RouteType { get { RouteType(rawValue: typeRaw) ?? .ot } set { typeRaw = newValue.rawValue } }
    var warehouse: Warehouse { get { Warehouse(rawValue: warehouseRaw) ?? .liboc } set { warehouseRaw = newValue.rawValue } }
}

@Model final class Customer {
    @Attribute(.unique) var id: UUID
    var routeID: UUID
    var date: Date
    var routeSequence: Int
    var routeTypeRaw: String
    var firstName: String
    var lastName: String
    var address: String
    var bags: Int
    var tipsHellers: Int64
    var note: String
    var deletedAt: Date?

    init(routeID: UUID, date: Date = Date.now, routeSequence: Int = 1, routeType: RouteType = .ot, firstName: String, lastName: String = "", address: String, bags: Int = 0, tipsHellers: Int64 = 0) {
        id = UUID(); self.routeID = routeID; self.date = date; self.routeSequence = routeSequence; routeTypeRaw = routeType.rawValue
        self.firstName = firstName; self.lastName = lastName; self.address = address; self.bags = bags; self.tipsHellers = tipsHellers; note = ""
    }
}

@Model final class FinancialEntry {
    @Attribute(.unique) var id: UUID
    var date: Date
    var kindRaw: String
    var amountHellers: Int64
    var note: String
    var source: String
    var deletedAt: Date?
    init(date: Date = Date.now, kind: FinancialKind, amountHellers: Int64, note: String = "", source: String = "Ручной ввод") {
        id = UUID(); self.date = date; kindRaw = kind.rawValue; self.amountHellers = amountHellers; self.note = note; self.source = source
    }
    var kind: FinancialKind { get { FinancialKind(rawValue: kindRaw) ?? .bonus } set { kindRaw = newValue.rawValue } }
}

@Model final class Goal {
    @Attribute(.unique) var month: String
    var targetOrders: Int
    var targetHellers: Int64
    init(month: String, targetOrders: Int, targetHellers: Int64 = 0) { self.month = month; self.targetOrders = targetOrders; self.targetHellers = targetHellers }
}

@Model final class CalendarPlan {
    @Attribute(.unique) var id: UUID
    var date: Date
    var warehouseRaw: String
    var startMinutes: Int
    var plannedRings: Int
    var note: String
    init(date: Date, warehouse: Warehouse, startMinutes: Int, plannedRings: Int) {
        id = UUID(); self.date = date; warehouseRaw = warehouse.rawValue; self.startMinutes = startMinutes; self.plannedRings = plannedRings; note = ""
    }
    var warehouse: Warehouse { get { Warehouse(rawValue: warehouseRaw) ?? .liboc } set { warehouseRaw = newValue.rawValue } }
}

@Model final class FuelEntry {
    @Attribute(.unique) var id: UUID
    var date: Date
    var amountHellers: Int64
    var liters: Double
    var distanceKm: Double
    var note: String
    var deletedAt: Date?
    init(date: Date = Date.now, amountHellers: Int64 = 0, liters: Double = 0, distanceKm: Double = 0, note: String = "") {
        id = UUID(); self.date = date; self.amountHellers = amountHellers; self.liters = liters; self.distanceKm = distanceKm; self.note = note
    }
}

@Model final class AdvanceEntry {
    @Attribute(.unique) var id: UUID
    var date: Date
    var amountHellers: Int64
    var note: String
    var deletedAt: Date?
    init(date: Date = Date.now, amountHellers: Int64 = 0, note: String = "") { id = UUID(); self.date = date; self.amountHellers = amountHellers; self.note = note }
}

@Model final class SalaryEntry {
    @Attribute(.unique) var id: UUID
    var month: String
    var paidHellers: Int64
    var note: String
    var paidAt: Date
    init(month: String, paidHellers: Int64, note: String = "", paidAt: Date = Date.now) { id = UUID(); self.month = month; self.paidHellers = paidHellers; self.note = note; self.paidAt = paidAt }
}

@Model final class AuditEntry {
    @Attribute(.unique) var id: UUID
    var date: Date
    var kindRaw: String
    var title: String
    var details: String
    init(date: Date = Date.now, kind: AuditKind, title: String, details: String = "") { id = UUID(); self.date = date; kindRaw = kind.rawValue; self.title = title; self.details = details }
}

@Model final class AppPreference {
    @Attribute(.unique) var key: String
    var value: String
    init(key: String, value: String) { self.key = key; self.value = value }
}

func moneyKc(_ hellers: Int64) -> String {
    let number = Double(hellers) / 100.0
    let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = "CZK"; f.locale = Locale(identifier: "cs_CZ"); f.maximumFractionDigits = 0
    return f.string(from: NSNumber(value: number)) ?? "\(Int(number)) Kč"
}

func minutesLabel(_ minutes: Int) -> String {
    let h = max(0, minutes) / 60; let m = max(0, minutes) % 60
    return h > 0 ? "\(h) ч \(m) мин" : "\(m) мин"
}

extension Date {
    var monthKey: String {
        let c = Calendar.current.dateComponents([.year, .month], from: self)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }
    func sameDay(as other: Date) -> Bool { Calendar.current.isDate(self, inSameDayAs: other) }
}
