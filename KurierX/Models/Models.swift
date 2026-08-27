import Foundation
import SwiftData

enum Warehouse: String, Codable, CaseIterable { case liboc = "Liboc", chrastany = "CH", horniPocernice = "HP" }
enum RouteType: String, Codable, CaseIterable { case ot = "OT", region = "REG", express = "EXP" }
enum ShiftStatus: String, Codable { case planned, active, complete, partial }
enum FinancialKind: String, Codable, CaseIterable { case bonus = "Бонус", penalty = "Штраф" }

@Model final class Shift {
    @Attribute(.unique) var id: UUID
    var date: Date
    var warehouseRaw: String
    var statusRaw: String
    var startedAt: Date?
    var endedAt: Date?
    init(date: Date = .now, warehouse: Warehouse = .liboc, status: ShiftStatus = .planned) {
        id = UUID(); self.date = date; warehouseRaw = warehouse.rawValue; statusRaw = status.rawValue
    }
    var warehouse: Warehouse { get { Warehouse(rawValue: warehouseRaw) ?? .liboc } set { warehouseRaw = newValue.rawValue } }
}

@Model final class Route {
    @Attribute(.unique) var id: UUID
    var shiftID: UUID
    var sequence: Int
    var typeRaw: String
    var plannedOrders: Int
    var factualOrders: Int
    var tipsHellers: Int64
    var deletedAt: Date?
    init(shiftID: UUID, sequence: Int, type: RouteType, plannedOrders: Int = 0, factualOrders: Int = 0, tipsHellers: Int64 = 0) {
        id = UUID(); self.shiftID = shiftID; self.sequence = sequence; typeRaw = type.rawValue; self.plannedOrders = plannedOrders; self.factualOrders = factualOrders; self.tipsHellers = tipsHellers
    }
}

@Model final class Customer {
    @Attribute(.unique) var id: UUID
    var routeID: UUID
    var firstName: String
    var lastName: String
    var address: String
    var bags: Int
    var tipsHellers: Int64
    var deletedAt: Date?
    init(routeID: UUID, firstName: String, lastName: String = "", address: String, bags: Int = 0, tipsHellers: Int64 = 0) {
        id = UUID(); self.routeID = routeID; self.firstName = firstName; self.lastName = lastName; self.address = address; self.bags = bags; self.tipsHellers = tipsHellers
    }
}

@Model final class FinancialEntry {
    @Attribute(.unique) var id: UUID
    var date: Date
    var kindRaw: String
    var amountHellers: Int64
    var note: String
    var deletedAt: Date?
    init(date: Date = .now, kind: FinancialKind, amountHellers: Int64, note: String = "") { id = UUID(); self.date = date; kindRaw = kind.rawValue; self.amountHellers = amountHellers; self.note = note }
}

@Model final class Goal {
    @Attribute(.unique) var month: String
    var targetOrders: Int
    init(month: String, targetOrders: Int) { self.month = month; self.targetOrders = targetOrders }
}
