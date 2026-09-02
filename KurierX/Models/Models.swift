import Foundation
import SwiftData

enum Warehouse:String,Codable,CaseIterable,Identifiable{case liboc = "Liboc",chrastany = "Chrášťany",horniPocernice = "Horní Počernice";var id:String{rawValue}}
enum RouteType:String,Codable,CaseIterable,Identifiable{case ot = "OT",region = "Region",express = "Express";var id:String{rawValue};var rings:Int{1}}
enum ShiftStatus:String,Codable,CaseIterable{case planned,active,complete,partial}
enum FinancialKind:String,Codable,CaseIterable,Identifiable{case bonus = "Бонус",compensation = "Компенсация",penalty = "Штраф";var id:String{rawValue};var positive:Bool{self != .penalty}}

@Model final class Shift {
 @Attribute(.unique) var id:UUID; var date:Date; var warehouseRaw:String; var statusRaw:String; var plannedRings:Int; var startedAt:Date?; var endedAt:Date?; var queueOdometer:Double?; var closingOdometer:Double?; var closeReason:String; var note:String; var deletedAt:Date?
 init(date:Date = Date.now,warehouse:Warehouse = .liboc,status:ShiftStatus = .planned,plannedRings:Int = 4){id = UUID();self.date = date;warehouseRaw = warehouse.rawValue;statusRaw = status.rawValue;self.plannedRings = plannedRings;closeReason = "";note = ""}
 var warehouse:Warehouse{get{Warehouse(rawValue:warehouseRaw) ?? .liboc}set{warehouseRaw = newValue.rawValue}};var status:ShiftStatus{get{ShiftStatus(rawValue:statusRaw) ?? .planned}set{statusRaw = newValue.rawValue}}
 var durationMinutes:Int{guard let a = startedAt,let b = endedAt else{return 0};return max(0,Int(b.timeIntervalSince(a)/60))}
}
@Model final class Route {
 @Attribute(.unique) var id:UUID; var shiftID:UUID; var date:Date; var sequence:Int; var typeRaw:String; var warehouseRaw:String; var factualOrders:Int; var distanceKm:Double?; var note:String; var deletedAt:Date?
 init(shiftID:UUID,date:Date = Date.now,sequence:Int,type:RouteType,warehouse:Warehouse = .liboc,factualOrders:Int = 0,distanceKm:Double? = nil){id = UUID();self.shiftID = shiftID;self.date = date;self.sequence = sequence;typeRaw = type.rawValue;warehouseRaw = warehouse.rawValue;self.factualOrders = factualOrders;self.distanceKm = distanceKm;note = ""}
 var type:RouteType{get{RouteType(rawValue:typeRaw) ?? .ot}set{typeRaw = newValue.rawValue}};var warehouse:Warehouse{get{Warehouse(rawValue:warehouseRaw) ?? .liboc}set{warehouseRaw = newValue.rawValue}}
}
@Model final class Customer {
 @Attribute(.unique) var id:UUID; var routeID:UUID?; var date:Date; var routeSequence:Int; var routeTypeRaw:String; var firstName:String; var lastName:String; var address:String; var bags:Int; var note:String; var deletedAt:Date?
 init(routeID:UUID? = nil,date:Date = Date.now,routeSequence:Int = 1,routeType:RouteType = .ot,firstName:String,lastName:String = "",address:String,bags:Int = 0){id = UUID();self.routeID = routeID;self.date = date;self.routeSequence = routeSequence;routeTypeRaw = routeType.rawValue;self.firstName = firstName;self.lastName = lastName;self.address = address;self.bags = bags;note = ""}
}
@Model final class CalendarPlan {
 @Attribute(.unique) var id:UUID; var date:Date; var warehouseRaw:String; var startMinutes:Int; var plannedRings:Int; var note:String
 init(date:Date,warehouse:Warehouse,startMinutes:Int,plannedRings:Int){id = UUID();self.date = date;warehouseRaw = warehouse.rawValue;self.startMinutes = startMinutes;self.plannedRings = plannedRings;note = ""}
 var warehouse:Warehouse{get{Warehouse(rawValue:warehouseRaw) ?? .liboc}set{warehouseRaw = newValue.rawValue}}
}
@Model final class FinancialEntry {@Attribute(.unique)var id:UUID;var date:Date;var kindRaw:String;var amountHellers:Int64;var note:String;var source:String;var deletedAt:Date?;init(date:Date = Date.now,kind:FinancialKind,amountHellers:Int64,note:String = "",source:String = "Ручной ввод"){id = UUID();self.date = date;kindRaw = kind.rawValue;self.amountHellers = amountHellers;self.note = note;self.source = source};var kind:FinancialKind{get{FinancialKind(rawValue:kindRaw) ?? .bonus}set{kindRaw = newValue.rawValue}}}
@Model final class FuelEntry {@Attribute(.unique)var id:UUID;var date:Date;var amountHellers:Int64;var liters:Double;var distanceKm:Double;var note:String;var deletedAt:Date?;init(date:Date = Date.now,amountHellers:Int64 = 0,liters:Double = 0,distanceKm:Double = 0,note:String = ""){id = UUID();self.date = date;self.amountHellers = amountHellers;self.liters = liters;self.distanceKm = distanceKm;self.note = note}}
@Model final class Goal {@Attribute(.unique)var id:UUID;var month:String;var targetOrders:Int;var targetHellers:Int64;init(month:String,targetOrders:Int,targetHellers:Int64 = 0){id = UUID();self.month = month;self.targetOrders = targetOrders;self.targetHellers = targetHellers}}
@Model final class AppPreference {@Attribute(.unique)var key:String;var value:String;init(key:String,value:String){self.key = key;self.value = value}}

func moneyKc(_ h:Int64)->String{let n = Double(h)/100;let f = NumberFormatter();f.numberStyle = .currency;f.currencyCode = "CZK";f.locale = Locale(identifier:"cs_CZ");f.maximumFractionDigits = 0;return f.string(from:NSNumber(value:n)) ?? "\(Int(n)) Kč"}
extension Date{var monthKey:String{let c = Calendar.current.dateComponents([.year,.month],from:self);return String(format:"%04d-%02d",c.year ?? 0,c.month ?? 0)};func sameDay(as o:Date)->Bool{Calendar.current.isDate(self,inSameDayAs:o)}}
