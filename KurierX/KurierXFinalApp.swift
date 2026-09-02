import Charts
import CryptoKit
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import LocalAuthentication
import PhotosUI
import Security
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import Vision

// MARK: - Application

@main
struct KurierXApp: App {
  @StateObject private var session: SessionStore
  @StateObject private var developerAccess: DeveloperAccess
  private let modelContainer: ModelContainer

  init() {
    if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil,
      FirebaseApp.app() == nil
    {
      FirebaseApp.configure()
    }

    _session = StateObject(wrappedValue: SessionStore())
    _developerAccess = StateObject(wrappedValue: DeveloperAccess())
    modelContainer = PersistenceFactory.makeContainer()
  }

  var body: some Scene {
    WindowGroup {
      RootView()
        .environmentObject(session)
        .environmentObject(developerAccess)
        .preferredColorScheme(.dark)
        .tint(.kxGreen)
    }
    .modelContainer(modelContainer)
  }
}

enum PersistenceFactory {
  static var recoveryMessage: String?

  static func makeContainer() -> ModelContainer {
    let schema = Schema([
      Shift.self,
      Route.self,
      Customer.self,
      CalendarPlan.self,
      FinancialEntry.self,
      FuelEntry.self,
      AdvanceEntry.self,
      SalaryPayment.self,
      Goal.self,
      StatisticsSnapshot.self,
      AuditEntry.self,
      AppPreference.self,
    ])

    do {
      return try ModelContainer(for: schema)
    } catch {
      // Never terminate the app because an older test database cannot be migrated.
      // A separate recovery store is opened and the original store remains untouched.
      recoveryMessage =
        "Старая локальная база несовместима с новой схемой. KurierX открыл чистую восстановительную базу; старая база не удалена."
      let recoveryConfiguration = ModelConfiguration(
        "KurierX-Recovery-v1",
        schema: schema
      )
      do {
        return try ModelContainer(
          for: schema,
          configurations: [recoveryConfiguration]
        )
      } catch {
        recoveryMessage = "Постоянное хранилище недоступно. Данные этой сессии временные."
        let memory = ModelConfiguration(
          "KurierX-Memory",
          schema: schema,
          isStoredInMemoryOnly: true
        )
        return try! ModelContainer(for: schema, configurations: [memory])
      }
    }
  }
}

// MARK: - Domain types

enum Warehouse: String, Codable, CaseIterable, Identifiable, Equatable {
  case liboc = "Liboc"
  case chrastany = "Chrášťany"
  case horniPocernice = "Horní Počernice"

  var id: String { rawValue }
  var shortCode: String {
    switch self {
    case .liboc: return "L"
    case .chrastany: return "CH"
    case .horniPocernice: return "HP"
    }
  }
}

enum RouteType: String, Codable, CaseIterable, Identifiable, Equatable {
  case ot = "OT"
  case region = "Region"
  case express = "Express"

  var id: String { rawValue }
  var rings: Int { self == .region ? 2 : 1 }
}

enum ShiftStatus: String, Codable, CaseIterable, Identifiable {
  case planned = "PLANNED"
  case active = "ACTIVE"
  case complete = "COMPLETE"
  case partial = "PARTIAL"

  var id: String { rawValue }
  var displayName: String {
    switch self {
    case .planned: return "Запланирована"
    case .active: return "Активна"
    case .complete: return "Завершена"
    case .partial: return "Закрыта досрочно"
    }
  }
}

enum FinancialKind: String, Codable, CaseIterable, Identifiable {
  case bonus = "Бонус"
  case compensation = "Компенсация"
  case penalty = "Штраф"

  var id: String { rawValue }
  var positive: Bool { self != .penalty }
}

enum AutoExpenseKind: String, Codable, CaseIterable, Identifiable {
  case fuel = "Дизель / топливо"
  case parking = "Парковка"
  case toll = "Платная дорога"
  case service = "Ремонт / сервис"
  case wash = "Мойка"
  case other = "Другой авторасход"

  var id: String { rawValue }
}

enum DataSource: String, Codable {
  case ocr = "OCR"
  case manual = "Ручной ввод"
  case automatic = "Авторасчёт"
  case importData = "Импорт"
  case correction = "Исправление"
}

// MARK: - SwiftData models

@Model
final class Shift {
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
  var closeReason: String
  var note: String
  var sourceRaw: String?
  var deletedAt: Date?

  init(
    id: UUID = UUID(),
    date: Date = Date.now,
    warehouse: Warehouse = .liboc,
    status: ShiftStatus = .planned,
    plannedRings: Int = 4,
    startedAt: Date? = nil,
    endedAt: Date? = nil,
    queueOdometer: Double? = nil,
    closingOdometer: Double? = nil,
    closeReason: String = "",
    note: String = "",
    source: DataSource = .manual
  ) {
    self.id = id
    self.date = date
    warehouseRaw = warehouse.rawValue
    statusRaw = status.rawValue
    self.plannedRings = plannedRings
    self.startedAt = startedAt
    self.endedAt = endedAt
    self.queueOdometer = queueOdometer
    self.closingOdometer = closingOdometer
    self.closeReason = closeReason
    self.note = note
    sourceRaw = source.rawValue
  }

  var warehouse: Warehouse {
    get { Warehouse(rawValue: warehouseRaw) ?? .liboc }
    set { warehouseRaw = newValue.rawValue }
  }

  var status: ShiftStatus {
    get { ShiftStatus(rawValue: statusRaw) ?? .planned }
    set { statusRaw = newValue.rawValue }
  }

  var durationMinutes: Int {
    guard let startedAt, let endedAt else { return 0 }
    return max(0, Int(endedAt.timeIntervalSince(startedAt) / 60))
  }
}

@Model
final class Route {
  @Attribute(.unique) var id: UUID
  var shiftID: UUID
  var date: Date
  var sequence: Int
  var typeRaw: String
  var warehouseRaw: String
  var factualOrders: Int
  var distanceKm: Double?
  var externalRouteID: String?
  var startedAt: Date?
  var finishedAt: Date?
  var confirmed: Bool
  var sourceRaw: String?
  var note: String
  var deletedAt: Date?

  init(
    id: UUID = UUID(),
    shiftID: UUID,
    date: Date = Date.now,
    sequence: Int,
    type: RouteType,
    warehouse: Warehouse = .liboc,
    factualOrders: Int = 0,
    distanceKm: Double? = nil,
    externalRouteID: String? = nil,
    confirmed: Bool = true,
    source: DataSource = .manual,
    note: String = ""
  ) {
    self.id = id
    self.shiftID = shiftID
    self.date = date
    self.sequence = sequence
    typeRaw = type.rawValue
    warehouseRaw = warehouse.rawValue
    self.factualOrders = factualOrders
    self.distanceKm = distanceKm
    self.externalRouteID = externalRouteID
    self.confirmed = confirmed
    sourceRaw = source.rawValue
    self.note = note
  }

  var type: RouteType {
    get { RouteType(rawValue: typeRaw) ?? .ot }
    set { typeRaw = newValue.rawValue }
  }

  var warehouse: Warehouse {
    get { Warehouse(rawValue: warehouseRaw) ?? .liboc }
    set { warehouseRaw = newValue.rawValue }
  }
}

@Model
final class Customer {
  @Attribute(.unique) var id: UUID
  var routeID: UUID?
  var date: Date
  var routeSequence: Int
  var routeTypeRaw: String
  var position: Int
  var photoOrder: Int
  var firstName: String
  var lastName: String
  var address: String
  var normalizedAddress: String?
  var addressVerified: Bool
  var bags: Int
  var tipsHellers: Int64?
  var sourceRaw: String?
  var note: String
  var deletedAt: Date?

  init(
    id: UUID = UUID(),
    routeID: UUID? = nil,
    date: Date = Date.now,
    routeSequence: Int = 1,
    routeType: RouteType = .ot,
    position: Int = 0,
    photoOrder: Int = 0,
    firstName: String,
    lastName: String = "",
    address: String,
    normalizedAddress: String? = nil,
    addressVerified: Bool = false,
    bags: Int = 0,
    tipsHellers: Int64 = 0,
    source: DataSource = .manual,
    note: String = ""
  ) {
    self.id = id
    self.routeID = routeID
    self.date = date
    self.routeSequence = routeSequence
    routeTypeRaw = routeType.rawValue
    self.position = position
    self.photoOrder = photoOrder
    self.firstName = firstName
    self.lastName = lastName
    self.address = address
    self.normalizedAddress = normalizedAddress
    self.addressVerified = addressVerified
    self.bags = bags
    self.tipsHellers = tipsHellers
    sourceRaw = source.rawValue
    self.note = note
  }

  var routeType: RouteType {
    get { RouteType(rawValue: routeTypeRaw) ?? .ot }
    set { routeTypeRaw = newValue.rawValue }
  }

  var tipValue: Int64 { tipsHellers ?? 0 }
  var displayName: String {
    (firstName + " " + lastName).trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

@Model
final class CalendarPlan {
  @Attribute(.unique) var id: UUID
  var date: Date
  var warehouseRaw: String
  var startMinutes: Int
  var plannedRings: Int
  var sourceRaw: String?
  var confidence: Double?
  var note: String
  var deletedAt: Date?

  init(
    id: UUID = UUID(),
    date: Date,
    warehouse: Warehouse,
    startMinutes: Int,
    plannedRings: Int,
    source: DataSource = .manual,
    confidence: Double? = nil,
    note: String = ""
  ) {
    self.id = id
    self.date = date
    warehouseRaw = warehouse.rawValue
    self.startMinutes = startMinutes
    self.plannedRings = plannedRings
    sourceRaw = source.rawValue
    self.confidence = confidence
    self.note = note
  }

  var warehouse: Warehouse {
    get { Warehouse(rawValue: warehouseRaw) ?? .liboc }
    set { warehouseRaw = newValue.rawValue }
  }
}

@Model
final class FinancialEntry {
  @Attribute(.unique) var id: UUID
  var date: Date
  var kindRaw: String
  var amountHellers: Int64
  var note: String
  var source: String
  var linkedRouteID: UUID?
  var deletedAt: Date?

  init(
    id: UUID = UUID(),
    date: Date = Date.now,
    kind: FinancialKind,
    amountHellers: Int64,
    note: String = "",
    source: String = DataSource.manual.rawValue,
    linkedRouteID: UUID? = nil
  ) {
    self.id = id
    self.date = date
    kindRaw = kind.rawValue
    self.amountHellers = amountHellers
    self.note = note
    self.source = source
    self.linkedRouteID = linkedRouteID
  }

  var kind: FinancialKind {
    get { FinancialKind(rawValue: kindRaw) ?? .bonus }
    set { kindRaw = newValue.rawValue }
  }
}

@Model
final class FuelEntry {
  @Attribute(.unique) var id: UUID
  var date: Date
  var amountHellers: Int64
  var liters: Double
  var distanceKm: Double
  var odometer: Double?
  var kindRaw: String?
  var note: String
  var deletedAt: Date?

  init(
    id: UUID = UUID(),
    date: Date = Date.now,
    amountHellers: Int64 = 0,
    liters: Double = 0,
    distanceKm: Double = 0,
    odometer: Double? = nil,
    kind: AutoExpenseKind = .fuel,
    note: String = ""
  ) {
    self.id = id
    self.date = date
    self.amountHellers = amountHellers
    self.liters = liters
    self.distanceKm = distanceKm
    self.odometer = odometer
    kindRaw = kind.rawValue
    self.note = note
  }

  var kind: AutoExpenseKind {
    get { AutoExpenseKind(rawValue: kindRaw ?? "") ?? .fuel }
    set { kindRaw = newValue.rawValue }
  }
}

@Model
final class AdvanceEntry {
  @Attribute(.unique) var id: UUID
  var date: Date
  var amountHellers: Int64
  var note: String
  var deletedAt: Date?

  init(
    id: UUID = UUID(),
    date: Date = Date.now,
    amountHellers: Int64,
    note: String = ""
  ) {
    self.id = id
    self.date = date
    self.amountHellers = amountHellers
    self.note = note
  }
}

@Model
final class SalaryPayment {
  @Attribute(.unique) var id: UUID
  var receivedDate: Date
  var amountHellers: Int64
  var periodStart: Date
  var periodEnd: Date
  var note: String
  var deletedAt: Date?

  init(
    id: UUID = UUID(),
    receivedDate: Date = Date.now,
    amountHellers: Int64,
    periodStart: Date,
    periodEnd: Date,
    note: String = ""
  ) {
    self.id = id
    self.receivedDate = receivedDate
    self.amountHellers = amountHellers
    self.periodStart = periodStart
    self.periodEnd = periodEnd
    self.note = note
  }
}

@Model
final class Goal {
  @Attribute(.unique) var id: UUID
  var month: String
  var targetOrders: Int
  var targetHellers: Int64
  var deletedAt: Date?

  init(
    id: UUID = UUID(),
    month: String,
    targetOrders: Int,
    targetHellers: Int64 = 0
  ) {
    self.id = id
    self.month = month
    self.targetOrders = targetOrders
    self.targetHellers = targetHellers
  }
}

@Model
final class StatisticsSnapshot {
  @Attribute(.unique) var id: UUID
  var capturedAt: Date
  var cumulativeOrders: Int
  var cumulativeTipsHellers: Int64?
  var deltaOrders: Int
  var rawText: String

  init(
    id: UUID = UUID(),
    capturedAt: Date = Date.now,
    cumulativeOrders: Int,
    cumulativeTipsHellers: Int64? = nil,
    deltaOrders: Int,
    rawText: String
  ) {
    self.id = id
    self.capturedAt = capturedAt
    self.cumulativeOrders = cumulativeOrders
    self.cumulativeTipsHellers = cumulativeTipsHellers
    self.deltaOrders = deltaOrders
    self.rawText = rawText
  }
}

@Model
final class AuditEntry {
  @Attribute(.unique) var id: UUID
  var createdAt: Date
  var action: String
  var entityType: String
  var entityID: String
  var details: String

  init(
    id: UUID = UUID(),
    createdAt: Date = Date.now,
    action: String,
    entityType: String,
    entityID: String,
    details: String
  ) {
    self.id = id
    self.createdAt = createdAt
    self.action = action
    self.entityType = entityType
    self.entityID = entityID
    self.details = details
  }
}

@Model
final class AppPreference {
  @Attribute(.unique) var key: String
  var value: String

  init(key: String, value: String) {
    self.key = key
    self.value = value
  }
}

// MARK: - Formatting and calculations

enum KXFormat {
  static let russianMonths = [
    "Январь", "Февраль", "Март", "Апрель", "Май", "Июнь",
    "Июль", "Август", "Сентябрь", "Октябрь", "Ноябрь", "Декабрь",
  ]

  static func money(_ hellers: Int64) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = "CZK"
    formatter.currencySymbol = "Kč"
    formatter.locale = Locale(identifier: "cs_CZ")
    formatter.maximumFractionDigits = hellers % 100 == 0 ? 0 : 2
    return formatter.string(from: NSNumber(value: Double(hellers) / 100.0))
      ?? "\(Double(hellers) / 100.0) Kč"
  }

  static func number(_ value: Double, digits: Int = 1) -> String {
    String(format: "%.*f", digits, value)
  }

  static func date(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ru_RU")
    formatter.dateFormat = "d MMMM yyyy"
    return formatter.string(from: date)
  }

  static func shortDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ru_RU")
    formatter.dateFormat = "dd.MM.yyyy"
    return formatter.string(from: date)
  }

  static func time(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ru_RU")
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: date)
  }

  static func monthTitle(_ date: Date) -> String {
    let c = Calendar.current.dateComponents([.year, .month], from: date)
    let month = max(1, min(12, c.month ?? 1))
    return "\(russianMonths[month - 1]) \(c.year ?? 0)"
  }

  static func minutesToTime(_ minutes: Int) -> String {
    String(format: "%02d:%02d", max(0, minutes) / 60, max(0, minutes) % 60)
  }

  static func duration(_ minutes: Int) -> String {
    let h = max(0, minutes) / 60
    let m = max(0, minutes) % 60
    return h > 0 ? "\(h) ч \(m) мин" : "\(m) мин"
  }
}

extension Date {
  var startOfDay: Date { Calendar.current.startOfDay(for: self) }

  var monthKey: String {
    let c = Calendar.current.dateComponents([.year, .month], from: self)
    return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
  }

  func sameDay(as other: Date) -> Bool {
    Calendar.current.isDate(self, inSameDayAs: other)
  }

  func adding(days: Int) -> Date {
    Calendar.current.date(byAdding: .day, value: days, to: self) ?? self
  }
}

struct RouteMoney {
  let base: Int64
  let regionBonus: Int64
  let tips: Int64
  var gross: Int64 { base + regionBonus + tips }
}

enum EarningsCalculator {
  static var weekdayRate: Int64 {
    let value = UserDefaults.standard.integer(forKey: "kxWeekdayRateHellers")
    return value == 0 ? 5_000 : Int64(value)
  }

  static var weekendRate: Int64 {
    let value = UserDefaults.standard.integer(forKey: "kxWeekendRateHellers")
    return value == 0 ? 8_000 : Int64(value)
  }

  static var regionBonus: Int64 {
    let value = UserDefaults.standard.integer(forKey: "kxRegionBonusHellers")
    return value == 0 ? 25_000 : Int64(value)
  }

  static func route(_ route: Route, customers: [Customer]) -> RouteMoney {
    let weekday = Calendar.current.component(.weekday, from: route.date)
    // Calendar: Sunday = 1. Friday/Saturday/Sunday have the high Android rate.
    let highRate = weekday == 1 || weekday == 6 || weekday == 7
    let rate = highRate ? weekendRate : weekdayRate
    let tips =
      customers
      .filter { $0.deletedAt == nil && $0.routeID == route.id }
      .reduce(Int64(0)) { $0 + $1.tipValue }
    return RouteMoney(
      base: Int64(max(0, route.factualOrders)) * rate,
      regionBonus: route.type == .region ? regionBonus : 0,
      tips: tips
    )
  }
}

func audit(
  _ context: ModelContext,
  action: String,
  entityType: String,
  entityID: String,
  details: String
) {
  context.insert(
    AuditEntry(
      action: action,
      entityType: entityType,
      entityID: entityID,
      details: details
    )
  )
}

// MARK: - Design system

extension Color {
  static let kxGreen = Color(red: 0.55, green: 0.78, blue: 0.27)
  static let kxGreenDim = Color(red: 0.17, green: 0.25, blue: 0.11)
  static let kxBackground = Color(red: 0.045, green: 0.052, blue: 0.058)
  static let kxSurface = Color(red: 0.095, green: 0.092, blue: 0.105)
  static let kxSurface2 = Color(red: 0.12, green: 0.12, blue: 0.135)
  static let kxSurface3 = Color(red: 0.145, green: 0.14, blue: 0.16)
  static let kxPurple = Color(red: 0.31, green: 0.22, blue: 0.55)
  static let kxDanger = Color(red: 0.72, green: 0.15, blue: 0.18)
}

struct KXCard<Content: View>: View {
  let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    content
      .padding(18)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        Color.kxSurface,
        in: RoundedRectangle(cornerRadius: 22, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
          .stroke(Color.white.opacity(0.055), lineWidth: 1)
      }
  }
}

struct KXHeader: View {
  let title: String
  var subtitle: String? = nil

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(title)
        .font(.system(size: 34, weight: .black, design: .rounded))
        .foregroundStyle(.white)

      if let subtitle {
        Text(subtitle)
          .font(.system(size: 17))
          .foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct KXBrand: View {
  var body: some View {
    HStack(spacing: 12) {
      ZStack {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(Color.black.opacity(0.6))
        Image(systemName: "paperplane.fill")
          .font(.system(size: 27, weight: .bold))
          .rotationEffect(.degrees(-35))
          .foregroundStyle(Color.kxGreen)
      }
      .frame(width: 56, height: 56)

      HStack(spacing: 0) {
        Text("Kurier")
          .font(.system(size: 34, weight: .black, design: .rounded))
        Text("X")
          .font(.system(size: 34, weight: .black, design: .rounded))
          .foregroundStyle(Color.kxGreen)
      }

      Spacer()
    }
  }
}

struct KXSectionRow: View {
  let title: String
  let subtitle: String
  let icon: String
  var accent: Color = .kxGreen

  var body: some View {
    HStack(spacing: 14) {
      ZStack {
        Circle()
          .fill(accent.opacity(0.12))
        Image(systemName: icon)
          .font(.system(size: 23, weight: .semibold))
          .foregroundStyle(accent)
      }
      .frame(width: 48, height: 48)

      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(.white)
        Text(subtitle)
          .font(.system(size: 14))
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }

      Spacer()

      Image(systemName: "chevron.right")
        .font(.system(size: 14, weight: .bold))
        .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 11)
    .background(
      Color.kxSurface2,
      in: RoundedRectangle(cornerRadius: 18, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(Color.white.opacity(0.05), lineWidth: 1)
    }
  }
}

struct KXInput: View {
  let title: String
  @Binding var text: String
  var keyboard: UIKeyboardType = .default
  var capitalization: TextInputAutocapitalization = .sentences
  var disabled = false

  var body: some View {
    TextField(title, text: $text)
      .keyboardType(keyboard)
      .textInputAutocapitalization(capitalization)
      .disabled(disabled)
      .padding(.horizontal, 14)
      .frame(height: 54)
      .background(
        disabled ? Color.kxSurface2.opacity(0.6) : Color.black.opacity(0.48),
        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .stroke(Color.white.opacity(disabled ? 0.04 : 0.08), lineWidth: 1)
      }
  }
}

struct KXSecureInput: View {
  let title: String
  @Binding var text: String

  var body: some View {
    SecureField(title, text: $text)
      .keyboardType(.numberPad)
      .padding(.horizontal, 14)
      .frame(height: 54)
      .background(
        Color.black.opacity(0.48),
        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .stroke(Color.white.opacity(0.08), lineWidth: 1)
      }
  }
}

struct KXPrimaryButton: View {
  let title: String
  var icon: String? = nil
  var disabled = false
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        if let icon { Image(systemName: icon) }
        Text(title).fontWeight(.semibold)
      }
      .frame(maxWidth: .infinity)
      .frame(height: 54)
    }
    .buttonStyle(.plain)
    .foregroundStyle(disabled ? Color.white.opacity(0.45) : Color.kxBackground)
    .background(
      disabled ? Color.white.opacity(0.14) : Color.kxGreen,
      in: RoundedRectangle(cornerRadius: 16, style: .continuous)
    )
    .disabled(disabled)
  }
}

struct KXSecondaryButton: View {
  let title: String
  var icon: String? = nil
  var destructive = false
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        if let icon { Image(systemName: icon) }
        Text(title).fontWeight(.semibold)
      }
      .frame(maxWidth: .infinity)
      .frame(height: 50)
    }
    .buttonStyle(.plain)
    .foregroundStyle(destructive ? Color.red : Color.white)
    .background(
      destructive ? Color.red.opacity(0.12) : Color.kxSurface2,
      in: RoundedRectangle(cornerRadius: 15, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 15, style: .continuous)
        .stroke(
          destructive ? Color.red.opacity(0.4) : Color.white.opacity(0.12),
          lineWidth: 1
        )
    }
  }
}

struct KXChip: View {
  let title: String
  let selected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 15, weight: .semibold))
        .padding(.horizontal, 16)
        .frame(height: 42)
    }
    .buttonStyle(.plain)
    .foregroundStyle(selected ? Color.white : Color.white.opacity(0.76))
    .background(
      selected ? Color.kxPurple : Color.kxSurface2,
      in: RoundedRectangle(cornerRadius: 12, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(Color.white.opacity(0.06), lineWidth: 1)
    }
  }
}

struct KXErrorText: View {
  let text: String

  var body: some View {
    if !text.isEmpty {
      Label(text, systemImage: "exclamationmark.triangle.fill")
        .font(.footnote)
        .foregroundStyle(.red)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

struct KeyboardDoneToolbar: ToolbarContent {
  var body: some ToolbarContent {
    ToolbarItemGroup(placement: .keyboard) {
      Spacer()
      Button("Готово") {
        UIApplication.shared.sendAction(
          #selector(UIResponder.resignFirstResponder),
          to: nil,
          from: nil,
          for: nil
        )
      }
    }
  }
}

extension View {
  func kxDismissKeyboardOnTap() -> some View {
    contentShape(Rectangle())
      .onTapGesture {
        UIApplication.shared.sendAction(
          #selector(UIResponder.resignFirstResponder),
          to: nil,
          from: nil,
          for: nil
        )
      }
  }

  func kxPageBackground() -> some View {
    background(Color.kxBackground.ignoresSafeArea())
      .toolbarBackground(Color.kxBackground, for: .navigationBar)
      .toolbarBackground(.visible, for: .navigationBar)
  }
}

// MARK: - Keychain and Developer Mode

enum KeychainStore {
  static func save(_ value: String, service: String, account: String) {
    let data = Data(value.utf8)
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    SecItemDelete(query as CFDictionary)
    var insert = query
    insert[kSecValueData as String] = data
    SecItemAdd(insert as CFDictionary, nil)
  }

  static func read(service: String, account: String) -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var result: AnyObject?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data
    else { return nil }
    return String(data: data, encoding: .utf8)
  }

  static func delete(service: String, account: String) {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    SecItemDelete(query as CFDictionary)
  }
}

@MainActor
final class DeveloperAccess: ObservableObject {
  @Published var isUnlocked = false
  @Published var errorMessage = ""
  @Published var faceEnabled: Bool {
    didSet { UserDefaults.standard.set(faceEnabled, forKey: "kxDeveloperFaceEnabled") }
  }

  private let service = "cz.courierledger.ios.developer"
  private let account = "pinHash"

  init() {
    faceEnabled = UserDefaults.standard.bool(forKey: "kxDeveloperFaceEnabled")
  }

  var hasPIN: Bool {
    KeychainStore.read(service: service, account: account) != nil
  }

  var biometricName: String {
    let context = LAContext()
    _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    switch context.biometryType {
    case .faceID: return "Face ID"
    case .touchID: return "Touch ID"
    default: return "Биометрия"
    }
  }

  @discardableResult
  func createPIN(_ first: String, repeat second: String) -> Bool {
    let pin = first.filter(\.isNumber)
    guard pin.count >= 4 else {
      errorMessage = "PIN должен содержать минимум 4 цифры."
      return false
    }
    guard pin == second.filter(\.isNumber) else {
      errorMessage = "PIN-коды не совпадают."
      return false
    }
    KeychainStore.save(Self.hash(pin), service: service, account: account)
    errorMessage = ""
    isUnlocked = true
    return true
  }

  @discardableResult
  func verify(_ value: String) -> Bool {
    guard let stored = KeychainStore.read(service: service, account: account) else {
      errorMessage = "PIN ещё не создан. Сначала установите новый PIN."
      return false
    }
    let valid = Self.hash(value.filter(\.isNumber)) == stored
    errorMessage = valid ? "" : "Неверный PIN. Попробуйте ещё раз."
    isUnlocked = valid
    return valid
  }

  func authenticateBiometrics() async {
    let context = LAContext()
    var error: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
      errorMessage = "\(biometricName) недоступен на этом устройстве."
      return
    }
    do {
      let success = try await context.evaluatePolicy(
        .deviceOwnerAuthenticationWithBiometrics,
        localizedReason: "Разблокировать Developer Mode KurierX"
      )
      isUnlocked = success
      errorMessage = success ? "" : "Не удалось подтвердить биометрию."
    } catch {
      errorMessage = "Не удалось подтвердить \(biometricName)."
    }
  }

  func lock() {
    isUnlocked = false
    errorMessage = ""
  }

  func resetPIN() {
    KeychainStore.delete(service: service, account: account)
    faceEnabled = false
    isUnlocked = false
    errorMessage = ""
  }

  private static func hash(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8))
      .map { String(format: "%02x", $0) }
      .joined()
  }
}

// MARK: - Firebase license session

@MainActor
final class SessionStore: ObservableObject {
  enum State: Equatable {
    case loading
    case needsFirebase
    case registration
    case active
    case frozen
    case revoked
    case owner
  }

  @Published var state: State = .loading
  @Published var profile: UserProfile?
  @Published var isOwner = false

  let ownerUID = "dDUHublQoTccwtzPa1hmpyiDTd23"
  private var listener: ListenerRegistration?

  init() {
    Task { await bootstrap() }
  }

  func bootstrap() async {
    guard FirebaseApp.app() != nil else {
      state = .needsFirebase
      return
    }

    if let current = Auth.auth().currentUser, current.uid == ownerUID {
      isOwner = true
      state = .owner
      return
    }

    if Auth.auth().currentUser == nil {
      do {
        _ = try await Auth.auth().signInAnonymously()
      } catch {
        state = .registration
        return
      }
    }

    guard let uid = Auth.auth().currentUser?.uid else {
      state = .registration
      return
    }
    listen(uid: uid)
  }

  private func listen(uid: String) {
    listener?.remove()
    listener = Firestore.firestore()
      .collection("users")
      .document(uid)
      .addSnapshotListener { [weak self] snapshot, _ in
        guard let self else { return }
        Task { @MainActor in
          guard let data = snapshot?.data() else {
            self.profile = nil
            self.isOwner = false
            self.state = .registration
            return
          }
          self.profile = UserProfile(data: data)
          switch data["status"] as? String ?? "" {
          case "ACTIVE": self.state = .active
          case "FROZEN": self.state = .frozen
          default: self.state = .revoked
          }
        }
      }
  }

  func activate(
    firstName: String,
    lastName: String,
    courierID: String,
    key: String
  ) async throws {
    if Auth.auth().currentUser == nil {
      _ = try await Auth.auth().signInAnonymously()
    }
    guard let uid = Auth.auth().currentUser?.uid else {
      throw LicenseError.noUser
    }

    let normalized = key.uppercased().filter { $0.isLetter || $0.isNumber }
    guard normalized.hasPrefix("KX"), normalized.count == 14 else {
      throw LicenseError.badFormat
    }

    do {
      try await activateTransaction(
        uid: uid,
        firstName: firstName,
        lastName: lastName,
        courierID: courierID,
        normalizedKey: normalized,
        platform: "IOS",
        actualPlatform: nil
      )
    } catch {
      let ns = error as NSError
      guard ns.domain == FirestoreErrorDomain,
        ns.code == FirestoreErrorCode.permissionDenied.rawValue
      else {
        throw error
      }
      // Compatibility fallback for older Firestore rules. actualPlatform still records iOS.
      try await activateTransaction(
        uid: uid,
        firstName: firstName,
        lastName: lastName,
        courierID: courierID,
        normalizedKey: normalized,
        platform: "ANDROID",
        actualPlatform: "IOS"
      )
    }
    listen(uid: uid)
  }

  private func activateTransaction(
    uid: String,
    firstName: String,
    lastName: String,
    courierID: String,
    normalizedKey: String,
    platform: String,
    actualPlatform: String?
  ) async throws {
    let hash = SHA256.hash(data: Data(normalizedKey.utf8))
      .map { String(format: "%02x", $0) }
      .joined()
    let db = Firestore.firestore()
    let keyRef = db.collection("activation_keys").document(hash)
    let userRef = db.collection("users").document(uid)
    let deviceID = Self.deviceID()
    let deviceRef = db.collection("devices").document(deviceID)

    _ = try await db.runTransaction { transaction, errorPointer -> Any? in
      do {
        let keyDocument = try transaction.getDocument(keyRef)
        guard keyDocument.exists,
          keyDocument.data()?["status"] as? String == "UNUSED"
        else {
          throw LicenseError.invalidKey
        }

        let now = FieldValue.serverTimestamp()
        transaction.updateData(
          [
            "status": "USED",
            "userId": uid,
            "deviceId": deviceID,
            "activatedAt": now,
          ], forDocument: keyRef)

        transaction.setData(
          [
            "uid": uid,
            "firstName": firstName,
            "lastName": lastName,
            "courierId": courierID,
            "deviceId": deviceID,
            "activationKeyId": hash,
            "status": "ACTIVE",
            "role": "USER",
            "createdAt": now,
            "updatedAt": now,
          ], forDocument: userRef)

        var deviceData: [String: Any] = [
          "uid": uid,
          "deviceId": deviceID,
          "platform": platform,
          "manufacturer": "Apple",
          "model": UIDevice.current.model,
          "androidVersion": "iOS \(UIDevice.current.systemVersion)",
          "iosVersion": UIDevice.current.systemVersion,
          "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? "1.0",
          "status": "ACTIVE",
          "createdAt": now,
          "lastSeenAt": now,
        ]
        if let actualPlatform { deviceData["actualPlatform"] = actualPlatform }
        transaction.setData(deviceData, forDocument: deviceRef)
        return nil
      } catch {
        errorPointer?.pointee = error as NSError
        return nil
      }
    }
  }

  func ownerLogin(email: String, password: String) async throws {
    listener?.remove()
    try? Auth.auth().signOut()
    let result = try await Auth.auth().signIn(withEmail: email, password: password)
    guard result.user.uid == ownerUID else {
      try? Auth.auth().signOut()
      throw LicenseError.notOwner
    }
    isOwner = true
    state = .owner
  }

  func leaveOwnerToActivation() async {
    listener?.remove()
    try? Auth.auth().signOut()
    profile = nil
    isOwner = false
    do { _ = try await Auth.auth().signInAnonymously() } catch {}
    state = .registration
  }

  func signOutUser() async {
    listener?.remove()
    try? Auth.auth().signOut()
    profile = nil
    isOwner = false
    do { _ = try await Auth.auth().signInAnonymously() } catch {}
    state = .registration
  }

  static func deviceID() -> String {
    let service = "cz.courierledger.ios.device"
    let account = "stableID"
    if let existing = KeychainStore.read(service: service, account: account) {
      return existing
    }
    let source = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
    let value = SHA256.hash(data: Data(("IOS|" + source).utf8))
      .map { String(format: "%02x", $0) }
      .joined()
    KeychainStore.save(value, service: service, account: account)
    return value
  }
}

struct UserProfile {
  let firstName: String
  let lastName: String
  let courierID: String
  let status: String

  init(data: [String: Any]) {
    firstName = data["firstName"] as? String ?? ""
    lastName = data["lastName"] as? String ?? ""
    courierID = data["courierId"] as? String ?? ""
    status = data["status"] as? String ?? ""
  }
}

enum LicenseError: LocalizedError {
  case noUser
  case badFormat
  case invalidKey
  case notOwner

  var errorDescription: String? {
    switch self {
    case .noUser: return "Нет Firebase-сессии."
    case .badFormat: return "Ключ имеет неверный формат."
    case .invalidKey: return "Ключ недействителен или уже использован."
    case .notOwner: return "Нет OWNER-доступа."
    }
  }
}

// MARK: - OCR engine

struct OCRLine: Identifiable, Hashable {
  let id = UUID()
  let text: String
  let confidence: Float
  /// Normalized rectangle with origin at the top-left.
  let rect: CGRect

  var centerX: CGFloat { rect.midX }
  var centerY: CGFloat { rect.midY }
}

struct OCRDocument {
  let lines: [OCRLine]
  let text: String
  let confidence: Double
}

enum OCRService {
  static func recognize(_ image: UIImage) async throws -> OCRDocument {
    guard let cgImage = image.cgImage else { throw OCRError.invalidImage }

    return try await withCheckedThrowingContinuation { continuation in
      let request = VNRecognizeTextRequest { request, error in
        if let error {
          continuation.resume(throwing: error)
          return
        }

        let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
        let lines = observations.compactMap { observation -> OCRLine? in
          guard let candidate = observation.topCandidates(1).first else { return nil }
          let box = observation.boundingBox
          let topOrigin = CGRect(
            x: box.minX,
            y: 1.0 - box.maxY,
            width: box.width,
            height: box.height
          )
          return OCRLine(
            text: candidate.string.trimmingCharacters(in: .whitespacesAndNewlines),
            confidence: candidate.confidence,
            rect: topOrigin
          )
        }
        .filter { !$0.text.isEmpty }
        .sorted {
          if abs($0.rect.minY - $1.rect.minY) > 0.012 {
            return $0.rect.minY < $1.rect.minY
          }
          return $0.rect.minX < $1.rect.minX
        }

        let text = lines.map(\.text).joined(separator: "\n")
        let confidence =
          lines.isEmpty
          ? 0
          : Double(lines.map { $0.confidence }.reduce(0, +)) / Double(lines.count)
        continuation.resume(
          returning: OCRDocument(
            lines: lines,
            text: text,
            confidence: confidence
          )
        )
      }

      request.recognitionLevel = .accurate
      request.usesLanguageCorrection = true
      let supported = (try? request.supportedRecognitionLanguages()) ?? []
      let preferred = ["ru-RU", "uk-UA", "cs-CZ", "en-US"].filter { supported.contains($0) }
      if !preferred.isEmpty { request.recognitionLanguages = preferred }
      request.minimumTextHeight = 0.008

      let handler = VNImageRequestHandler(
        cgImage: cgImage, orientation: cgOrientation(image.imageOrientation))
      do {
        try handler.perform([request])
      } catch {
        continuation.resume(throwing: error)
      }
    }
  }

  private static func cgOrientation(_ orientation: UIImage.Orientation)
    -> CGImagePropertyOrientation
  {
    switch orientation {
    case .up: return .up
    case .down: return .down
    case .left: return .left
    case .right: return .right
    case .upMirrored: return .upMirrored
    case .downMirrored: return .downMirrored
    case .leftMirrored: return .leftMirrored
    case .rightMirrored: return .rightMirrored
    @unknown default: return .up
    }
  }
}

enum OCRError: LocalizedError {
  case invalidImage
  case noText

  var errorDescription: String? {
    switch self {
    case .invalidImage: return "Не удалось прочитать изображение."
    case .noText: return "На изображении не найден текст."
    }
  }
}

struct CalendarImportDraft: Identifiable, Hashable {
  var id = UUID()
  var date: Date
  var startMinutes: Int
  var rings: Int
  var warehouse: Warehouse
  var confidence: Double
}

struct CalendarParseResult {
  var month: Date
  var entries: [CalendarImportDraft]
  var warnings: [String]
  var rawText: String
}

enum CalendarOCRParser {
  private static let monthNames: [String: Int] = [
    "january": 1, "jan": 1, "январ": 1, "leden": 1,
    "february": 2, "feb": 2, "феврал": 2, "unor": 2,
    "march": 3, "mar": 3, "март": 3, "brezen": 3,
    "april": 4, "apr": 4, "апрел": 4, "duben": 4,
    "may": 5, "май": 5, "kveten": 5,
    "june": 6, "jun": 6, "июн": 6, "cerven": 6,
    "july": 7, "jul": 7, "июл": 7, "cervenec": 7,
    "august": 8, "aug": 8, "август": 8, "srpen": 8,
    "september": 9, "sep": 9, "сентябр": 9, "zari": 9,
    "october": 10, "oct": 10, "октябр": 10, "rijen": 10,
    "november": 11, "nov": 11, "ноябр": 11, "listopad": 11,
    "december": 12, "dec": 12, "декабр": 12, "prosinec": 12,
  ]

  private static let compactSchedule = try! NSRegularExpression(
    pattern: #"(?i)(?:(CH|HP|L)\s*)?(\d{1,2})\s*[:.]\s*(\d{2})\s*[-–—]?\s*(\d{1,2})\s*[kк]"#
  )
  private static let timeRegex = try! NSRegularExpression(
    pattern: #"(?i)(CH|HP|L)?\s*(\d{1,2})\s*[:.]\s*(\d{2})"#
  )
  private static let ringsRegex = try! NSRegularExpression(
    pattern: #"(?i)(\d{1,2})\s*[kк]"#
  )

  static func parse(_ document: OCRDocument, fallbackMonth: Date = Date.now) -> CalendarParseResult
  {
    let detectedMonth =
      findMonth(document) ?? Calendar.current.dateInterval(of: .month, for: fallbackMonth)?.start
      ?? fallbackMonth
    let monthStart =
      Calendar.current.dateInterval(of: .month, for: detectedMonth)?.start ?? detectedMonth
    let numberOfDays = Calendar.current.range(of: .day, in: .month, for: monthStart)?.count ?? 31
    let monthLine = document.lines.first { line in
      let normalized = ascii(line.text).lowercased()
      return monthNames.keys.contains { normalized.contains($0) }
    }
    let monthBottom = monthLine?.rect.maxY ?? 0

    let dayLines: [(day: Int, line: OCRLine)] = document.lines.compactMap { line in
      guard line.rect.minY > monthBottom,
        let day = Int(line.text.trimmingCharacters(in: .whitespacesAndNewlines)),
        (1...numberOfDays).contains(day)
      else { return nil }
      return (day, line)
    }

    var entries: [CalendarImportDraft] = []
    var warnings: [String] = []

    if !dayLines.isEmpty {
      let firstWeekday = mondayBasedWeekday(monthStart)
      let detected = dayLines.map { item -> DetectedDay in
        let index = firstWeekday + item.day - 1
        return DetectedDay(day: item.day, column: index % 7, row: index / 7, line: item.line)
      }

      let xStep = inferXStep(detected: detected, document: document)
      let yStep = inferYStep(detected: detected)
      let xOrigin = estimateOrigin(
        values: Dictionary(grouping: detected, by: \.column)
          .compactMapValues { average($0.map { Double($0.line.centerX) }) },
        step: xStep
      )
      let yOrigin = estimateOrigin(
        values: Dictionary(grouping: detected, by: \.row)
          .compactMapValues { average($0.map { Double($0.line.centerY) }) },
        step: yStep
      )

      for day in 1...numberOfDays {
        let index = firstWeekday + day - 1
        let column = index % 7
        let row = index / 7
        let known = detected.first { $0.day == day }
        let centerX = known.map { Double($0.line.centerX) } ?? xOrigin + Double(column) * xStep
        let dayY = known.map { Double($0.line.centerY) } ?? yOrigin + Double(row) * yStep
        let left = centerX - xStep * 0.54
        let right = centerX + xStep * 0.54
        let top = (known.map { Double($0.line.rect.maxY) } ?? dayY) - 0.005
        let bottom = dayY + yStep * 0.85

        let cellLines = document.lines
          .filter {
            Double($0.centerX) >= left && Double($0.centerX) <= right
              && Double($0.centerY) >= top && Double($0.centerY) <= bottom
          }
          .filter { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) != String(day) }
          .sorted {
            if abs($0.rect.minY - $1.rect.minY) > 0.008 {
              return $0.rect.minY < $1.rect.minY
            }
            return $0.rect.minX < $1.rect.minX
          }

        let cellText = cellLines.map { cleanup($0.text) }.joined(separator: " ")
        let schedules = parseSchedules(cellText)
        for schedule in schedules {
          guard let date = Calendar.current.date(byAdding: .day, value: day - 1, to: monthStart)
          else { continue }
          entries.append(
            CalendarImportDraft(
              date: date,
              startMinutes: schedule.hour * 60 + schedule.minute,
              rings: schedule.rings,
              warehouse: schedule.warehouse,
              confidence: min(
                1,
                document.confidence * 0.75 + (known == nil ? 0.04 : 0.14)
                  + (schedule.exact ? 0.08 : 0.03))
            )
          )
        }
      }
    }

    if entries.isEmpty {
      entries = sequentialFallback(
        document: document, monthStart: monthStart, numberOfDays: numberOfDays)
      if !entries.isEmpty {
        warnings.append(
          "График распознан запасным способом. Обязательно проверьте каждую дату перед сохранением."
        )
      }
    }

    let unique = Dictionary(grouping: entries) {
      "\(KXFormat.shortDate($0.date))|\($0.startMinutes)|\($0.warehouse.rawValue)"
    }
    .compactMap { $0.value.first }
    .sorted {
      if $0.date != $1.date { return $0.date < $1.date }
      return $0.startMinutes < $1.startMinutes
    }

    if unique.isEmpty {
      warnings.append(
        "OCR не нашёл рабочие блоки вида 06:00 · 4K. Сделайте скрин без обрезки и повторите импорт."
      )
    }
    if dayLines.count < max(7, numberOfDays / 3) {
      warnings.append("OCR увидел мало номеров дней. Проверьте, что весь календарь попал в кадр.")
    }

    return CalendarParseResult(
      month: monthStart,
      entries: unique,
      warnings: warnings,
      rawText: document.text
    )
  }

  private struct DetectedDay {
    let day: Int
    let column: Int
    let row: Int
    let line: OCRLine
  }

  private struct Schedule {
    let hour: Int
    let minute: Int
    let rings: Int
    let warehouse: Warehouse
    let exact: Bool
  }

  private static func findMonth(_ document: OCRDocument) -> Date? {
    let normalized = ascii(document.text).lowercased()
    guard let month = monthNames.first(where: { normalized.contains($0.key) })?.value else {
      return nil
    }
    let yearRegex = try! NSRegularExpression(pattern: #"\b(20\d{2})\b"#)
    let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
    guard let match = yearRegex.firstMatch(in: normalized, range: range),
      let yearRange = Range(match.range(at: 1), in: normalized),
      let year = Int(normalized[yearRange])
    else { return nil }
    return Calendar.current.date(from: DateComponents(year: year, month: month, day: 1))
  }

  private static func parseSchedules(_ text: String) -> [Schedule] {
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    let compact = compactSchedule.matches(in: text, range: range).compactMap { match -> Schedule? in
      func group(_ index: Int) -> String {
        guard let r = Range(match.range(at: index), in: text) else { return "" }
        return String(text[r])
      }
      guard let hour = Int(group(2)), let minute = Int(group(3)), let rings = Int(group(4)),
        (0...23).contains(hour), (0...59).contains(minute), (1...20).contains(rings)
      else { return nil }
      return Schedule(
        hour: hour,
        minute: minute,
        rings: rings,
        warehouse: warehouse(code: group(1)),
        exact: true
      )
    }
    if !compact.isEmpty { return compact }

    let times = timeRegex.matches(in: text, range: range).compactMap {
      match -> (Int, Int, Warehouse)? in
      func group(_ index: Int) -> String {
        guard let r = Range(match.range(at: index), in: text) else { return "" }
        return String(text[r])
      }
      guard let hour = Int(group(2)), let minute = Int(group(3)),
        (0...23).contains(hour), (0...59).contains(minute)
      else { return nil }
      return (hour, minute, warehouse(code: group(1)))
    }
    let rings = ringsRegex.matches(in: text, range: range).compactMap { match -> Int? in
      guard let r = Range(match.range(at: 1), in: text), let value = Int(text[r]),
        (1...20).contains(value)
      else { return nil }
      return value
    }
    return zip(times, rings).map {
      Schedule(hour: $0.0.0, minute: $0.0.1, rings: $0.1, warehouse: $0.0.2, exact: false)
    }
  }

  private static func sequentialFallback(document: OCRDocument, monthStart: Date, numberOfDays: Int)
    -> [CalendarImportDraft]
  {
    var currentDay: Int?
    var result: [CalendarImportDraft] = []
    for line in document.lines {
      let value = cleanup(line.text)
      if let day = Int(value), (1...numberOfDays).contains(day) {
        currentDay = day
        continue
      }
      guard let day = currentDay else { continue }
      let schedules = parseSchedules(value)
      for schedule in schedules {
        guard let date = Calendar.current.date(byAdding: .day, value: day - 1, to: monthStart)
        else { continue }
        result.append(
          CalendarImportDraft(
            date: date,
            startMinutes: schedule.hour * 60 + schedule.minute,
            rings: schedule.rings,
            warehouse: schedule.warehouse,
            confidence: max(0.35, document.confidence * 0.55)
          )
        )
      }
    }
    return result
  }

  private static func mondayBasedWeekday(_ date: Date) -> Int {
    let weekday = Calendar.current.component(.weekday, from: date)
    return (weekday + 5) % 7
  }

  private static func inferXStep(detected: [DetectedDay], document: OCRDocument) -> Double {
    let centers = Dictionary(grouping: detected, by: \.column)
      .compactMapValues { average($0.map { Double($0.line.centerX) }) }
      .sorted { $0.key < $1.key }
      .map(\.value)
    let diffs = zip(centers, centers.dropFirst()).map { $1 - $0 }.filter { $0 > 0.02 }.sorted()
    if !diffs.isEmpty { return diffs[diffs.count / 2] }
    let minX = document.lines.map { Double($0.rect.minX) }.min() ?? 0
    let maxX = document.lines.map { Double($0.rect.maxX) }.max() ?? 1
    return max(0.09, (maxX - minX) / 7.0)
  }

  private static func inferYStep(detected: [DetectedDay]) -> Double {
    let centers = Dictionary(grouping: detected, by: \.row)
      .compactMapValues { average($0.map { Double($0.line.centerY) }) }
      .sorted { $0.key < $1.key }
      .map(\.value)
    let diffs = zip(centers, centers.dropFirst()).map { $1 - $0 }.filter { $0 > 0.03 }.sorted()
    return diffs.isEmpty ? 0.13 : diffs[diffs.count / 2]
  }

  private static func estimateOrigin(values: [Int: Double], step: Double) -> Double {
    let estimates = values.map { Double($0.key) * -step + $0.value }
    return average(estimates) ?? 0
  }

  private static func average(_ values: [Double]) -> Double? {
    guard !values.isEmpty else { return nil }
    return values.reduce(0, +) / Double(values.count)
  }

  private static func warehouse(code: String) -> Warehouse {
    switch code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
    case "CH": return .chrastany
    case "HP": return .horniPocernice
    default: return .liboc
    }
  }

  private static func cleanup(_ value: String) -> String {
    value
      .replacingOccurrences(of: "■", with: " ")
      .replacingOccurrences(of: "▪", with: " ")
      .replacingOccurrences(of: "□", with: " ")
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func ascii(_ value: String) -> String {
    value.folding(
      options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "cs_CZ"))
  }
}

struct CustomerDraft: Identifiable, Hashable {
  var id = UUID()
  var photoOrder: Int
  var position: Int
  var firstName: String
  var lastName: String
  var address: String
  var normalizedAddress: String = ""
  var addressVerified = false
  var bags: Int
  var tipsHellers: Int64
}

enum CustomerOCRParser {
  static func parse(documents: [OCRDocument]) -> [CustomerDraft] {
    var drafts: [CustomerDraft] = []
    for (photoIndex, document) in documents.enumerated() {
      let lines = document.lines.map { clean($0.text) }.filter { !$0.isEmpty }
      var used = Set<Int>()
      var localPosition = 0

      for index in lines.indices {
        let line = lines[index]
        guard looksLikeAddress(line) else { continue }
        let nameIndex = stride(from: index - 1, through: max(0, index - 3), by: -1)
          .first { candidate in
            !used.contains(candidate)
              && looksLikeName(lines[candidate])
              && !looksLikeAddress(lines[candidate])
          }
        let name = nameIndex.map { lines[$0] } ?? "Клиент \(drafts.count + 1)"
        if let nameIndex { used.insert(nameIndex) }
        used.insert(index)

        let components = splitName(name)
        let nearby = lines[index...min(lines.count - 1, index + 3)].joined(separator: " ")
        drafts.append(
          CustomerDraft(
            photoOrder: photoIndex,
            position: localPosition,
            firstName: components.first,
            lastName: components.last,
            address: line,
            bags: parseBags(nearby),
            tipsHellers: parseMoney(nearby)
          )
        )
        localPosition += 1
      }

      if localPosition == 0 {
        var index = 0
        while index + 1 < lines.count {
          let name = lines[index]
          let address = lines[index + 1]
          if looksLikeName(name) && address.count > 5 {
            let components = splitName(name)
            drafts.append(
              CustomerDraft(
                photoOrder: photoIndex,
                position: localPosition,
                firstName: components.first,
                lastName: components.last,
                address: address,
                bags: 0,
                tipsHellers: 0
              )
            )
            localPosition += 1
            index += 2
          } else {
            index += 1
          }
        }
      }
    }
    return drafts
  }

  private static func clean(_ text: String) -> String {
    text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func looksLikeAddress(_ text: String) -> Bool {
    let lower = text.lowercased()
    let hasNumber = lower.range(of: #"\d{1,5}(?:/\d{1,5})?"#, options: .regularExpression) != nil
    let hasStreetLetters =
      lower.range(
        of: #"[a-záčďéěíňóřšťúůýž]{3,}"#, options: [.regularExpression, .caseInsensitive]) != nil
    let excluded =
      lower.contains("kč") || lower.contains("czk") || lower.contains("objed")
      || lower.contains("заказ")
    return hasNumber && hasStreetLetters && !excluded
  }

  private static func looksLikeName(_ text: String) -> Bool {
    let words = text.split(separator: " ")
    return words.count >= 1 && words.count <= 4 && !text.contains(":") && text.count <= 60
  }

  private static func splitName(_ value: String) -> (first: String, last: String) {
    let words = value.split(separator: " ").map(String.init)
    guard let first = words.first else { return ("", "") }
    return (first, words.dropFirst().joined(separator: " "))
  }

  private static func parseBags(_ value: String) -> Int {
    let regex = try! NSRegularExpression(
      pattern: #"(?i)(\d{1,2})\s*(?:bags?|paket|balik|ta[sš]ek|пакет)"#)
    let range = NSRange(value.startIndex..<value.endIndex, in: value)
    guard let match = regex.firstMatch(in: value, range: range),
      let numberRange = Range(match.range(at: 1), in: value)
    else { return 0 }
    return Int(value[numberRange]) ?? 0
  }

  private static func parseMoney(_ value: String) -> Int64 {
    let regex = try! NSRegularExpression(pattern: #"(?i)(\d{1,5}(?:[.,]\d{1,2})?)\s*(?:k[cč]|czk)"#)
    let range = NSRange(value.startIndex..<value.endIndex, in: value)
    guard let match = regex.firstMatch(in: value, range: range),
      let numberRange = Range(match.range(at: 1), in: value)
    else { return 0 }
    let amount = Double(value[numberRange].replacingOccurrences(of: ",", with: ".")) ?? 0
    return Int64(amount * 100)
  }
}

struct RouteOCRResult {
  var orders: Int?
  var distanceKm: Double?
  var externalRouteID: String?
}

enum RouteOCRParser {
  static func parse(_ text: String) -> RouteOCRResult {
    let orders = firstInteger(
      in: text,
      patterns: [
        #"(?i)(\d{1,3})\s*(?:заказ|objedn|orders?)"#,
        #"(?i)(?:заказ|objedn|orders?)[^\d]{0,12}(\d{1,3})"#,
      ]
    )
    let km = firstDouble(
      in: text,
      patterns: [
        #"(?i)(\d{1,4}(?:[.,]\d+)?)\s*km"#,
        #"(?i)(?:kilometr|километраж)[^\d]{0,12}(\d{1,4}(?:[.,]\d+)?)"#,
      ]
    )
    let routeID = firstString(
      in: text, pattern: #"(?i)(?:route|trasa|трасса)\s*[#:]?\s*([A-Z0-9-]{3,20})"#)
    return RouteOCRResult(orders: orders, distanceKm: km, externalRouteID: routeID)
  }

  private static func firstInteger(in text: String, patterns: [String]) -> Int? {
    for pattern in patterns {
      if let value = firstString(in: text, pattern: pattern), let integer = Int(value) {
        return integer
      }
    }
    return nil
  }

  private static func firstDouble(in text: String, patterns: [String]) -> Double? {
    for pattern in patterns {
      if let value = firstString(in: text, pattern: pattern) {
        return Double(value.replacingOccurrences(of: ",", with: "."))
      }
    }
    return nil
  }

  private static func firstString(in text: String, pattern: String) -> String? {
    let regex = try! NSRegularExpression(pattern: pattern)
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let match = regex.firstMatch(in: text, range: range),
      let resultRange = Range(match.range(at: 1), in: text)
    else { return nil }
    return String(text[resultRange])
  }
}

struct FinanceOCRResult {
  var amountHellers: Int64?
  var description: String
  var date: Date?
}

enum FinanceOCRParser {
  static func parse(_ text: String) -> FinanceOCRResult {
    let normalized = text.replacingOccurrences(of: " ", with: " ")
    let amountRegex = try! NSRegularExpression(
      pattern: #"(?i)([-+]?\d{1,6}(?:[.,]\d{1,2})?)\s*(?:k[cč]|czk)"#)
    let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
    var amount: Int64?
    if let match = amountRegex.firstMatch(in: normalized, range: range),
      let r = Range(match.range(at: 1), in: normalized)
    {
      amount = Int64((Double(normalized[r].replacingOccurrences(of: ",", with: ".")) ?? 0) * 100)
    }
    return FinanceOCRResult(
      amountHellers: amount.map(abs),
      description:
        normalized
        .split(separator: "\n")
        .prefix(4)
        .joined(separator: " · "),
      date: parseDate(normalized)
    )
  }

  private static func parseDate(_ text: String) -> Date? {
    let regex = try! NSRegularExpression(pattern: #"\b(\d{1,2})[./-](\d{1,2})[./-](20\d{2})\b"#)
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let match = regex.firstMatch(in: text, range: range) else { return nil }
    func number(_ index: Int) -> Int? {
      guard let r = Range(match.range(at: index), in: text) else { return nil }
      return Int(text[r])
    }
    guard let day = number(1), let month = number(2), let year = number(3) else { return nil }
    return Calendar.current.date(from: DateComponents(year: year, month: month, day: day))
  }
}

struct StatsOCRResult {
  var cumulativeOrders: Int?
  var cumulativeTipsHellers: Int64?
}

enum StatsOCRParser {
  static func parse(_ text: String) -> StatsOCRResult {
    let orderPatterns = [
      #"(?i)(?:orders?|objedn|заказ)[^\d]{0,20}(\d[\d\s]{1,8})"#,
      #"(?i)(\d[\d\s]{1,8})[^\n]{0,20}(?:orders?|objedn|заказ)"#,
    ]
    var orders: Int?
    for pattern in orderPatterns {
      let regex = try! NSRegularExpression(pattern: pattern)
      let range = NSRange(text.startIndex..<text.endIndex, in: text)
      if let match = regex.firstMatch(in: text, range: range),
        let r = Range(match.range(at: 1), in: text)
      {
        orders = Int(text[r].replacingOccurrences(of: " ", with: ""))
        break
      }
    }
    let finance = FinanceOCRParser.parse(text)
    return StatsOCRResult(cumulativeOrders: orders, cumulativeTipsHellers: finance.amountHellers)
  }
}

// MARK: - Official RÚIAN address service

struct RuianSuggestion: Identifiable, Hashable {
  let id = UUID()
  let text: String
  let magicKey: String?
}

actor RuianAddressService {
  static let shared = RuianAddressService()
  private let root = "https://ags.cuzk.gov.cz/arcgis/rest/services/RUIAN/MapServer/exts/GeocodeSOE"

  func suggest(_ query: String) async throws -> [RuianSuggestion] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count >= 3 else { return [] }
    var components = URLComponents(string: root + "/suggest")!
    components.queryItems = [
      URLQueryItem(name: "text", value: trimmed),
      URLQueryItem(name: "maxSuggestions", value: "8"),
      URLQueryItem(name: "f", value: "json"),
    ]
    guard let url = components.url else { return [] }
    let (data, response) = try await URLSession.shared.data(from: url)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
    let decoded = try JSONDecoder().decode(SuggestResponse.self, from: data)
    return decoded.suggestions.map { RuianSuggestion(text: $0.text, magicKey: $0.magicKey) }
  }

  func validate(_ address: String, magicKey: String? = nil) async throws -> String? {
    var components = URLComponents(string: root + "/findAddressCandidates")!
    var queryItems = [
      URLQueryItem(name: "SingleLine", value: address),
      URLQueryItem(name: "maxLocations", value: "5"),
      URLQueryItem(name: "outFields", value: "*"),
      URLQueryItem(name: "f", value: "json"),
    ]
    if let magicKey { queryItems.append(URLQueryItem(name: "magicKey", value: magicKey)) }
    components.queryItems = queryItems
    guard let url = components.url else { return nil }
    let (data, response) = try await URLSession.shared.data(from: url)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
    let decoded = try JSONDecoder().decode(CandidateResponse.self, from: data)
    return decoded.candidates
      .sorted { $0.score > $1.score }
      .first { $0.score >= 70 }?
      .address
  }

  static func normalize(_ value: String) -> String {
    value.folding(
      options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "cs_CZ")
    )
    .lowercased()
    .replacingOccurrences(of: #"[^a-z0-9 ]+"#, with: " ", options: .regularExpression)
    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private struct SuggestResponse: Decodable {
    let suggestions: [Suggestion]
  }

  private struct Suggestion: Decodable {
    let text: String
    let magicKey: String?
  }

  private struct CandidateResponse: Decodable {
    let candidates: [Candidate]
  }

  private struct Candidate: Decodable {
    let address: String
    let score: Double
  }
}

// MARK: - System camera picker

struct CameraPicker: UIViewControllerRepresentable {
  @Environment(\.dismiss) private var dismiss
  let onImage: (UIImage) -> Void

  func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

  func makeUIViewController(context: Context) -> UIImagePickerController {
    let controller = UIImagePickerController()
    controller.sourceType =
      UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
    controller.delegate = context.coordinator
    return controller
  }

  func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

  final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate
  {
    let parent: CameraPicker
    init(parent: CameraPicker) { self.parent = parent }

    func imagePickerController(
      _ picker: UIImagePickerController,
      didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
      if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
      parent.dismiss()
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
      parent.dismiss()
    }
  }
}

// MARK: - Root and activation

struct RootView: View {
  @EnvironmentObject private var session: SessionStore

  var body: some View {
    ZStack(alignment: .top) {
      Color.kxBackground.ignoresSafeArea()

      switch session.state {
      case .loading:
        VStack(spacing: 18) {
          KXBrand().frame(maxWidth: 260)
          ProgressView()
          Text("Загрузка KurierX…").foregroundStyle(.secondary)
        }
      case .needsFirebase:
        KXBlockedView(
          title: "Firebase не настроен",
          message: "Оставьте GoogleService-Info.plist в папке Resources и пересоберите приложение.",
          icon: "flame.fill"
        )
      case .registration:
        ActivationView()
      case .active:
        MainShell(isOwner: false)
      case .owner:
        MainShell(isOwner: true)
      case .frozen:
        KXBlockedView(
          title: "Аккаунт заморожен",
          message: "Обратитесь к владельцу KurierX.",
          icon: "snowflake"
        )
      case .revoked:
        KXBlockedView(
          title: "Лицензия недействительна",
          message: "Необходимо выполнить новую активацию.",
          icon: "lock.fill"
        )
      }

      if let message = PersistenceFactory.recoveryMessage,
        session.state != .loading
      {
        Text(message)
          .font(.caption)
          .foregroundStyle(.orange)
          .padding(10)
          .frame(maxWidth: .infinity)
          .background(Color.orange.opacity(0.12))
      }
    }
  }
}

struct KXBlockedView: View {
  let title: String
  let message: String
  let icon: String

  var body: some View {
    VStack(spacing: 18) {
      Image(systemName: icon)
        .font(.system(size: 58))
        .foregroundStyle(Color.kxGreen)
      Text(title).font(.title.bold())
      Text(message)
        .multilineTextAlignment(.center)
        .foregroundStyle(.secondary)
    }
    .padding(28)
  }
}

struct ActivationView: View {
  @EnvironmentObject private var session: SessionStore

  @State private var firstName = ""
  @State private var lastName = ""
  @State private var courierID = ""
  @State private var activationKey = ""
  @State private var errorMessage = ""
  @State private var busy = false
  @State private var showOwner = false
  @State private var ownerEmail = ""
  @State private var ownerPassword = ""

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 18) {
          Spacer(minLength: 28)
          VStack(spacing: 10) {
            ZStack {
              RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.kxGreen.opacity(0.15))
              Image(systemName: "shippingbox.fill")
                .font(.system(size: 38))
                .foregroundStyle(Color.kxGreen)
            }
            .frame(width: 78, height: 78)
            KXBrand().frame(maxWidth: 250)
            Text("Активация приложения")
              .font(.title3)
              .foregroundStyle(.secondary)
          }

          KXCard {
            VStack(spacing: 12) {
              KXInput(title: "Имя", text: $firstName)
              KXInput(title: "Фамилия", text: $lastName)
              KXInput(title: "Courier ID", text: $courierID, keyboard: .numberPad)
              KXInput(
                title: "KX-XXXX-XXXX-XXXX",
                text: $activationKey,
                capitalization: .characters
              )
              KXErrorText(text: errorMessage)
              KXPrimaryButton(
                title: busy ? "Проверка…" : "Активировать",
                icon: "checkmark.shield.fill",
                disabled: busy
                  || firstName.trimmingCharacters(in: .whitespaces).isEmpty
                  || courierID.trimmingCharacters(in: .whitespaces).isEmpty
                  || activationKey.trimmingCharacters(in: .whitespaces).isEmpty
              ) {
                Task { await activate() }
              }
            }
          }

          KXSecondaryButton(
            title: "OWNER / Developer",
            icon: "lock.shield.fill"
          ) {
            withAnimation(.snappy) { showOwner.toggle() }
          }

          if showOwner {
            KXCard {
              VStack(alignment: .leading, spacing: 12) {
                Text("KurierX Control")
                  .font(.title3.bold())
                KXInput(
                  title: "Email",
                  text: $ownerEmail,
                  keyboard: .emailAddress,
                  capitalization: .never
                )
                SecureField("Пароль", text: $ownerPassword)
                  .textInputAutocapitalization(.never)
                  .padding(.horizontal, 14)
                  .frame(height: 54)
                  .background(
                    Color.black.opacity(0.48),
                    in: RoundedRectangle(cornerRadius: 12)
                  )
                KXPrimaryButton(
                  title: "Войти как OWNER",
                  icon: "person.badge.shield.checkmark.fill",
                  disabled: ownerEmail.isEmpty || ownerPassword.isEmpty
                ) {
                  Task { await ownerLogin() }
                }
              }
            }
          }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 40)
      }
      .scrollDismissesKeyboard(.interactively)
      .kxDismissKeyboardOnTap()
      .kxPageBackground()
      .toolbar { KeyboardDoneToolbar() }
      .navigationBarHidden(true)
    }
  }

  private func activate() async {
    busy = true
    errorMessage = ""
    defer { busy = false }
    do {
      try await session.activate(
        firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
        lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines),
        courierID: courierID.trimmingCharacters(in: .whitespacesAndNewlines),
        key: activationKey
      )
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func ownerLogin() async {
    busy = true
    errorMessage = ""
    defer { busy = false }
    do {
      try await session.ownerLogin(email: ownerEmail, password: ownerPassword)
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

// MARK: - Main shell and bottom navigation

struct MainShell: View {
  enum Tab: Hashable, CaseIterable {
    case home, calendar, statistics, scanner, more
  }

  let isOwner: Bool
  @State private var selectedTab: Tab = .home

  var body: some View {
    Group {
      switch selectedTab {
      case .home:
        NavigationStack { HomeView(openScanner: { selectedTab = .scanner }) }
      case .calendar:
        NavigationStack { CalendarViewKX() }
      case .statistics:
        NavigationStack { StatisticsView() }
      case .scanner:
        NavigationStack { ScannerView() }
      case .more:
        NavigationStack { MoreView(isOwner: isOwner) }
      }
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      KXBottomBar(selection: $selectedTab)
    }
    .background(Color.kxBackground.ignoresSafeArea())
  }
}

struct KXBottomBar: View {
  @Binding var selection: MainShell.Tab

  private let items: [(MainShell.Tab, String, String)] = [
    (.home, "Главная", "house"),
    (.calendar, "Календарь", "calendar"),
    (.statistics, "Статистика", "chart.bar.fill"),
    (.scanner, "Сканер", "qrcode.viewfinder"),
    (.more, "Ещё", "ellipsis"),
  ]

  var body: some View {
    HStack(spacing: 0) {
      ForEach(items, id: \.0) { item in
        Button {
          selection = item.0
        } label: {
          VStack(spacing: 4) {
            ZStack {
              if selection == item.0 {
                Capsule()
                  .fill(Color.kxPurple.opacity(0.85))
                  .frame(width: 56, height: 38)
              }
              Image(systemName: item.2)
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(
                  selection == item.0 ? Color.white : Color.white.opacity(0.72)
                )
            }
            .frame(height: 40)

            Text(item.1)
              .font(.system(size: 11, weight: selection == item.0 ? .semibold : .regular))
              .foregroundStyle(
                selection == item.0 ? Color.kxGreen : Color.white.opacity(0.72)
              )
              .lineLimit(1)
              .minimumScaleFactor(0.7)
          }
          .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.horizontal, 4)
    .padding(.top, 7)
    .padding(.bottom, 5)
    .background(Color.kxSurface2.opacity(0.99).ignoresSafeArea(edges: .bottom))
    .overlay(alignment: .top) {
      Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
    }
  }
}

// MARK: - Home

struct HomeView: View {
  @Environment(\.modelContext) private var context
  @EnvironmentObject private var developerAccess: DeveloperAccess

  @Query(sort: \Shift.date, order: .reverse) private var shifts: [Shift]
  @Query(sort: \Route.date, order: .reverse) private var routes: [Route]
  @Query(sort: \Customer.date, order: .reverse) private var customers: [Customer]
  @Query(sort: \FinancialEntry.date, order: .reverse) private var finances: [FinancialEntry]
  @Query(sort: \FuelEntry.date, order: .reverse) private var expenses: [FuelEntry]
  @Query(sort: \AdvanceEntry.date, order: .reverse) private var advances: [AdvanceEntry]
  @Query private var goals: [Goal]

  let openScanner: () -> Void

  @State private var showStartShift = false
  @State private var showCloseShift = false
  @State private var selectedRoute: Route?
  @State private var showPlanEditor = false
  @State private var planValue = "4"

  private var activeShift: Shift? {
    shifts.first { $0.deletedAt == nil && $0.status == .active }
  }

  private var visibleRoutes: [Route] {
    routes.filter { $0.deletedAt == nil }
  }

  private var totalOrders: Int {
    visibleRoutes.reduce(0) { $0 + $1.factualOrders }
  }

  private var routeMoney: Int64 {
    visibleRoutes.reduce(Int64(0)) { result, route in
      result + EarningsCalculator.route(route, customers: customers).gross
    }
  }

  private var tips: Int64 {
    visibleRoutes.reduce(Int64(0)) { result, route in
      result + EarningsCalculator.route(route, customers: customers).tips
    }
  }

  private var netMoney: Int64 {
    let extra =
      finances
      .filter { $0.deletedAt == nil }
      .reduce(Int64(0)) {
        $0 + ($1.kind.positive ? $1.amountHellers : -$1.amountHellers)
      }
    let expense =
      expenses
      .filter { $0.deletedAt == nil }
      .reduce(Int64(0)) { $0 + $1.amountHellers }
    let advance =
      advances
      .filter { $0.deletedAt == nil }
      .reduce(Int64(0)) { $0 + $1.amountHellers }
    return routeMoney + extra - expense - advance
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 16) {
        KXBrand().padding(.top, 10)

        if let goal = currentGoal, goal.targetOrders > 0 {
          GoalProgressCard(
            completed: ordersForCurrentMonth,
            target: goal.targetOrders
          )
        }

        KXCard {
          VStack(alignment: .leading, spacing: 8) {
            Text("Заработок по обработанным трассам")
              .font(.system(size: 15, weight: .semibold))
            Text(KXFormat.money(netMoney))
              .font(.system(size: 38, weight: .bold, design: .rounded))
            Text("\(totalOrders) фактических заказов · чаевые \(KXFormat.money(tips))")
              .font(.system(size: 16))
              .foregroundStyle(.secondary)
            Text("Итог учитывает трассы, бонусы / компенсации, штрафы, дизель и авансы.")
              .font(.system(size: 14))
              .foregroundStyle(.secondary)
          }
        }

        if let activeShift {
          ActiveShiftCard(
            shift: activeShift,
            routes: visibleRoutes.filter { $0.shiftID == activeShift.id },
            onEditPlan: {
              planValue = String(activeShift.plannedRings)
              showPlanEditor = true
            },
            onAddRoute: openScanner,
            onClose: { showCloseShift = true }
          )

          let shiftRoutes =
            visibleRoutes
            .filter { $0.shiftID == activeShift.id }
            .sorted { $0.sequence > $1.sequence }
          if !shiftRoutes.isEmpty {
            Text("Закрытые трассы")
              .font(.system(size: 27, weight: .bold, design: .rounded))
              .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(shiftRoutes) { route in
              Button {
                selectedRoute = route
              } label: {
                RouteSummaryCard(
                  route: route,
                  customers: customers.filter { $0.routeID == route.id && $0.deletedAt == nil }
                )
              }
              .buttonStyle(.plain)
            }
          }
        } else {
          KXCard {
            VStack(alignment: .leading, spacing: 13) {
              Text("Смена не начата")
                .font(.system(size: 24, weight: .bold))
              Text("Рабочее время начнётся только после входа в очередь.")
                .foregroundStyle(.secondary)
              KXPrimaryButton(title: "Начать смену", icon: "play.fill") {
                showStartShift = true
              }
            }
          }
        }
      }
      .padding(.horizontal, 18)
      .padding(.bottom, 24)
    }
    .scrollDismissesKeyboard(.interactively)
    .kxPageBackground()
    .navigationBarHidden(true)
    .sheet(isPresented: $showStartShift) {
      StartShiftSheet()
    }
    .sheet(isPresented: $showCloseShift) {
      if let activeShift {
        CloseShiftSheet(
          shift: activeShift,
          routes: visibleRoutes.filter { $0.shiftID == activeShift.id }
        )
      }
    }
    .sheet(item: $selectedRoute) { route in
      RouteDetailSheet(route: route)
        .environmentObject(developerAccess)
    }
    .alert("Изменить план", isPresented: $showPlanEditor) {
      TextField("Колечки", text: $planValue).keyboardType(.numberPad)
      Button("Сохранить") {
        guard let activeShift else { return }
        activeShift.plannedRings = max(1, Int(planValue) ?? activeShift.plannedRings)
        audit(
          context,
          action: "edit",
          entityType: "shift",
          entityID: activeShift.id.uuidString,
          details: "План изменён на \(activeShift.plannedRings)K"
        )
        try? context.save()
      }
      Button("Отмена", role: .cancel) {}
    }
  }

  private var currentGoal: Goal? {
    goals.first { $0.deletedAt == nil && $0.month == Date.now.monthKey }
  }

  private var ordersForCurrentMonth: Int {
    visibleRoutes
      .filter { $0.date.monthKey == Date.now.monthKey }
      .reduce(0) { $0 + $1.factualOrders }
  }
}

struct GoalProgressCard: View {
  let completed: Int
  let target: Int

  var body: some View {
    KXCard {
      VStack(spacing: 8) {
        HStack {
          Text("\(completed)")
            .bold()
            .foregroundStyle(Color.kxGreen)
          Text("/ \(target)")
          Spacer()
          Text("Цель: \(target) заказов")
            .font(.caption.bold())
        }
        ProgressView(value: Double(completed), total: Double(max(1, target)))
          .tint(Color.kxGreen)
        Text(
          completed >= target
            ? "Цель выполнена ✓"
            : "Осталось \(max(0, target - completed)) заказов"
        )
        .font(.caption)
        .foregroundStyle(completed >= target ? Color.kxGreen : .secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }
}

struct ActiveShiftCard: View {
  let shift: Shift
  let routes: [Route]
  let onEditPlan: () -> Void
  let onAddRoute: () -> Void
  let onClose: () -> Void

  private var completedRings: Int {
    routes.reduce(0) { $0 + $1.type.rings }
  }

  var body: some View {
    KXCard {
      VStack(alignment: .leading, spacing: 15) {
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: 4) {
            Text("Смена активна")
              .font(.system(size: 24, weight: .bold))
            Text("Старт \(shift.startedAt.map(KXFormat.time) ?? "—")")
              .font(.system(size: 17))
              .foregroundStyle(.secondary)
          }
          Spacer()
          Text("\(completedRings)/\(max(1, shift.plannedRings)) K")
            .font(.title3.bold())
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.kxPurple, in: RoundedRectangle(cornerRadius: 14))
        }

        Text(
          completedRings >= shift.plannedRings
            ? "План выполнен"
            : "Осталось по плану: \(max(0, shift.plannedRings - completedRings)) колечка"
        )
        .font(.system(size: 17))

        Button("Изменить план", action: onEditPlan)
          .foregroundStyle(Color.kxGreen)
          .fontWeight(.semibold)

        KXPrimaryButton(
          title: "Добавить закрытую трассу",
          icon: "plus.circle.fill",
          action: onAddRoute
        )
        KXSecondaryButton(
          title: "Закрыть текущую смену",
          icon: "stop.circle",
          action: onClose
        )
      }
    }
  }
}

struct RouteSummaryCard: View {
  let route: Route
  let customers: [Customer]

  var body: some View {
    let money = EarningsCalculator.route(route, customers: customers)
    KXCard {
      VStack(alignment: .leading, spacing: 7) {
        HStack {
          Text("✓ \(route.type.rawValue) · \(route.warehouse.rawValue)")
            .font(.headline)
          Spacer()
          Text(KXFormat.money(money.gross)).bold()
        }
        Text(
          "\(route.type.rings) колечко · трасса #\(route.sequence) · \(route.factualOrders) заказов"
            + (route.distanceKm.map { " · \(KXFormat.number($0)) км" } ?? "")
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        if money.tips > 0 {
          Text("Чаевые \(KXFormat.money(money.tips))")
            .font(.caption)
            .foregroundStyle(Color.kxGreen)
        }
      }
    }
  }
}

extension EarningsCalculator {
  static func preview(
    date: Date,
    type: RouteType,
    orders: Int,
    tips: Int64
  ) -> RouteMoney {
    let weekday = Calendar.current.component(.weekday, from: date)
    let highRate = weekday == 1 || weekday == 6 || weekday == 7
    let rate = highRate ? weekendRate : weekdayRate
    return RouteMoney(
      base: Int64(max(0, orders)) * rate,
      regionBonus: type == .region ? regionBonus : 0,
      tips: tips
    )
  }
}

struct StartShiftSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var context

  @State private var warehouse: Warehouse = .liboc
  @State private var plannedRings = 4
  @State private var queueOdometer = ""
  @State private var errorMessage = ""

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 18) {
          KXHeader(
            title: "Начать смену",
            subtitle: "Выберите склад и план колечек"
          )

          KXCard {
            VStack(spacing: 16) {
              HStack {
                Text("Склад").font(.headline)
                Spacer()
                Picker("Склад", selection: $warehouse) {
                  ForEach(Warehouse.allCases) { item in
                    Text(item.rawValue).tag(item)
                  }
                }
                .tint(Color.kxGreen)
              }

              Divider()

              HStack {
                Text("План: \(plannedRings) колечка")
                  .font(.headline)
                Spacer()
                Stepper("", value: $plannedRings, in: 1...20)
                  .labelsHidden()
              }

              KXInput(
                title: "Спидометр при входе",
                text: $queueOdometer,
                keyboard: .decimalPad
              )
            }
          }

          KXErrorText(text: errorMessage)
          KXPrimaryButton(title: "Начать", icon: "play.fill") {
            save()
          }
          KXSecondaryButton(title: "Отмена") { dismiss() }
        }
        .padding(18)
      }
      .scrollDismissesKeyboard(.interactively)
      .kxDismissKeyboardOnTap()
      .kxPageBackground()
      .toolbar { KeyboardDoneToolbar() }
      .navigationBarHidden(true)
    }
  }

  private func save() {
    errorMessage = ""
    let odometer = Double(queueOdometer.replacingOccurrences(of: ",", with: "."))
    if !queueOdometer.isEmpty && odometer == nil {
      errorMessage = "Введите корректный километраж."
      return
    }
    let shift = Shift(
      warehouse: warehouse,
      status: .active,
      plannedRings: plannedRings,
      startedAt: Date.now,
      queueOdometer: odometer,
      source: .manual
    )
    context.insert(shift)
    audit(
      context,
      action: "create",
      entityType: "shift",
      entityID: shift.id.uuidString,
      details: "Начата смена: \(warehouse.rawValue), план \(plannedRings)K"
    )
    do {
      try context.save()
      dismiss()
    } catch {
      errorMessage = "Не удалось сохранить смену: \(error.localizedDescription)"
    }
  }
}

struct CloseShiftSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var context

  let shift: Shift
  let routes: [Route]

  @State private var reason = ""
  @State private var closingOdometer = ""
  @State private var errorMessage = ""

  private var completedRings: Int {
    routes.filter { $0.deletedAt == nil }.reduce(0) { $0 + $1.type.rings }
  }

  private var isEarly: Bool { completedRings < shift.plannedRings }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 18) {
          KXHeader(
            title: "Закрыть смену",
            subtitle: isEarly
              ? "План не выполнен: \(completedRings)/\(shift.plannedRings)K"
              : "План выполнен"
          )

          KXCard {
            VStack(alignment: .leading, spacing: 14) {
              if isEarly {
                Text("Причина досрочного закрытия")
                  .font(.headline)
                KXInput(
                  title: "Например: закончились трассы / личная причина",
                  text: $reason
                )
                Text("Причина обязательна, поскольку план колечек не выполнен.")
                  .font(.caption)
                  .foregroundStyle(.orange)
              }

              Text("Километраж при закрытии")
                .font(.headline)
              KXInput(
                title: "Показание спидометра",
                text: $closingOdometer,
                keyboard: .decimalPad
              )
            }
          }

          KXErrorText(text: errorMessage)
          KXPrimaryButton(title: "Закрыть смену", icon: "stop.fill") {
            closeShift()
          }
          KXSecondaryButton(title: "Отмена") { dismiss() }
        }
        .padding(18)
      }
      .scrollDismissesKeyboard(.interactively)
      .kxDismissKeyboardOnTap()
      .kxPageBackground()
      .toolbar { KeyboardDoneToolbar() }
      .navigationBarHidden(true)
    }
  }

  private func closeShift() {
    errorMessage = ""
    let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
    let odometer = Double(closingOdometer.replacingOccurrences(of: ",", with: "."))

    if isEarly && trimmedReason.isEmpty {
      errorMessage = "Укажите причину досрочного закрытия смены."
      return
    }
    if closingOdometer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || odometer == nil {
      errorMessage = "Укажите корректный километраж при закрытии."
      return
    }
    if let start = shift.queueOdometer, let odometer, odometer < start {
      errorMessage = "Конечный километраж не может быть меньше начального."
      return
    }

    shift.endedAt = Date.now
    shift.closingOdometer = odometer
    shift.closeReason = trimmedReason
    shift.status = isEarly ? .partial : .complete
    audit(
      context,
      action: "close",
      entityType: "shift",
      entityID: shift.id.uuidString,
      details: isEarly ? "Досрочно: \(trimmedReason)" : "Смена завершена по плану"
    )
    do {
      try context.save()
      dismiss()
    } catch {
      errorMessage = "Не удалось закрыть смену: \(error.localizedDescription)"
    }
  }
}

struct RouteDetailSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var context
  @EnvironmentObject private var developerAccess: DeveloperAccess

  @Query(sort: \Customer.position) private var allCustomers: [Customer]

  let route: Route

  @State private var routeType: RouteType = .ot
  @State private var factualOrders = ""
  @State private var distanceKm = ""
  @State private var note = ""
  @State private var errorMessage = ""
  @State private var selectedCustomer: Customer?
  @State private var confirmDelete = false

  private var routeCustomers: [Customer] {
    allCustomers
      .filter { $0.deletedAt == nil && $0.routeID == route.id }
      .sorted {
        if $0.photoOrder != $1.photoOrder { return $0.photoOrder < $1.photoOrder }
        return $0.position < $1.position
      }
  }

  private var money: RouteMoney {
    EarningsCalculator.preview(
      date: route.date,
      type: routeType,
      orders: Int(factualOrders) ?? route.factualOrders,
      tips: routeCustomers.reduce(Int64(0)) { $0 + $1.tipValue }
    )
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 16) {
          KXHeader(
            title: "Трасса #\(route.sequence)",
            subtitle: KXFormat.date(route.date)
          )

          KXCard {
            VStack(spacing: 14) {
              Picker("Тип трассы", selection: $routeType) {
                ForEach(RouteType.allCases) { type in
                  Text(type.rawValue).tag(type)
                }
              }
              .pickerStyle(.segmented)
              .disabled(!developerAccess.isUnlocked)

              KXInput(
                title: "Количество заказов",
                text: $factualOrders,
                keyboard: .numberPad,
                disabled: !developerAccess.isUnlocked
              )
              KXInput(
                title: "Километраж",
                text: $distanceKm,
                keyboard: .decimalPad,
                disabled: !developerAccess.isUnlocked
              )
              KXInput(
                title: "Комментарий",
                text: $note,
                disabled: !developerAccess.isUnlocked
              )
            }
          }

          KXCard {
            VStack(alignment: .leading, spacing: 9) {
              Text("Расчёт")
                .font(.title3.bold())
              LabeledContent("Базовая оплата", value: KXFormat.money(money.base))
              LabeledContent("Region", value: KXFormat.money(money.regionBonus))
              LabeledContent("Чаевые клиентов", value: KXFormat.money(money.tips))
              Divider()
              LabeledContent("Итог по трассе", value: KXFormat.money(money.gross))
                .font(.headline)
              Text("Чаевые и итог по трассе рассчитываются автоматически.")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }

          if !routeCustomers.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
              Text("Заказники")
                .font(.title2.bold())
              ForEach(routeCustomers) { customer in
                Button {
                  selectedCustomer = customer
                } label: {
                  KXCard {
                    HStack {
                      VStack(alignment: .leading, spacing: 4) {
                        Text(customer.displayName).bold()
                        Text(customer.address)
                          .font(.caption)
                          .foregroundStyle(.secondary)
                        Text(
                          "Пакеты: \(customer.bags) · чаевые \(KXFormat.money(customer.tipValue))"
                        )
                        .font(.caption)
                        .foregroundStyle(Color.kxGreen)
                      }
                      Spacer()
                      Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                    }
                  }
                }
                .buttonStyle(.plain)
              }
            }
          }

          if developerAccess.isUnlocked {
            KXErrorText(text: errorMessage)
            KXPrimaryButton(title: "Сохранить изменения", icon: "checkmark") {
              save()
            }
            KXSecondaryButton(title: "Удалить трассу", icon: "trash", destructive: true) {
              confirmDelete = true
            }
          } else {
            KXCard {
              Label(
                "Для изменения закрытой трассы разблокируйте Developer Mode в разделе «Ещё».",
                systemImage: "lock.fill"
              )
              .foregroundStyle(.secondary)
            }
          }
        }
        .padding(18)
      }
      .scrollDismissesKeyboard(.interactively)
      .kxDismissKeyboardOnTap()
      .kxPageBackground()
      .toolbar {
        KeyboardDoneToolbar()
        ToolbarItem(placement: .cancellationAction) {
          Button("Закрыть") { dismiss() }
        }
      }
      .onAppear {
        routeType = route.type
        factualOrders = String(route.factualOrders)
        distanceKm = route.distanceKm.map { KXFormat.number($0) } ?? ""
        note = route.note
      }
      .sheet(item: $selectedCustomer) { customer in
        CustomerEditorSheet(customer: customer, preferredRouteID: route.id)
      }
      .alert("Удалить трассу?", isPresented: $confirmDelete) {
        Button("Удалить", role: .destructive) {
          route.deletedAt = Date.now
          audit(
            context,
            action: "delete",
            entityType: "route",
            entityID: route.id.uuidString,
            details: "Трасса перемещена в корзину"
          )
          try? context.save()
          dismiss()
        }
        Button("Отмена", role: .cancel) {}
      }
    }
  }

  private func save() {
    errorMessage = ""
    guard let orders = Int(factualOrders), orders >= 0 else {
      errorMessage = "Введите корректное количество заказов."
      return
    }
    guard let km = Double(distanceKm.replacingOccurrences(of: ",", with: ".")), km >= 0 else {
      errorMessage = "Введите корректный километраж."
      return
    }
    route.type = routeType
    route.factualOrders = orders
    route.distanceKm = km
    route.note = note
    route.sourceRaw = DataSource.correction.rawValue
    audit(
      context,
      action: "edit",
      entityType: "route",
      entityID: route.id.uuidString,
      details: "\(routeType.rawValue), \(orders) заказов, \(km) км"
    )
    do {
      try context.save()
      dismiss()
    } catch {
      errorMessage = "Не удалось сохранить: \(error.localizedDescription)"
    }
  }
}

// MARK: - Calendar

struct CalendarViewKX: View {
  @Environment(\.modelContext) private var context
  @Query(sort: \CalendarPlan.date) private var plans: [CalendarPlan]

  @State private var visibleMonth =
    Calendar.current.dateInterval(of: .month, for: Date.now)?.start ?? Date.now
  @State private var selectedDate = Date.now.startOfDay
  @State private var photoItem: PhotosPickerItem?
  @State private var showCamera = false
  @State private var importResult: CalendarParseResult?
  @State private var importBusy = false
  @State private var importError = ""
  @State private var showManualAdd = false
  @State private var editingPlan: CalendarPlan?

  private let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)

  private var monthDays: [Date?] {
    let calendar = Calendar.current
    guard let interval = calendar.dateInterval(of: .month, for: visibleMonth) else { return [] }
    let first = interval.start
    let leading = (calendar.component(.weekday, from: first) + 5) % 7
    let count = calendar.range(of: .day, in: .month, for: first)?.count ?? 30
    return Array(repeating: nil, count: leading)
      + (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
  }

  private var selectedPlans: [CalendarPlan] {
    plans
      .filter { $0.deletedAt == nil && $0.date.sameDay(as: selectedDate) }
      .sorted { $0.startMinutes < $1.startMinutes }
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 16) {
        HStack(alignment: .top) {
          KXHeader(title: "Календарь", subtitle: "План смен и колечек")
          Button("Сегодня") {
            visibleMonth =
              Calendar.current.dateInterval(of: .month, for: Date.now)?.start ?? Date.now
            selectedDate = Date.now.startOfDay
          }
          .foregroundStyle(Color.kxGreen)
          .fontWeight(.semibold)
        }
        .padding(.top, 10)

        KXCard {
          VStack(spacing: 14) {
            HStack {
              Button {
                visibleMonth =
                  Calendar.current.date(byAdding: .month, value: -1, to: visibleMonth)
                  ?? visibleMonth
              } label: {
                Image(systemName: "chevron.left.circle.fill")
                  .font(.system(size: 31))
              }
              Spacer()
              Text(KXFormat.monthTitle(visibleMonth))
                .font(.system(size: 25, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
              Spacer()
              Button {
                visibleMonth =
                  Calendar.current.date(byAdding: .month, value: 1, to: visibleMonth)
                  ?? visibleMonth
              } label: {
                Image(systemName: "chevron.right.circle.fill")
                  .font(.system(size: 31))
              }
            }

            LazyVGrid(columns: columns, spacing: 7) {
              ForEach(["ПН", "ВТ", "СР", "ЧТ", "ПТ", "СБ", "ВС"], id: \.self) { title in
                Text(title)
                  .font(.caption.bold())
                  .foregroundStyle(.secondary)
              }

              ForEach(Array(monthDays.enumerated()), id: \.offset) { _, day in
                if let day {
                  let dayPlans = plans.filter { $0.deletedAt == nil && $0.date.sameDay(as: day) }
                  Button {
                    selectedDate = day.startOfDay
                  } label: {
                    CalendarDayCell(
                      day: day,
                      plans: dayPlans,
                      selected: day.sameDay(as: selectedDate)
                    )
                  }
                  .buttonStyle(.plain)
                } else {
                  Color.clear.frame(height: 90)
                }
              }
            }
          }
        }

        SelectedCalendarDayCard(
          date: selectedDate,
          plans: selectedPlans,
          onAdd: { showManualAdd = true },
          onEdit: { editingPlan = $0 },
          onDelete: { plan in
            plan.deletedAt = Date.now
            audit(
              context,
              action: "delete",
              entityType: "calendar",
              entityID: plan.id.uuidString,
              details: KXFormat.date(plan.date)
            )
            try? context.save()
          }
        )

        HStack(spacing: 12) {
          Button {
            showCamera = true
          } label: {
            Label("Камера", systemImage: "camera.fill")
              .frame(maxWidth: .infinity)
              .frame(height: 52)
          }
          .buttonStyle(.plain)
          .background(Color.kxSurface2, in: RoundedRectangle(cornerRadius: 16))
          .overlay {
            RoundedRectangle(cornerRadius: 16)
              .stroke(Color.white.opacity(0.14), lineWidth: 1)
          }

          PhotosPicker(selection: $photoItem, matching: .images) {
            Label("Импорт скриншота", systemImage: "photo.fill")
              .fontWeight(.semibold)
              .foregroundStyle(Color.kxBackground)
              .frame(maxWidth: .infinity)
              .frame(height: 52)
              .background(Color.kxGreen, in: RoundedRectangle(cornerRadius: 16))
          }
        }

        if importBusy {
          KXCard {
            HStack {
              ProgressView()
              Text("Распознаю график…")
            }
          }
        }
        KXErrorText(text: importError)

        Text(
          "После OCR график всегда открывается на проверку. Каждый рабочий блок сохраняется на свою дату."
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)

        KXCard {
          VStack(alignment: .leading, spacing: 7) {
            Text("Цвета плана").font(.headline)
            Text(
              "Liboc 06:00 — зелёный · 06:30 — красный · 07:30 — фиолетовый. Коды CH и HP обозначают другие склады."
            )
            .foregroundStyle(.secondary)
          }
        }
      }
      .padding(.horizontal, 18)
      .padding(.bottom, 24)
    }
    .kxPageBackground()
    .navigationBarHidden(true)
    .onChange(of: photoItem) { _, newItem in
      guard let newItem else { return }
      Task { await importPhotoItem(newItem) }
    }
    .sheet(isPresented: $showCamera) {
      CameraPicker { image in
        Task { await processCalendarImage(image) }
      }
    }
    .sheet(item: $importResult) { result in
      CalendarImportReviewSheet(result: result)
    }
    .sheet(isPresented: $showManualAdd) {
      CalendarPlanEditorSheet(date: selectedDate, plan: nil)
    }
    .sheet(item: $editingPlan) { plan in
      CalendarPlanEditorSheet(date: plan.date, plan: plan)
    }
  }

  private func importPhotoItem(_ item: PhotosPickerItem) async {
    importBusy = true
    importError = ""
    defer {
      importBusy = false
      photoItem = nil
    }
    do {
      guard let data = try await item.loadTransferable(type: Data.self),
        let image = UIImage(data: data)
      else { throw OCRError.invalidImage }
      await processCalendarImage(image)
    } catch {
      importError = error.localizedDescription
    }
  }

  private func processCalendarImage(_ image: UIImage) async {
    importBusy = true
    importError = ""
    defer { importBusy = false }
    do {
      let document = try await OCRService.recognize(image)
      guard !document.lines.isEmpty else { throw OCRError.noText }
      let result = CalendarOCRParser.parse(document, fallbackMonth: visibleMonth)
      importResult = result
    } catch {
      importError = error.localizedDescription
    }
  }
}

struct CalendarDayCell: View {
  let day: Date
  let plans: [CalendarPlan]
  let selected: Bool

  private var firstPlan: CalendarPlan? {
    plans.sorted { $0.startMinutes < $1.startMinutes }.first
  }

  private var accent: Color {
    guard let plan = firstPlan else { return Color.white.opacity(0.12) }
    if plan.warehouse == .chrastany { return .orange }
    if plan.warehouse == .horniPocernice { return .cyan }
    switch plan.startMinutes {
    case 360: return .kxGreen
    case 390: return .red
    case 450: return .purple
    default: return .kxGreen
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text("\(Calendar.current.component(.day, from: day))")
        .font(.system(size: 18, weight: .bold))
        .foregroundStyle(.white)

      if let plan = firstPlan {
        Text(KXFormat.minutesToTime(plan.startMinutes))
          .font(.system(size: 12, weight: .medium, design: .rounded))
          .foregroundStyle(accent)
          .lineLimit(1)
          .fixedSize(horizontal: true, vertical: false)
          .minimumScaleFactor(0.72)
        Text("\(plans.reduce(0) { $0 + $1.plannedRings })K")
          .font(.system(size: 13, weight: .bold, design: .rounded))
          .foregroundStyle(.white)
          .lineLimit(1)
        if plans.count > 1 {
          Text("+\(plans.count - 1)")
            .font(.caption2.bold())
            .foregroundStyle(.secondary)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(8)
    .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
    .background(Color.kxSurface2, in: RoundedRectangle(cornerRadius: 12))
    .overlay {
      RoundedRectangle(cornerRadius: 12)
        .stroke(
          selected
            ? Color.kxGreen : (firstPlan == nil ? Color.white.opacity(0.055) : accent.opacity(0.8)),
          lineWidth: selected ? 2.2 : 1)
    }
  }
}

struct SelectedCalendarDayCard: View {
  let date: Date
  let plans: [CalendarPlan]
  let onAdd: () -> Void
  let onEdit: (CalendarPlan) -> Void
  let onDelete: (CalendarPlan) -> Void

  var body: some View {
    KXCard {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          VStack(alignment: .leading, spacing: 3) {
            Text(KXFormat.date(date)).font(.title3.bold())
            Text(plans.isEmpty ? "На этот день план не добавлен" : "Рабочих блоков: \(plans.count)")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer()
          Button(action: onAdd) {
            Image(systemName: "plus.circle.fill")
              .font(.title2)
              .foregroundStyle(Color.kxGreen)
          }
        }

        ForEach(plans) { plan in
          HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
              Text("\(KXFormat.minutesToTime(plan.startMinutes)) · \(plan.plannedRings)K")
                .font(.headline)
                .fixedSize(horizontal: true, vertical: false)
              Text(plan.warehouse.rawValue)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
              onEdit(plan)
            } label: {
              Image(systemName: "pencil")
            }
            Button(role: .destructive) {
              onDelete(plan)
            } label: {
              Image(systemName: "trash")
            }
          }
          .padding(12)
          .background(Color.kxSurface2, in: RoundedRectangle(cornerRadius: 13))
        }
      }
    }
  }
}

struct CalendarPlanEditorSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var context

  let date: Date
  let plan: CalendarPlan?

  @State private var selectedDate = Date.now
  @State private var time = Date.now
  @State private var warehouse: Warehouse = .liboc
  @State private var rings = 4
  @State private var errorMessage = ""

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 18) {
          KXHeader(
            title: plan == nil ? "Добавить план" : "Изменить план",
            subtitle: "Время вводится одним полем — без отдельного пункта «Минуты»"
          )
          KXCard {
            VStack(spacing: 16) {
              DatePicker("День", selection: $selectedDate, displayedComponents: .date)
                .datePickerStyle(.compact)
              DatePicker("Время", selection: $time, displayedComponents: .hourAndMinute)
                .datePickerStyle(.compact)
              HStack {
                Text("Склад")
                Spacer()
                Picker("Склад", selection: $warehouse) {
                  ForEach(Warehouse.allCases) { item in
                    Text(item.rawValue).tag(item)
                  }
                }
              }
              HStack {
                Text("Колечек: \(rings)")
                Spacer()
                Stepper("", value: $rings, in: 1...20).labelsHidden()
              }
            }
          }
          KXErrorText(text: errorMessage)
          KXPrimaryButton(title: "Сохранить", icon: "checkmark") { save() }
          KXSecondaryButton(title: "Отмена") { dismiss() }
        }
        .padding(18)
      }
      .kxPageBackground()
      .navigationBarHidden(true)
      .onAppear {
        selectedDate = plan?.date ?? date
        warehouse = plan?.warehouse ?? .liboc
        rings = plan?.plannedRings ?? 4
        let minutes = plan?.startMinutes ?? 360
        time =
          Calendar.current.date(
            bySettingHour: minutes / 60,
            minute: minutes % 60,
            second: 0,
            of: selectedDate
          ) ?? selectedDate
      }
    }
  }

  private func save() {
    let components = Calendar.current.dateComponents([.hour, .minute], from: time)
    let minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
    guard (0..<1440).contains(minutes) else {
      errorMessage = "Выберите корректное время."
      return
    }
    if let plan {
      plan.date = selectedDate.startOfDay
      plan.startMinutes = minutes
      plan.plannedRings = rings
      plan.warehouse = warehouse
      plan.sourceRaw = DataSource.correction.rawValue
      audit(
        context, action: "edit", entityType: "calendar", entityID: plan.id.uuidString,
        details: KXFormat.date(selectedDate))
    } else {
      let newPlan = CalendarPlan(
        date: selectedDate.startOfDay,
        warehouse: warehouse,
        startMinutes: minutes,
        plannedRings: rings,
        source: .manual
      )
      context.insert(newPlan)
      audit(
        context, action: "create", entityType: "calendar", entityID: newPlan.id.uuidString,
        details: KXFormat.date(selectedDate))
    }
    do {
      try context.save()
      dismiss()
    } catch {
      errorMessage = "Не удалось сохранить план: \(error.localizedDescription)"
    }
  }
}

extension CalendarParseResult: Identifiable {
  var id: String { "\(month.timeIntervalSince1970)-\(rawText.hashValue)" }
}

struct CalendarImportReviewSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var context

  let result: CalendarParseResult
  @State private var drafts: [CalendarImportDraft] = []
  @State private var errorMessage = ""
  @State private var showRawText = false

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 16) {
          KXHeader(
            title: "Проверка импорта",
            subtitle: "\(KXFormat.monthTitle(result.month)) · найдено \(drafts.count) блоков"
          )

          ForEach(result.warnings, id: \.self) { warning in
            Label(warning, systemImage: "exclamationmark.triangle.fill")
              .font(.footnote)
              .foregroundStyle(.orange)
              .frame(maxWidth: .infinity, alignment: .leading)
          }

          if drafts.isEmpty {
            KXCard {
              VStack(alignment: .leading, spacing: 10) {
                Text("Ничего не распознано")
                  .font(.title3.bold())
                Text(
                  "Проверьте, что скриншот содержит название месяца, номера дней и блоки времени с количеством колечек."
                )
                .foregroundStyle(.secondary)
                Button("Показать распознанный текст") {
                  showRawText.toggle()
                }
                .foregroundStyle(Color.kxGreen)
              }
            }
          } else {
            ForEach($drafts) { $draft in
              CalendarDraftCard(draft: $draft) {
                drafts.removeAll { $0.id == draft.id }
              }
            }
          }

          if showRawText {
            KXCard {
              Text(result.rawText.isEmpty ? "OCR не вернул текст." : result.rawText)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
            }
          }

          KXErrorText(text: errorMessage)
          KXPrimaryButton(
            title: "Сохранить \(drafts.count) блоков",
            icon: "checkmark.circle.fill",
            disabled: drafts.isEmpty
          ) {
            save()
          }
          KXSecondaryButton(title: "Отмена") { dismiss() }
        }
        .padding(18)
      }
      .scrollDismissesKeyboard(.interactively)
      .kxPageBackground()
      .navigationBarHidden(true)
      .onAppear { drafts = result.entries }
    }
  }

  private func save() {
    errorMessage = ""
    for draft in drafts {
      let existingDescriptor = FetchDescriptor<CalendarPlan>()
      let existing = (try? context.fetch(existingDescriptor))?.first {
        $0.deletedAt == nil
          && $0.date.sameDay(as: draft.date)
          && $0.startMinutes == draft.startMinutes
          && $0.warehouse == draft.warehouse
      }
      if let existing {
        existing.plannedRings = draft.rings
        existing.confidence = draft.confidence
        existing.sourceRaw = DataSource.ocr.rawValue
      } else {
        context.insert(
          CalendarPlan(
            date: draft.date.startOfDay,
            warehouse: draft.warehouse,
            startMinutes: draft.startMinutes,
            plannedRings: draft.rings,
            source: .ocr,
            confidence: draft.confidence
          )
        )
      }
    }
    audit(
      context,
      action: "import",
      entityType: "calendar",
      entityID: UUID().uuidString,
      details: "Импортировано \(drafts.count) рабочих блоков"
    )
    do {
      try context.save()
      dismiss()
    } catch {
      errorMessage = "Не удалось сохранить импорт: \(error.localizedDescription)"
    }
  }
}

struct CalendarDraftCard: View {
  @Binding var draft: CalendarImportDraft
  let onDelete: () -> Void

  private var timeBinding: Binding<Date> {
    Binding {
      Calendar.current.date(
        bySettingHour: draft.startMinutes / 60,
        minute: draft.startMinutes % 60,
        second: 0,
        of: draft.date
      ) ?? draft.date
    } set: { newValue in
      let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
      draft.startMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
  }

  var body: some View {
    KXCard {
      VStack(spacing: 12) {
        HStack {
          DatePicker("День", selection: $draft.date, displayedComponents: .date)
          Button(role: .destructive, action: onDelete) {
            Image(systemName: "trash")
          }
        }
        DatePicker("Время", selection: timeBinding, displayedComponents: .hourAndMinute)
        HStack {
          Picker("Склад", selection: $draft.warehouse) {
            ForEach(Warehouse.allCases) { Text($0.rawValue).tag($0) }
          }
          Spacer()
          Stepper("\(draft.rings)K", value: $draft.rings, in: 1...20)
            .fixedSize()
        }
        ProgressView(value: draft.confidence)
          .tint(draft.confidence >= 0.65 ? Color.kxGreen : .orange)
      }
    }
  }
}

// MARK: - Statistics

struct StatisticsView: View {
  enum Period: String, CaseIterable, Identifiable {
    case day = "День"
    case week = "Неделя"
    case month = "Месяц"
    case custom = "Период"
    case all = "Всё"
    var id: String { rawValue }
  }

  @Query(sort: \Shift.date, order: .reverse) private var shifts: [Shift]
  @Query(sort: \Route.date, order: .reverse) private var routes: [Route]
  @Query(sort: \Customer.date, order: .reverse) private var customers: [Customer]
  @Query(sort: \FinancialEntry.date, order: .reverse) private var finances: [FinancialEntry]
  @Query(sort: \FuelEntry.date, order: .reverse) private var expenses: [FuelEntry]
  @Query(sort: \AdvanceEntry.date, order: .reverse) private var advances: [AdvanceEntry]

  @State private var period: Period = .month
  @State private var customStart =
    Calendar.current.date(byAdding: .day, value: -30, to: Date.now) ?? Date.now
  @State private var customEnd = Date.now
  @State private var showDateRange = false

  private var filteredRoutes: [Route] {
    routes.filter { $0.deletedAt == nil && included($0.date) }
  }

  private var filteredShifts: [Shift] {
    shifts.filter { $0.deletedAt == nil && included($0.date) }
  }

  private var routeResults: [(Route, RouteMoney)] {
    filteredRoutes.map { ($0, EarningsCalculator.route($0, customers: customers)) }
  }

  private var orders: Int { filteredRoutes.reduce(0) { $0 + $1.factualOrders } }
  private var rings: Int { filteredRoutes.reduce(0) { $0 + $1.type.rings } }
  private var minutes: Int { filteredShifts.reduce(0) { $0 + $1.durationMinutes } }
  private var base: Int64 { routeResults.reduce(Int64(0)) { $0 + $1.1.base } }
  private var regionBonus: Int64 { routeResults.reduce(Int64(0)) { $0 + $1.1.regionBonus } }
  private var tips: Int64 { routeResults.reduce(Int64(0)) { $0 + $1.1.tips } }
  private var routeGross: Int64 { routeResults.reduce(Int64(0)) { $0 + $1.1.gross } }
  private var bonuses: Int64 {
    finances.filter { $0.deletedAt == nil && included($0.date) && $0.kind == .bonus }
      .reduce(Int64(0)) { $0 + $1.amountHellers }
  }
  private var compensations: Int64 {
    finances.filter { $0.deletedAt == nil && included($0.date) && $0.kind == .compensation }
      .reduce(Int64(0)) { $0 + $1.amountHellers }
  }
  private var penalties: Int64 {
    finances.filter { $0.deletedAt == nil && included($0.date) && $0.kind == .penalty }
      .reduce(Int64(0)) { $0 + $1.amountHellers }
  }
  private var diesel: Int64 {
    expenses.filter { $0.deletedAt == nil && included($0.date) }
      .reduce(Int64(0)) { $0 + $1.amountHellers }
  }
  private var advance: Int64 {
    advances.filter { $0.deletedAt == nil && included($0.date) }
      .reduce(Int64(0)) { $0 + $1.amountHellers }
  }
  private var total: Int64 {
    routeGross + bonuses + compensations - penalties - diesel - advance
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 16) {
        KXHeader(
          title: "Статистика",
          subtitle: "Удалённые трассы исключаются из расчётов до восстановления из корзины."
        )
        .padding(.top, 10)

        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            ForEach(Period.allCases) { item in
              KXChip(title: item.rawValue, selected: period == item) {
                period = item
                if item == .custom { showDateRange = true }
              }
            }
          }
        }

        if period == .custom {
          Button {
            showDateRange = true
          } label: {
            Label(
              "\(KXFormat.shortDate(customStart)) — \(KXFormat.shortDate(customEnd))",
              systemImage: "calendar.badge.clock"
            )
            .foregroundStyle(Color.kxGreen)
            .frame(maxWidth: .infinity, alignment: .leading)
          }
        }

        KXCard {
          VStack(alignment: .leading, spacing: 10) {
            Text("\(orders) заказов")
              .font(.system(size: 34, weight: .bold, design: .rounded))
            Text("\(rings) колечек · \(filteredShifts.count) смен · \(KXFormat.duration(minutes))")
              .foregroundStyle(.secondary)
            Divider()
            Text(
              "OT \(filteredRoutes.filter { $0.type == .ot }.count) · Region \(filteredRoutes.filter { $0.type == .region }.count) · Express \(filteredRoutes.filter { $0.type == .express }.count)"
            )
            Text("Базовая оплата \(KXFormat.money(base))")
            Text("Region \(KXFormat.money(regionBonus)) · чаевые \(KXFormat.money(tips))")
            Text("По трассам \(KXFormat.money(routeGross))")
              .font(.title2.bold())
          }
        }

        LazyVGrid(
          columns: [GridItem(.flexible()), GridItem(.flexible())],
          spacing: 12
        ) {
          metric(KXFormat.money(orders > 0 ? total / Int64(orders) : 0), "Kč / заказ")
          metric(KXFormat.money(minutes > 0 ? total * 60 / Int64(minutes) : 0), "Kč / час")
          metric(
            String(format: "%.2f", minutes > 0 ? Double(orders) * 60 / Double(minutes) : 0),
            "Заказов / час")
          metric(
            String(format: "%.2f", minutes > 0 ? Double(rings) * 60 / Double(minutes) : 0),
            "Колечек / час")
          metric(KXFormat.money(orders > 0 ? tips / Int64(orders) : 0), "Чаевые / заказ")
          metric(KXFormat.money(total), "Итого")
        }

        KXCard {
          VStack(alignment: .leading, spacing: 9) {
            Text("Финансы за выбранный период")
              .font(.title2.bold())
            LabeledContent("Трассы", value: KXFormat.money(routeGross))
            LabeledContent("Бонусы", value: KXFormat.money(bonuses))
            LabeledContent("Компенсации", value: KXFormat.money(compensations))
            LabeledContent("Штрафы", value: "− \(KXFormat.money(penalties))")
            LabeledContent("Дизель и авторасходы", value: "− \(KXFormat.money(diesel))")
            LabeledContent("Авансы", value: "− \(KXFormat.money(advance))")
            Divider()
            LabeledContent("Итог", value: KXFormat.money(total))
              .font(.headline)
          }
        }

        if !filteredRoutes.isEmpty {
          KXCard {
            VStack(alignment: .leading, spacing: 10) {
              Text("Заработок по трассам")
                .font(.headline)
              Chart(Array(filteredRoutes.prefix(40))) { route in
                BarMark(
                  x: .value("Дата", route.date, unit: .day),
                  y: .value(
                    "Kč", Double(EarningsCalculator.route(route, customers: customers).gross) / 100)
                )
                .foregroundStyle(Color.kxGreen.gradient)
              }
              .frame(height: 190)
            }
          }
        }
      }
      .padding(.horizontal, 18)
      .padding(.bottom, 24)
    }
    .kxPageBackground()
    .navigationBarHidden(true)
    .sheet(isPresented: $showDateRange) {
      CustomPeriodSheet(start: $customStart, end: $customEnd)
    }
  }

  private func included(_ date: Date) -> Bool {
    let calendar = Calendar.current
    let now = Date.now
    switch period {
    case .day:
      return calendar.isDateInToday(date)
    case .week:
      return calendar.dateInterval(of: .weekOfYear, for: now)?.contains(date) ?? true
    case .month:
      return date.monthKey == now.monthKey
    case .custom:
      let start = customStart.startOfDay
      let end = customEnd.adding(days: 1).startOfDay
      return date >= start && date < end
    case .all:
      return true
    }
  }

  private func metric(_ value: String, _ title: String) -> some View {
    KXCard {
      VStack(alignment: .leading, spacing: 5) {
        Text(value)
          .font(.title2.bold())
          .lineLimit(1)
          .minimumScaleFactor(0.72)
        Text(title)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }
}

struct CustomPeriodSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Binding var start: Date
  @Binding var end: Date
  @State private var errorMessage = ""

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 18) {
          KXHeader(title: "Выбрать период")
          KXCard {
            VStack(spacing: 14) {
              DatePicker("Начало", selection: $start, displayedComponents: .date)
              DatePicker("Конец", selection: $end, displayedComponents: .date)
            }
          }
          KXErrorText(text: errorMessage)
          KXPrimaryButton(title: "Применить", icon: "checkmark") {
            guard end >= start else {
              errorMessage = "Дата окончания не может быть раньше начала."
              return
            }
            dismiss()
          }
          KXSecondaryButton(title: "Отмена") { dismiss() }
        }
        .padding(18)
      }
      .kxPageBackground()
      .navigationBarHidden(true)
    }
  }
}

// MARK: - Scanner

struct ScannerView: View {
  enum Mode: String, CaseIterable, Identifiable {
    case route = "Трасса"
    case customers = "Заказники"
    case courierStats = "Статистика курьера"
    case finance = "Бонусы / штрафы"

    var id: String { rawValue }
    var subtitle: String {
      switch self {
      case .route: return "Фото сообщения после завершения трассы"
      case .customers: return "Одна или несколько фотографий списка клиентов"
      case .courierStats: return "Снимок накопительной статистики"
      case .finance: return "Бонус, компенсация или штраф"
      }
    }
    var icon: String {
      switch self {
      case .route: return "point.topleft.down.to.point.bottomright.curvepath"
      case .customers: return "person.2.fill"
      case .courierStats: return "chart.bar.doc.horizontal.fill"
      case .finance: return "banknote.fill"
      }
    }
  }

  @Environment(\.modelContext) private var context
  @Query(sort: \Shift.date, order: .reverse) private var shifts: [Shift]
  @Query(sort: \Route.date, order: .reverse) private var routes: [Route]
  @Query private var preferences: [AppPreference]

  @State private var mode: Mode = .route
  @State private var selectedPhotos: [PhotosPickerItem] = []
  @State private var showCamera = false
  @State private var busy = false
  @State private var message = ""
  @State private var errorMessage = ""
  @State private var rawOCR = ""

  @State private var routeType: RouteType = .ot
  @State private var routeOrders = ""
  @State private var routeKilometers = ""
  @State private var routeExternalID = ""

  @State private var customerDrafts: [CustomerDraft] = []
  @State private var showCustomerReview = false

  @State private var cumulativeOrders = ""
  @State private var cumulativeTips = ""

  @State private var financeKind: FinancialKind = .bonus
  @State private var financeAmount = ""
  @State private var financeDescription = ""

  private var activeShift: Shift? {
    shifts.first { $0.deletedAt == nil && $0.status == .active }
  }

  private var previewMoney: RouteMoney {
    EarningsCalculator.preview(
      date: Date.now,
      type: routeType,
      orders: Int(routeOrders) ?? 0,
      tips: 0
    )
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 14) {
        KXHeader(
          title: "Сканер",
          subtitle: "Каждый тип экрана распознаётся отдельно — так надёжнее."
        )
        .padding(.top, 10)

        ForEach(Mode.allCases) { item in
          Button {
            switchMode(item)
          } label: {
            HStack(spacing: 14) {
              Image(systemName: item.icon)
                .font(.system(size: 24, weight: .semibold))
              VStack(alignment: .leading, spacing: 4) {
                Text(item.rawValue).font(.headline)
                Text(item.subtitle)
                  .font(.caption)
                  .foregroundStyle(
                    mode == item ? Color.white.opacity(0.8) : .secondary
                  )
              }
              Spacer()
            }
            .padding(17)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
              mode == item ? Color.kxPurple : Color.kxSurface2,
              in: RoundedRectangle(cornerRadius: 17, style: .continuous)
            )
            .overlay {
              RoundedRectangle(cornerRadius: 17)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
            }
          }
          .buttonStyle(.plain)
        }

        HStack(spacing: 12) {
          Button {
            showCamera = true
          } label: {
            Label("Камера", systemImage: "camera.fill")
              .frame(maxWidth: .infinity)
              .frame(height: 52)
          }
          .buttonStyle(.plain)
          .background(Color.kxSurface2, in: RoundedRectangle(cornerRadius: 16))
          .overlay { RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.13)) }

          PhotosPicker(
            selection: $selectedPhotos,
            maxSelectionCount: mode == .customers ? 12 : 1,
            matching: .images
          ) {
            Label("Галерея", systemImage: "photo.on.rectangle.angled")
              .fontWeight(.semibold)
              .foregroundStyle(Color.kxBackground)
              .frame(maxWidth: .infinity)
              .frame(height: 52)
              .background(Color.kxGreen, in: RoundedRectangle(cornerRadius: 16))
          }
        }

        if busy {
          KXCard {
            HStack {
              ProgressView()
              Text("Распознаю выбранные изображения…")
            }
          }
        }

        modeContent

        KXErrorText(text: errorMessage)
        if !message.isEmpty {
          Label(message, systemImage: "checkmark.circle.fill")
            .foregroundStyle(Color.kxGreen)
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        if !rawOCR.isEmpty {
          DisclosureGroup("Распознанный текст") {
            Text(rawOCR)
              .font(.system(.caption, design: .monospaced))
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.top, 8)
          }
          .padding(16)
          .background(Color.kxSurface, in: RoundedRectangle(cornerRadius: 18))
        }
      }
      .padding(.horizontal, 18)
      .padding(.bottom, 24)
    }
    .scrollDismissesKeyboard(.interactively)
    .kxDismissKeyboardOnTap()
    .kxPageBackground()
    .navigationBarHidden(true)
    .toolbar { KeyboardDoneToolbar() }
    .onChange(of: selectedPhotos) { _, items in
      guard !items.isEmpty else { return }
      Task { await processPhotoItems(items) }
    }
    .sheet(isPresented: $showCamera) {
      CameraPicker { image in
        Task { await processImages([image]) }
      }
    }
    .sheet(isPresented: $showCustomerReview) {
      CustomerImportReviewSheet(drafts: customerDrafts, availableRoutes: routesForCurrentShift)
    }
  }

  @ViewBuilder
  private var modeContent: some View {
    switch mode {
    case .route:
      routeSection
    case .customers:
      customersSection
    case .courierStats:
      statsSection
    case .finance:
      financeSection
    }
  }

  private var routeSection: some View {
    VStack(spacing: 14) {
      Text("Проверка трассы")
        .font(.title2.bold())
        .frame(maxWidth: .infinity, alignment: .leading)
      Text("Тип трассы всегда выбирается вручную. Чаевые и итог рассчитываются приложением.")
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)

      Picker("Тип трассы", selection: $routeType) {
        ForEach(RouteType.allCases) { Text($0.rawValue).tag($0) }
      }
      .pickerStyle(.segmented)

      KXInput(title: "Количество заказов", text: $routeOrders, keyboard: .numberPad)
      KXInput(title: "Километраж", text: $routeKilometers, keyboard: .decimalPad)
      if !routeExternalID.isEmpty {
        KXInput(title: "ID трассы", text: $routeExternalID)
      }

      KXCard {
        VStack(alignment: .leading, spacing: 6) {
          Text("Автоматический расчёт").font(.headline)
          LabeledContent("Базовая оплата", value: KXFormat.money(previewMoney.base))
          LabeledContent("Region", value: KXFormat.money(previewMoney.regionBonus))
          LabeledContent("Итог без чаевых", value: KXFormat.money(previewMoney.gross))
          Text("Чаевые добавятся из заказников, привязанных к этой трассе.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      KXPrimaryButton(
        title: "Сохранить закрытую трассу",
        icon: "checkmark.circle.fill",
        disabled: activeShift == nil
          || (Int(routeOrders) ?? 0) <= 0
          || (Double(routeKilometers.replacingOccurrences(of: ",", with: ".")) ?? 0) <= 0
      ) {
        saveRoute()
      }

      if activeShift == nil {
        Text("Сначала начните смену на Главной.")
          .font(.footnote)
          .foregroundStyle(.orange)
      }
    }
  }

  private var customersSection: some View {
    VStack(spacing: 14) {
      KXCard {
        VStack(alignment: .leading, spacing: 8) {
          Text("Импорт заказников").font(.title3.bold())
          Text(
            "Выберите одно или несколько фото. Порядок фотографий и клиентов внутри каждого фото будет сохранён."
          )
          .foregroundStyle(.secondary)
          Text(
            "После OCR откроется экран проверки с ручным добавлением, изменением адресов, пакетов и чаевых."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
      }

      if !customerDrafts.isEmpty {
        KXPrimaryButton(
          title: "Проверить \(customerDrafts.count) клиентов",
          icon: "person.2.badge.gearshape"
        ) {
          showCustomerReview = true
        }
      }

      if routesForCurrentShift.isEmpty {
        Text("Для привязки заказников сначала сохраните закрытую трассу этой смены.")
          .font(.footnote)
          .foregroundStyle(.orange)
      }
    }
  }

  private var statsSection: some View {
    VStack(spacing: 14) {
      KXCard {
        VStack(alignment: .leading, spacing: 8) {
          Text("Накопительная статистика").font(.title3.bold())
          Text("Первое значение становится baseline. Следующие импорты считают разницу с baseline.")
            .foregroundStyle(.secondary)
          if let baseline = ordersBaseline {
            LabeledContent("Baseline", value: "\(baseline) заказов")
          } else {
            Text("Baseline ещё не установлен.").foregroundStyle(.orange)
          }
        }
      }
      KXInput(
        title: "Накопительное количество заказов", text: $cumulativeOrders, keyboard: .numberPad)
      KXInput(
        title: "Накопительные чаевые Kč (необязательно)", text: $cumulativeTips,
        keyboard: .decimalPad)
      if let current = Int(cumulativeOrders), let baseline = ordersBaseline {
        KXCard {
          LabeledContent("Новых заказов", value: "\(max(0, current - baseline))")
            .font(.headline)
        }
      }
      KXPrimaryButton(
        title: "Сохранить статистику",
        icon: "chart.bar.doc.horizontal.fill",
        disabled: (Int(cumulativeOrders) ?? 0) <= 0
      ) {
        saveStatistics()
      }
    }
  }

  private var financeSection: some View {
    VStack(spacing: 14) {
      Picker("Тип", selection: $financeKind) {
        ForEach(FinancialKind.allCases) { Text($0.rawValue).tag($0) }
      }
      .pickerStyle(.segmented)
      KXInput(title: "Сумма Kč", text: $financeAmount, keyboard: .decimalPad)
      KXInput(title: "Комментарий", text: $financeDescription)
      KXPrimaryButton(
        title: "Сохранить операцию",
        icon: "banknote.fill",
        disabled: (Double(financeAmount.replacingOccurrences(of: ",", with: ".")) ?? 0) <= 0
      ) {
        saveFinance()
      }
      Text("Фото сначала распознаётся, затем сумма и описание показываются здесь для проверки.")
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var routesForCurrentShift: [Route] {
    guard let shift = activeShift else { return [] }
    return
      routes
      .filter { $0.deletedAt == nil && $0.shiftID == shift.id }
      .sorted { $0.sequence > $1.sequence }
  }

  private var ordersBaseline: Int? {
    preferences.first { $0.key == "ordersBaseline" }.flatMap { Int($0.value) }
  }

  private func switchMode(_ newMode: Mode) {
    mode = newMode
    errorMessage = ""
    message = ""
    rawOCR = ""
    selectedPhotos = []
  }

  private func processPhotoItems(_ items: [PhotosPickerItem]) async {
    busy = true
    errorMessage = ""
    message = ""
    defer {
      busy = false
      selectedPhotos = []
    }
    var images: [UIImage] = []
    for item in items {
      if let data = try? await item.loadTransferable(type: Data.self),
        let image = UIImage(data: data)
      {
        images.append(image)
      }
    }
    guard !images.isEmpty else {
      errorMessage = "Не удалось открыть выбранные изображения."
      return
    }
    await processImages(images)
  }

  private func processImages(_ images: [UIImage]) async {
    busy = true
    errorMessage = ""
    message = ""
    defer { busy = false }
    do {
      var documents: [OCRDocument] = []
      for image in images {
        documents.append(try await OCRService.recognize(image))
      }
      guard documents.contains(where: { !$0.lines.isEmpty }) else { throw OCRError.noText }
      rawOCR = documents.map(\.text).joined(separator: "\n\n--- ФОТО ---\n\n")

      switch mode {
      case .route:
        let parsed = RouteOCRParser.parse(rawOCR)
        if let orders = parsed.orders { routeOrders = String(orders) }
        if let km = parsed.distanceKm { routeKilometers = KXFormat.number(km) }
        routeExternalID = parsed.externalRouteID ?? ""
        message = "Данные трассы распознаны. Проверьте поля и сохраните."
      case .customers:
        customerDrafts = CustomerOCRParser.parse(documents: documents)
        if customerDrafts.isEmpty {
          errorMessage = "Не удалось выделить клиентов. Откройте проверку и добавьте их вручную."
          customerDrafts = []
        }
        showCustomerReview = true
      case .courierStats:
        let parsed = StatsOCRParser.parse(rawOCR)
        if let orders = parsed.cumulativeOrders { cumulativeOrders = String(orders) }
        if let tips = parsed.cumulativeTipsHellers { cumulativeTips = String(Double(tips) / 100) }
        message =
          parsed.cumulativeOrders == nil
          ? "OCR завершён. Введите накопительное число вручную."
          : "Статистика распознана. Проверьте значение."
      case .finance:
        let parsed = FinanceOCRParser.parse(rawOCR)
        if let amount = parsed.amountHellers { financeAmount = String(Double(amount) / 100) }
        financeDescription = parsed.description
        message = "Операция распознана. Проверьте сумму и тип."
      }
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func saveRoute() {
    errorMessage = ""
    message = ""
    guard let shift = activeShift else {
      errorMessage = "Сначала начните смену."
      return
    }
    guard let orders = Int(routeOrders), orders > 0 else {
      errorMessage = "Введите количество заказов."
      return
    }
    guard let km = Double(routeKilometers.replacingOccurrences(of: ",", with: ".")), km > 0 else {
      errorMessage = "Введите километраж трассы."
      return
    }
    let nextSequence =
      routes.filter { $0.shiftID == shift.id && $0.deletedAt == nil }.map(\.sequence).max().map {
        $0 + 1
      } ?? 1
    let route = Route(
      shiftID: shift.id,
      sequence: nextSequence,
      type: routeType,
      warehouse: shift.warehouse,
      factualOrders: orders,
      distanceKm: km,
      externalRouteID: routeExternalID.isEmpty ? nil : routeExternalID,
      confirmed: true,
      source: rawOCR.isEmpty ? .manual : .ocr
    )
    route.finishedAt = Date.now
    context.insert(route)
    audit(
      context, action: "create", entityType: "route", entityID: route.id.uuidString,
      details: "\(routeType.rawValue), \(orders) заказов, \(km) км")
    do {
      try context.save()
      routeOrders = ""
      routeKilometers = ""
      routeExternalID = ""
      rawOCR = ""
      message = "Трасса #\(nextSequence) сохранена."
    } catch {
      errorMessage = "Не удалось сохранить трассу: \(error.localizedDescription)"
    }
  }

  private func saveStatistics() {
    errorMessage = ""
    guard let current = Int(cumulativeOrders), current > 0 else {
      errorMessage = "Введите накопительное количество заказов."
      return
    }
    let baseline: Int
    if let existing = ordersBaseline {
      baseline = existing
    } else {
      baseline = current
      let preference = AppPreference(key: "ordersBaseline", value: String(current))
      context.insert(preference)
    }
    let tips = Int64((Double(cumulativeTips.replacingOccurrences(of: ",", with: ".")) ?? 0) * 100)
    let snapshot = StatisticsSnapshot(
      cumulativeOrders: current,
      cumulativeTipsHellers: tips > 0 ? tips : nil,
      deltaOrders: max(0, current - baseline),
      rawText: rawOCR
    )
    context.insert(snapshot)
    audit(
      context, action: "import", entityType: "statistics", entityID: snapshot.id.uuidString,
      details: "Накопительно \(current), delta \(snapshot.deltaOrders)")
    do {
      try context.save()
      message =
        ordersBaseline == nil
        ? "Baseline установлен: \(current)."
        : "Сохранено новых заказов: \(snapshot.deltaOrders)."
      cumulativeOrders = ""
      cumulativeTips = ""
      rawOCR = ""
    } catch {
      errorMessage = "Не удалось сохранить статистику: \(error.localizedDescription)"
    }
  }

  private func saveFinance() {
    errorMessage = ""
    guard let amount = Double(financeAmount.replacingOccurrences(of: ",", with: ".")), amount > 0
    else {
      errorMessage = "Введите корректную сумму."
      return
    }
    let entry = FinancialEntry(
      kind: financeKind,
      amountHellers: Int64(amount * 100),
      note: financeDescription,
      source: rawOCR.isEmpty ? DataSource.manual.rawValue : DataSource.ocr.rawValue
    )
    context.insert(entry)
    audit(
      context, action: "create", entityType: "finance", entityID: entry.id.uuidString,
      details: "\(financeKind.rawValue) \(amount) Kč")
    do {
      try context.save()
      financeAmount = ""
      financeDescription = ""
      rawOCR = ""
      message = "Операция сохранена."
    } catch {
      errorMessage = "Не удалось сохранить операцию: \(error.localizedDescription)"
    }
  }
}

struct CustomerImportReviewSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var context

  let initialDrafts: [CustomerDraft]
  let availableRoutes: [Route]

  @State private var drafts: [CustomerDraft]
  @State private var selectedRouteID: UUID?
  @State private var editingDraft: CustomerDraft?
  @State private var showManualAdd = false
  @State private var errorMessage = ""
  @State private var saving = false

  init(drafts: [CustomerDraft], availableRoutes: [Route]) {
    initialDrafts = drafts
    self.availableRoutes = availableRoutes
    _drafts = State(initialValue: drafts)
    _selectedRouteID = State(initialValue: availableRoutes.first?.id)
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 15) {
          KXHeader(
            title: "Проверка заказников",
            subtitle: "Проверьте порядок, адреса, пакеты и чаевые"
          )

          if availableRoutes.isEmpty {
            KXCard {
              Label(
                "Нет закрытой трассы текущей смены. Сначала сохраните трассу.",
                systemImage: "exclamationmark.triangle.fill"
              )
              .foregroundStyle(.orange)
            }
          } else {
            KXCard {
              HStack {
                Text("Привязать к трассе").font(.headline)
                Spacer()
                Picker("Трасса", selection: $selectedRouteID) {
                  ForEach(availableRoutes) { route in
                    Text("#\(route.sequence) \(route.type.rawValue)")
                      .tag(Optional(route.id))
                  }
                }
              }
            }
          }

          HStack(spacing: 12) {
            KXSecondaryButton(title: "Добавить вручную", icon: "person.badge.plus") {
              showManualAdd = true
            }
            KXSecondaryButton(title: "Очистить", icon: "trash", destructive: true) {
              drafts = []
            }
          }

          if drafts.isEmpty {
            KXCard {
              Text("OCR не создал ни одной карточки. Нажмите «Добавить вручную».")
                .foregroundStyle(.secondary)
            }
          }

          ForEach(Array(drafts.enumerated()), id: \.element.id) { index, draft in
            CustomerDraftCard(
              draft: draft,
              index: index,
              total: drafts.count,
              onEdit: { editingDraft = draft },
              onUp: { move(index, by: -1) },
              onDown: { move(index, by: 1) },
              onDelete: { drafts.removeAll { $0.id == draft.id } }
            )
          }

          KXErrorText(text: errorMessage)
          KXPrimaryButton(
            title: saving ? "Проверяю адреса…" : "Добавить \(drafts.count) клиентов",
            icon: "checkmark.circle.fill",
            disabled: drafts.isEmpty || selectedRouteID == nil || saving
          ) {
            Task { await save() }
          }
          KXSecondaryButton(title: "Отмена") { dismiss() }
        }
        .padding(18)
      }
      .kxPageBackground()
      .navigationBarHidden(true)
      .sheet(item: $editingDraft) { draft in
        CustomerDraftEditorSheet(draft: draft) { updated in
          if let index = drafts.firstIndex(where: { $0.id == updated.id }) {
            drafts[index] = updated
          }
        }
      }
      .sheet(isPresented: $showManualAdd) {
        CustomerDraftEditorSheet(
          draft: CustomerDraft(
            photoOrder: drafts.map(\.photoOrder).max().map { $0 + 1 } ?? 0,
            position: drafts.count,
            firstName: "",
            lastName: "",
            address: "",
            bags: 0,
            tipsHellers: 0
          )
        ) { newDraft in
          drafts.append(newDraft)
        }
      }
    }
  }

  private func move(_ index: Int, by delta: Int) {
    let destination = index + delta
    guard drafts.indices.contains(index), drafts.indices.contains(destination) else { return }
    drafts.swapAt(index, destination)
    for i in drafts.indices { drafts[i].position = i }
  }

  private func save() async {
    guard let selectedRouteID,
      let route = availableRoutes.first(where: { $0.id == selectedRouteID })
    else {
      errorMessage = "Выберите трассу."
      return
    }
    saving = true
    errorMessage = ""
    defer { saving = false }

    var verifiedDrafts = drafts
    for index in verifiedDrafts.indices {
      let name = verifiedDrafts[index].firstName.trimmingCharacters(in: .whitespacesAndNewlines)
      let address = verifiedDrafts[index].address.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !name.isEmpty, !address.isEmpty else {
        errorMessage = "У клиента №\(index + 1) не заполнено имя или адрес."
        return
      }
      do {
        if let official = try await RuianAddressService.shared.validate(address) {
          verifiedDrafts[index].address = official
          verifiedDrafts[index].normalizedAddress = RuianAddressService.normalize(official)
          verifiedDrafts[index].addressVerified = true
        } else {
          errorMessage =
            "RÚIAN не подтвердил адрес клиента №\(index + 1): \(address). Исправьте адрес и повторите."
          return
        }
      } catch {
        errorMessage = "Не удалось проверить RÚIAN: \(error.localizedDescription)"
        return
      }
    }

    for (index, draft) in verifiedDrafts.enumerated() {
      context.insert(
        Customer(
          routeID: route.id,
          date: route.date,
          routeSequence: route.sequence,
          routeType: route.type,
          position: index,
          photoOrder: draft.photoOrder,
          firstName: draft.firstName,
          lastName: draft.lastName,
          address: draft.address,
          normalizedAddress: draft.normalizedAddress,
          addressVerified: draft.addressVerified,
          bags: draft.bags,
          tipsHellers: draft.tipsHellers,
          source: .ocr
        )
      )
    }
    audit(
      context, action: "import", entityType: "customers", entityID: route.id.uuidString,
      details: "Добавлено \(verifiedDrafts.count) клиентов к трассе #\(route.sequence)")
    do {
      try context.save()
      dismiss()
    } catch {
      errorMessage = "Не удалось сохранить клиентов: \(error.localizedDescription)"
    }
  }
}

struct CustomerDraftCard: View {
  let draft: CustomerDraft
  let index: Int
  let total: Int
  let onEdit: () -> Void
  let onUp: () -> Void
  let onDown: () -> Void
  let onDelete: () -> Void

  var body: some View {
    KXCard {
      HStack(alignment: .top, spacing: 12) {
        Text("\(index + 1)")
          .font(.headline)
          .foregroundStyle(Color.kxGreen)
          .frame(width: 28, height: 28)
          .background(Color.kxGreen.opacity(0.12), in: Circle())
        VStack(alignment: .leading, spacing: 5) {
          Text((draft.firstName + " " + draft.lastName).trimmingCharacters(in: .whitespaces))
            .font(.headline)
          Text(draft.address)
            .foregroundStyle(.secondary)
          Text("Пакеты: \(draft.bags) · чаевые \(KXFormat.money(draft.tipsHellers))")
            .font(.caption)
            .foregroundStyle(Color.kxGreen)
          Text("Фото \(draft.photoOrder + 1)")
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        Spacer()
        VStack(spacing: 12) {
          Button(action: onEdit) { Image(systemName: "pencil") }
          Button(action: onUp) { Image(systemName: "chevron.up") }.disabled(index == 0)
          Button(action: onDown) { Image(systemName: "chevron.down") }.disabled(index == total - 1)
          Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
        }
      }
    }
  }
}

struct CustomerDraftEditorSheet: View {
  @Environment(\.dismiss) private var dismiss
  let original: CustomerDraft
  let onSave: (CustomerDraft) -> Void

  @State private var draft: CustomerDraft
  @State private var tips = ""
  @State private var suggestions: [RuianSuggestion] = []
  @State private var searching = false
  @State private var errorMessage = ""

  init(draft: CustomerDraft, onSave: @escaping (CustomerDraft) -> Void) {
    original = draft
    self.onSave = onSave
    _draft = State(initialValue: draft)
    _tips = State(
      initialValue: draft.tipsHellers == 0 ? "" : String(Double(draft.tipsHellers) / 100))
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 14) {
          KXHeader(title: original.firstName.isEmpty ? "Добавить клиента" : "Изменить клиента")
          KXCard {
            VStack(spacing: 12) {
              KXInput(title: "Имя", text: $draft.firstName)
              KXInput(title: "Фамилия", text: $draft.lastName)
              KXInput(title: "Адрес", text: $draft.address)
              if searching { ProgressView().frame(maxWidth: .infinity, alignment: .leading) }
              ForEach(suggestions.prefix(6)) { suggestion in
                Button {
                  draft.address = suggestion.text
                  draft.normalizedAddress = RuianAddressService.normalize(suggestion.text)
                  draft.addressVerified = true
                  suggestions = []
                } label: {
                  HStack {
                    Image(systemName: "mappin.and.ellipse")
                    Text(suggestion.text)
                      .multilineTextAlignment(.leading)
                    Spacer()
                  }
                  .foregroundStyle(.white)
                  .padding(10)
                  .background(Color.kxSurface2, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
              }
              Stepper("Пакеты: \(draft.bags)", value: $draft.bags, in: 0...99)
              KXInput(title: "Чаевые Kč", text: $tips, keyboard: .decimalPad)
            }
          }
          KXErrorText(text: errorMessage)
          KXPrimaryButton(title: "Сохранить", icon: "checkmark") { save() }
          KXSecondaryButton(title: "Отмена") { dismiss() }
        }
        .padding(18)
      }
      .scrollDismissesKeyboard(.interactively)
      .kxDismissKeyboardOnTap()
      .kxPageBackground()
      .navigationBarHidden(true)
      .toolbar { KeyboardDoneToolbar() }
      .task(id: draft.address) {
        guard !draft.addressVerified, draft.address.count >= 3 else { return }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        searching = true
        suggestions = (try? await RuianAddressService.shared.suggest(draft.address)) ?? []
        searching = false
      }
    }
  }

  private func save() {
    errorMessage = ""
    guard !draft.firstName.trimmingCharacters(in: .whitespaces).isEmpty else {
      errorMessage = "Введите имя клиента."
      return
    }
    guard !draft.address.trimmingCharacters(in: .whitespaces).isEmpty else {
      errorMessage = "Введите адрес клиента."
      return
    }
    draft.tipsHellers = Int64((Double(tips.replacingOccurrences(of: ",", with: ".")) ?? 0) * 100)
    onSave(draft)
    dismiss()
  }
}

// MARK: - More menu

struct MoreView: View {
  let isOwner: Bool

  var body: some View {
    ScrollView {
      VStack(spacing: 11) {
        HStack {
          KXHeader(title: "Ещё")
          NavigationLink {
            SettingsView()
          } label: {
            Image(systemName: "gearshape.fill")
              .font(.system(size: 29))
              .foregroundStyle(Color.kxGreen)
          }
        }
        .padding(.top, 12)
        .padding(.bottom, 5)

        NavigationLink {
          AccountView()
        } label: {
          KXSectionRow(
            title: "Аккаунт",
            subtitle: "Профиль, лицензия и устройство",
            icon: "person.crop.circle.fill"
          )
        }
        .buttonStyle(.plain)

        if isOwner {
          NavigationLink {
            OwnerControlView()
          } label: {
            KXSectionRow(
              title: "KurierX Control",
              subtitle: "Ключи, пользователи и блокировки",
              icon: "person.badge.shield.checkmark.fill"
            )
          }
          .buttonStyle(.plain)
        }

        KXMenuDivider()

        NavigationLink {
          ClientsView()
        } label: {
          KXSectionRow(
            title: "Клиенты",
            subtitle: "Все клиенты, адреса и история",
            icon: "person.2.fill"
          )
        }
        .buttonStyle(.plain)

        NavigationLink {
          ShiftsView()
        } label: {
          KXSectionRow(
            title: "Смены",
            subtitle: "Все смены, трассы и параметры",
            icon: "calendar.badge.clock"
          )
        }
        .buttonStyle(.plain)

        NavigationLink {
          FinanceListView(filter: .positive)
        } label: {
          KXSectionRow(
            title: "Бонусы и компенсации",
            subtitle: "Ручной ввод, камера и OCR",
            icon: "gift.fill"
          )
        }
        .buttonStyle(.plain)

        NavigationLink {
          FinanceListView(filter: .penalty)
        } label: {
          KXSectionRow(
            title: "Штрафы",
            subtitle: "Просмотр, добавление по фото и удаление",
            icon: "exclamationmark.triangle.fill",
            accent: .orange
          )
        }
        .buttonStyle(.plain)

        NavigationLink {
          AutoExpensesView()
        } label: {
          KXSectionRow(
            title: "Дизель и авторасходы",
            subtitle: "Топливо, парковка, сервис и поездки",
            icon: "fuelpump.fill"
          )
        }
        .buttonStyle(.plain)

        NavigationLink {
          AdvancesView()
        } label: {
          KXSectionRow(
            title: "Авансы",
            subtitle: "Полученные авансы и история",
            icon: "wallet.pass.fill"
          )
        }
        .buttonStyle(.plain)

        KXMenuDivider()

        NavigationLink {
          SalaryView()
        } label: {
          KXSectionRow(
            title: "Зарплата",
            subtitle: "Выплаты и сверка с расчётом",
            icon: "banknote.fill"
          )
        }
        .buttonStyle(.plain)

        NavigationLink {
          GoalsView()
        } label: {
          KXSectionRow(
            title: "Цели",
            subtitle: "План заказов и заработка",
            icon: "scope"
          )
        }
        .buttonStyle(.plain)

        KXMenuDivider()

        NavigationLink {
          BackupView()
        } label: {
          KXSectionRow(
            title: "Резервные копии",
            subtitle: "Экспорт и восстановление данных",
            icon: "externaldrive.fill"
          )
        }
        .buttonStyle(.plain)

        NavigationLink {
          AuditLogView()
        } label: {
          KXSectionRow(
            title: "Журнал",
            subtitle: "История действий в приложении",
            icon: "doc.text.fill"
          )
        }
        .buttonStyle(.plain)

        NavigationLink {
          TrashView()
        } label: {
          KXSectionRow(
            title: "Корзина",
            subtitle: "Удалённые данные и восстановление",
            icon: "trash.fill"
          )
        }
        .buttonStyle(.plain)

        KXMenuDivider()

        NavigationLink {
          DeveloperModeView()
        } label: {
          KXSectionRow(
            title: "Developer Mode",
            subtitle: "PIN, Face ID и расширенные возможности",
            icon: "shield.lefthalf.filled"
          )
        }
        .buttonStyle(.plain)

        NavigationLink {
          SettingsView()
        } label: {
          KXSectionRow(
            title: "Настройки",
            subtitle: "Ставки, склад и параметры приложения",
            icon: "gearshape.fill"
          )
        }
        .buttonStyle(.plain)

        HStack(spacing: 12) {
          NavigationLink {
            KilometerOverviewView()
          } label: {
            Text("Километраж")
              .fontWeight(.semibold)
              .frame(maxWidth: .infinity)
              .frame(height: 54)
              .background(Color.kxSurface2, in: RoundedRectangle(cornerRadius: 16))
              .overlay { RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.13)) }
          }
          .buttonStyle(.plain)

          NavigationLink {
            TutorialView()
          } label: {
            Text("Обучение / Как пользоваться")
              .fontWeight(.semibold)
              .foregroundStyle(Color.kxBackground)
              .multilineTextAlignment(.center)
              .frame(maxWidth: .infinity)
              .frame(height: 54)
              .background(Color.kxGreen, in: RoundedRectangle(cornerRadius: 16))
          }
          .buttonStyle(.plain)
        }
        .padding(.top, 4)
      }
      .padding(.horizontal, 18)
      .padding(.bottom, 24)
    }
    .kxPageBackground()
    .navigationBarHidden(true)
  }
}

struct KXMenuDivider: View {
  var body: some View {
    Rectangle()
      .fill(Color.white.opacity(0.07))
      .frame(height: 1)
      .padding(.vertical, 4)
  }
}

// MARK: Account

struct AccountView: View {
  @EnvironmentObject private var session: SessionStore

  var body: some View {
    ScrollView {
      VStack(spacing: 16) {
        KXHeader(title: "Аккаунт")
        KXCard {
          VStack(alignment: .leading, spacing: 10) {
            if session.isOwner {
              Label("OWNER", systemImage: "person.badge.shield.checkmark.fill")
                .font(.title2.bold())
                .foregroundStyle(Color.kxGreen)
              Text("OWNER использует обычный KurierX и открывает Control через раздел «Ещё».")
                .foregroundStyle(.secondary)
            } else if let profile = session.profile {
              Text(profile.firstName + " " + profile.lastName)
                .font(.title2.bold())
              LabeledContent("Courier ID", value: profile.courierID)
              LabeledContent("Статус", value: profile.status)
            }
          }
        }
        KXCard {
          VStack(alignment: .leading, spacing: 8) {
            Text("Устройство").font(.headline)
            LabeledContent("Модель", value: UIDevice.current.model)
            LabeledContent("Система", value: "iOS \(UIDevice.current.systemVersion)")
            Text(SessionStore.deviceID())
              .font(.system(.caption2, design: .monospaced))
              .foregroundStyle(.secondary)
              .textSelection(.enabled)
          }
        }
        KXSecondaryButton(
          title: session.isOwner ? "Выйти из OWNER" : "Выйти из аккаунта",
          icon: "rectangle.portrait.and.arrow.right",
          destructive: true
        ) {
          Task {
            if session.isOwner {
              await session.leaveOwnerToActivation()
            } else {
              await session.signOutUser()
            }
          }
        }
      }
      .padding(18)
    }
    .navigationTitle("Аккаунт")
    .navigationBarTitleDisplayMode(.inline)
    .kxPageBackground()
  }
}

// MARK: Clients

struct ClientsView: View {
  @Environment(\.modelContext) private var context
  @Query(sort: \Customer.date, order: .reverse) private var customers: [Customer]

  @State private var searchText = ""
  @State private var selectedCustomer: Customer?
  @State private var showAdd = false

  private var visibleCustomers: [Customer] {
    customers.filter { customer in
      guard customer.deletedAt == nil else { return false }
      if searchText.isEmpty { return true }
      return (customer.displayName + " " + customer.address)
        .localizedCaseInsensitiveContains(searchText)
    }
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 12) {
        KXHeader(
          title: "Клиенты",
          subtitle: "Адреса проверяются через RÚIAN"
        )
        KXInput(title: "Поиск по имени или адресу", text: $searchText)

        KXPrimaryButton(title: "Добавить клиента вручную", icon: "person.badge.plus") {
          showAdd = true
        }

        if visibleCustomers.isEmpty {
          KXCard {
            Text("Клиенты не найдены.")
              .foregroundStyle(.secondary)
          }
        }

        ForEach(visibleCustomers) { customer in
          Button {
            selectedCustomer = customer
          } label: {
            KXCard {
              HStack(spacing: 12) {
                ZStack {
                  Circle().fill(Color.kxGreen.opacity(0.12))
                  Image(systemName: "person.fill")
                    .foregroundStyle(Color.kxGreen)
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 4) {
                  Text(customer.displayName).font(.headline)
                  Text(customer.address)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                  Text("Пакеты: \(customer.bags) · чаевые \(KXFormat.money(customer.tipValue))")
                    .font(.caption)
                    .foregroundStyle(Color.kxGreen)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
              }
            }
          }
          .buttonStyle(.plain)
        }
      }
      .padding(18)
    }
    .scrollDismissesKeyboard(.interactively)
    .kxDismissKeyboardOnTap()
    .navigationTitle("Клиенты")
    .navigationBarTitleDisplayMode(.inline)
    .kxPageBackground()
    .sheet(isPresented: $showAdd) {
      CustomerEditorSheet(customer: nil, preferredRouteID: nil)
    }
    .sheet(item: $selectedCustomer) { customer in
      CustomerEditorSheet(customer: customer, preferredRouteID: customer.routeID)
    }
  }
}

struct CustomerEditorSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var context

  @Query(sort: \Route.date, order: .reverse) private var routes: [Route]

  let customer: Customer?
  let preferredRouteID: UUID?

  @State private var firstName = ""
  @State private var lastName = ""
  @State private var address = ""
  @State private var bags = 0
  @State private var tips = ""
  @State private var selectedRouteID: UUID?
  @State private var suggestions: [RuianSuggestion] = []
  @State private var selectedMagicKey: String?
  @State private var addressVerified = false
  @State private var searching = false
  @State private var saving = false
  @State private var errorMessage = ""
  @State private var confirmDelete = false

  private var availableRoutes: [Route] {
    routes.filter { $0.deletedAt == nil }.prefix(30).map { $0 }
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 15) {
          KXHeader(
            title: customer == nil ? "Новый клиент" : "Изменить клиента",
            subtitle: "Имя, адрес, пакеты и чаевые"
          )
          KXCard {
            VStack(spacing: 12) {
              KXInput(title: "Имя", text: $firstName)
              KXInput(title: "Фамилия", text: $lastName)
              KXInput(title: "Адрес", text: $address)

              if searching {
                HStack {
                  ProgressView()
                  Text("Поиск в RÚIAN…")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
              }
              ForEach(suggestions) { suggestion in
                Button {
                  address = suggestion.text
                  selectedMagicKey = suggestion.magicKey
                  addressVerified = true
                  suggestions = []
                } label: {
                  HStack {
                    Image(systemName: "mappin.and.ellipse")
                      .foregroundStyle(Color.kxGreen)
                    Text(suggestion.text)
                      .multilineTextAlignment(.leading)
                      .foregroundStyle(.white)
                    Spacer()
                  }
                  .padding(11)
                  .background(Color.kxSurface2, in: RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(.plain)
              }

              if addressVerified {
                Label("Адрес выбран из RÚIAN", systemImage: "checkmark.seal.fill")
                  .font(.caption)
                  .foregroundStyle(Color.kxGreen)
                  .frame(maxWidth: .infinity, alignment: .leading)
              }

              Stepper("Пакеты: \(bags)", value: $bags, in: 0...99)
              KXInput(title: "Чаевые Kč", text: $tips, keyboard: .decimalPad)

              if !availableRoutes.isEmpty {
                HStack {
                  Text("Трасса")
                  Spacer()
                  Picker("Трасса", selection: $selectedRouteID) {
                    Text("Без трассы").tag(Optional<UUID>.none)
                    ForEach(availableRoutes) { route in
                      Text("#\(route.sequence) · \(route.type.rawValue)")
                        .tag(Optional(route.id))
                    }
                  }
                }
              }
            }
          }

          KXErrorText(text: errorMessage)
          KXPrimaryButton(
            title: saving ? "Проверяю адрес…" : "Сохранить",
            icon: "checkmark",
            disabled: saving
          ) {
            Task { await save() }
          }
          if customer != nil {
            KXSecondaryButton(title: "Удалить клиента", icon: "trash", destructive: true) {
              confirmDelete = true
            }
          }
          KXSecondaryButton(title: "Отмена") { dismiss() }
        }
        .padding(18)
      }
      .scrollDismissesKeyboard(.interactively)
      .kxDismissKeyboardOnTap()
      .kxPageBackground()
      .navigationBarHidden(true)
      .toolbar { KeyboardDoneToolbar() }
      .onAppear {
        firstName = customer?.firstName ?? ""
        lastName = customer?.lastName ?? ""
        address = customer?.address ?? ""
        bags = customer?.bags ?? 0
        tips = customer.map { String(Double($0.tipValue) / 100) } ?? ""
        selectedRouteID = customer?.routeID ?? preferredRouteID
        addressVerified = customer?.addressVerified ?? false
      }
      .task(id: address) {
        guard !addressVerified, address.count >= 3 else { return }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        searching = true
        suggestions = (try? await RuianAddressService.shared.suggest(address)) ?? []
        searching = false
      }
      .alert("Удалить клиента?", isPresented: $confirmDelete) {
        Button("Удалить", role: .destructive) {
          guard let customer else { return }
          customer.deletedAt = Date.now
          audit(
            context, action: "delete", entityType: "customer", entityID: customer.id.uuidString,
            details: customer.displayName)
          try? context.save()
          dismiss()
        }
        Button("Отмена", role: .cancel) {}
      }
    }
  }

  private func save() async {
    errorMessage = ""
    let first = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
    let enteredAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !first.isEmpty else {
      errorMessage = "Введите имя клиента."
      return
    }
    guard !enteredAddress.isEmpty else {
      errorMessage = "Введите адрес клиента."
      return
    }

    saving = true
    defer { saving = false }
    let officialAddress: String
    do {
      guard
        let result = try await RuianAddressService.shared.validate(
          enteredAddress, magicKey: selectedMagicKey)
      else {
        errorMessage = "RÚIAN не подтвердил этот адрес. Выберите подходящий вариант из подсказок."
        return
      }
      officialAddress = result
    } catch {
      errorMessage = "Проверка RÚIAN недоступна: \(error.localizedDescription)"
      return
    }

    let tipHellers = Int64((Double(tips.replacingOccurrences(of: ",", with: ".")) ?? 0) * 100)
    let route = availableRoutes.first { $0.id == selectedRouteID }

    if let customer {
      customer.firstName = first
      customer.lastName = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
      customer.address = officialAddress
      customer.normalizedAddress = RuianAddressService.normalize(officialAddress)
      customer.addressVerified = true
      customer.bags = bags
      customer.tipsHellers = tipHellers
      customer.routeID = route?.id
      if let route {
        customer.routeSequence = route.sequence
        customer.routeType = route.type
        customer.date = route.date
      }
      customer.sourceRaw = DataSource.correction.rawValue
      audit(
        context, action: "edit", entityType: "customer", entityID: customer.id.uuidString,
        details: customer.displayName)
    } else {
      let newCustomer = Customer(
        routeID: route?.id,
        date: route?.date ?? Date.now,
        routeSequence: route?.sequence ?? 0,
        routeType: route?.type ?? .ot,
        position: 0,
        photoOrder: 0,
        firstName: first,
        lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines),
        address: officialAddress,
        normalizedAddress: RuianAddressService.normalize(officialAddress),
        addressVerified: true,
        bags: bags,
        tipsHellers: tipHellers,
        source: .manual
      )
      context.insert(newCustomer)
      audit(
        context, action: "create", entityType: "customer", entityID: newCustomer.id.uuidString,
        details: newCustomer.displayName)
    }

    do {
      try context.save()
      dismiss()
    } catch {
      errorMessage = "Не удалось сохранить клиента: \(error.localizedDescription)"
    }
  }
}

// MARK: Shifts

struct ShiftsView: View {
  @Query(sort: \Shift.date, order: .reverse) private var shifts: [Shift]
  @Query(sort: \Route.date, order: .reverse) private var routes: [Route]

  @State private var selectedShift: Shift?

  var body: some View {
    ScrollView {
      VStack(spacing: 12) {
        KXHeader(
          title: "Смены",
          subtitle: "Все смены и входящие в них трассы"
        )

        if shifts.filter({ $0.deletedAt == nil }).isEmpty {
          KXCard { Text("Смен пока нет.").foregroundStyle(.secondary) }
        }

        ForEach(shifts.filter { $0.deletedAt == nil }) { shift in
          let shiftRoutes =
            routes
            .filter { $0.deletedAt == nil && $0.shiftID == shift.id }
            .sorted { $0.sequence < $1.sequence }
          Button {
            selectedShift = shift
          } label: {
            KXCard {
              VStack(alignment: .leading, spacing: 7) {
                HStack {
                  Text(KXFormat.date(shift.date)).font(.headline)
                  Spacer()
                  Text(shift.status.displayName)
                    .font(.caption.bold())
                    .foregroundStyle(shift.status == .active ? Color.kxGreen : .secondary)
                }
                Text(
                  "\(shift.warehouse.rawValue) · план \(shift.plannedRings)K · факт \(shiftRoutes.reduce(0) { $0 + $1.type.rings })K"
                )
                .foregroundStyle(.secondary)
                if let started = shift.startedAt {
                  Text(
                    "\(KXFormat.time(started)) — \(shift.endedAt.map(KXFormat.time) ?? "сейчас") · \(KXFormat.duration(shift.durationMinutes))"
                  )
                  .font(.caption)
                  .foregroundStyle(.secondary)
                }
                if !shiftRoutes.isEmpty {
                  Text(
                    "Трассы: "
                      + shiftRoutes.map { "#\($0.sequence) \($0.type.rawValue)" }.joined(
                        separator: ", ")
                  )
                  .font(.caption)
                  .foregroundStyle(Color.kxGreen)
                  .lineLimit(2)
                }
                if !shift.closeReason.isEmpty {
                  Text("Причина: \(shift.closeReason)")
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
              }
            }
          }
          .buttonStyle(.plain)
        }
      }
      .padding(18)
    }
    .navigationTitle("Смены")
    .navigationBarTitleDisplayMode(.inline)
    .kxPageBackground()
    .sheet(item: $selectedShift) { shift in
      ShiftDetailSheet(shift: shift)
    }
  }
}

struct ShiftDetailSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var context
  @EnvironmentObject private var developerAccess: DeveloperAccess

  @Query(sort: \Route.sequence) private var allRoutes: [Route]
  @Query(sort: \Customer.position) private var customers: [Customer]

  let shift: Shift

  @State private var date = Date.now
  @State private var warehouse: Warehouse = .liboc
  @State private var plannedRings = 4
  @State private var note = ""
  @State private var selectedRoute: Route?
  @State private var errorMessage = ""
  @State private var confirmDelete = false

  private var routes: [Route] {
    allRoutes.filter { $0.deletedAt == nil && $0.shiftID == shift.id }
  }

  private var mayEdit: Bool {
    shift.status == .active || shift.status == .planned || developerAccess.isUnlocked
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 16) {
          KXHeader(title: "Смена", subtitle: KXFormat.date(shift.date))

          KXCard {
            VStack(spacing: 14) {
              DatePicker("Дата", selection: $date, displayedComponents: .date)
                .disabled(!mayEdit)
              HStack {
                Text("Склад")
                Spacer()
                Picker("Склад", selection: $warehouse) {
                  ForEach(Warehouse.allCases) { Text($0.rawValue).tag($0) }
                }
                .disabled(!mayEdit)
              }
              Stepper("План: \(plannedRings)K", value: $plannedRings, in: 1...20)
                .disabled(!mayEdit)
              KXInput(title: "Комментарий", text: $note, disabled: !mayEdit)
              LabeledContent("Статус", value: shift.status.displayName)
              if let start = shift.startedAt {
                LabeledContent("Начало", value: KXFormat.time(start))
              }
              if let end = shift.endedAt {
                LabeledContent("Окончание", value: KXFormat.time(end))
              }
              if !shift.closeReason.isEmpty {
                LabeledContent("Причина закрытия", value: shift.closeReason)
              }
              if let queue = shift.queueOdometer {
                LabeledContent("Одометр при входе", value: KXFormat.number(queue))
              }
              if let closing = shift.closingOdometer {
                LabeledContent("Одометр при закрытии", value: KXFormat.number(closing))
              }
            }
          }

          VStack(alignment: .leading, spacing: 10) {
            Text("Трассы смены").font(.title2.bold())
            if routes.isEmpty {
              KXCard { Text("В этой смене нет трасс.").foregroundStyle(.secondary) }
            }
            ForEach(routes) { route in
              Button {
                selectedRoute = route
              } label: {
                RouteSummaryCard(
                  route: route,
                  customers: customers.filter { $0.routeID == route.id && $0.deletedAt == nil }
                )
              }
              .buttonStyle(.plain)
            }
          }

          if mayEdit {
            KXErrorText(text: errorMessage)
            KXPrimaryButton(title: "Сохранить смену", icon: "checkmark") { save() }
          } else {
            KXCard {
              Label(
                "Завершённую смену можно изменять после разблокировки Developer Mode.",
                systemImage: "lock.fill"
              )
              .foregroundStyle(.secondary)
            }
          }

          if developerAccess.isUnlocked || shift.status != .complete {
            KXSecondaryButton(title: "Удалить смену", icon: "trash", destructive: true) {
              confirmDelete = true
            }
          }
        }
        .padding(18)
      }
      .scrollDismissesKeyboard(.interactively)
      .kxDismissKeyboardOnTap()
      .kxPageBackground()
      .toolbar {
        KeyboardDoneToolbar()
        ToolbarItem(placement: .cancellationAction) {
          Button("Закрыть") { dismiss() }
        }
      }
      .onAppear {
        date = shift.date
        warehouse = shift.warehouse
        plannedRings = shift.plannedRings
        note = shift.note
      }
      .sheet(item: $selectedRoute) { route in
        RouteDetailSheet(route: route)
      }
      .alert("Удалить смену?", isPresented: $confirmDelete) {
        Button("Удалить", role: .destructive) {
          shift.deletedAt = Date.now
          audit(
            context, action: "delete", entityType: "shift", entityID: shift.id.uuidString,
            details: KXFormat.date(shift.date))
          try? context.save()
          dismiss()
        }
        Button("Отмена", role: .cancel) {}
      }
    }
  }

  private func save() {
    shift.date = date.startOfDay
    shift.warehouse = warehouse
    shift.plannedRings = plannedRings
    shift.note = note
    audit(
      context, action: "edit", entityType: "shift", entityID: shift.id.uuidString,
      details: "План \(plannedRings)K")
    do {
      try context.save()
      dismiss()
    } catch {
      errorMessage = "Не удалось сохранить смену: \(error.localizedDescription)"
    }
  }
}

// MARK: Finance

enum FinanceFilter: Equatable {
  case positive
  case penalty
}

struct FinanceListView: View {
  @Environment(\.modelContext) private var context
  @Query(sort: \FinancialEntry.date, order: .reverse) private var entries: [FinancialEntry]

  let filter: FinanceFilter

  @State private var showManual = false
  @State private var showOCR = false
  @State private var selectedEntry: FinancialEntry?

  private var visibleEntries: [FinancialEntry] {
    entries.filter {
      $0.deletedAt == nil
        && (filter == .positive ? $0.kind.positive : $0.kind == .penalty)
    }
  }

  private var title: String {
    filter == .positive ? "Бонусы и компенсации" : "Штрафы"
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 12) {
        KXHeader(title: title, subtitle: "Добавление вручную, камерой или через OCR")

        HStack(spacing: 12) {
          KXSecondaryButton(title: "Вручную", icon: "square.and.pencil") {
            showManual = true
          }
          KXPrimaryButton(title: "По фото / OCR", icon: "camera.fill") {
            showOCR = true
          }
        }

        if visibleEntries.isEmpty {
          KXCard { Text("Операций пока нет.").foregroundStyle(.secondary) }
        }

        ForEach(visibleEntries) { entry in
          Button {
            selectedEntry = entry
          } label: {
            KXCard {
              HStack {
                VStack(alignment: .leading, spacing: 4) {
                  Text(entry.kind.rawValue).font(.headline)
                  Text("\(KXFormat.date(entry.date)) · \(entry.source)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                  if !entry.note.isEmpty {
                    Text(entry.note).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                  }
                }
                Spacer()
                Text((entry.kind.positive ? "+ " : "− ") + KXFormat.money(entry.amountHellers))
                  .font(.headline)
                  .foregroundStyle(entry.kind.positive ? Color.kxGreen : .red)
              }
            }
          }
          .buttonStyle(.plain)
        }
      }
      .padding(18)
    }
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
    .kxPageBackground()
    .sheet(isPresented: $showManual) {
      FinancialEditorSheet(entry: nil, defaultKind: filter == .positive ? .bonus : .penalty)
    }
    .sheet(isPresented: $showOCR) {
      FinanceOCRImportSheet(defaultKind: filter == .positive ? .bonus : .penalty)
    }
    .sheet(item: $selectedEntry) { entry in
      FinancialEditorSheet(entry: entry, defaultKind: entry.kind)
    }
  }
}

struct FinancialEditorSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var context

  let entry: FinancialEntry?
  let defaultKind: FinancialKind

  @State private var kind: FinancialKind = .bonus
  @State private var date = Date.now
  @State private var amount = ""
  @State private var note = ""
  @State private var errorMessage = ""
  @State private var confirmDelete = false

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 15) {
          KXHeader(title: entry == nil ? "Новая операция" : "Изменить операцию")
          KXCard {
            VStack(spacing: 14) {
              Picker("Тип", selection: $kind) {
                ForEach(FinancialKind.allCases) { Text($0.rawValue).tag($0) }
              }
              .pickerStyle(.segmented)
              DatePicker("Дата", selection: $date, displayedComponents: .date)
              KXInput(title: "Сумма Kč", text: $amount, keyboard: .decimalPad)
              KXInput(title: "Комментарий", text: $note)
            }
          }
          KXErrorText(text: errorMessage)
          KXPrimaryButton(title: "Сохранить", icon: "checkmark") { save() }
          if entry != nil {
            KXSecondaryButton(title: "Удалить", icon: "trash", destructive: true) {
              confirmDelete = true
            }
          }
          KXSecondaryButton(title: "Отмена") { dismiss() }
        }
        .padding(18)
      }
      .scrollDismissesKeyboard(.interactively)
      .kxDismissKeyboardOnTap()
      .kxPageBackground()
      .navigationBarHidden(true)
      .toolbar { KeyboardDoneToolbar() }
      .onAppear {
        kind = entry?.kind ?? defaultKind
        date = entry?.date ?? Date.now
        amount = entry.map { String(Double($0.amountHellers) / 100) } ?? ""
        note = entry?.note ?? ""
      }
      .alert("Удалить операцию?", isPresented: $confirmDelete) {
        Button("Удалить", role: .destructive) {
          guard let entry else { return }
          entry.deletedAt = Date.now
          audit(
            context, action: "delete", entityType: "finance", entityID: entry.id.uuidString,
            details: entry.kind.rawValue)
          try? context.save()
          dismiss()
        }
        Button("Отмена", role: .cancel) {}
      }
    }
  }

  private func save() {
    guard let value = Double(amount.replacingOccurrences(of: ",", with: ".")), value > 0 else {
      errorMessage = "Введите корректную сумму."
      return
    }
    if let entry {
      entry.kind = kind
      entry.date = date.startOfDay
      entry.amountHellers = Int64(value * 100)
      entry.note = note
      entry.source = DataSource.correction.rawValue
      audit(
        context, action: "edit", entityType: "finance", entityID: entry.id.uuidString,
        details: "\(kind.rawValue) \(value) Kč")
    } else {
      let newEntry = FinancialEntry(
        date: date.startOfDay,
        kind: kind,
        amountHellers: Int64(value * 100),
        note: note,
        source: DataSource.manual.rawValue
      )
      context.insert(newEntry)
      audit(
        context, action: "create", entityType: "finance", entityID: newEntry.id.uuidString,
        details: "\(kind.rawValue) \(value) Kč")
    }
    do {
      try context.save()
      dismiss()
    } catch {
      errorMessage = "Не удалось сохранить операцию: \(error.localizedDescription)"
    }
  }
}

struct FinanceOCRImportSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var context

  let defaultKind: FinancialKind

  @State private var kind: FinancialKind = .bonus
  @State private var date = Date.now
  @State private var amount = ""
  @State private var note = ""
  @State private var photoItem: PhotosPickerItem?
  @State private var showCamera = false
  @State private var rawText = ""
  @State private var busy = false
  @State private var errorMessage = ""

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 15) {
          KXHeader(
            title: "Добавить по фото / OCR", subtitle: "Распознанные данные сначала проверяются")
          HStack(spacing: 12) {
            KXSecondaryButton(title: "Камера", icon: "camera.fill") { showCamera = true }
            PhotosPicker(selection: $photoItem, matching: .images) {
              Label("Галерея", systemImage: "photo.fill")
                .fontWeight(.semibold)
                .foregroundStyle(Color.kxBackground)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.kxGreen, in: RoundedRectangle(cornerRadius: 15))
            }
          }
          if busy { ProgressView("Распознаю…") }
          KXCard {
            VStack(spacing: 14) {
              Picker("Тип", selection: $kind) {
                ForEach(FinancialKind.allCases) { Text($0.rawValue).tag($0) }
              }
              .pickerStyle(.segmented)
              DatePicker("Дата", selection: $date, displayedComponents: .date)
              KXInput(title: "Сумма Kč", text: $amount, keyboard: .decimalPad)
              KXInput(title: "Комментарий", text: $note)
            }
          }
          if !rawText.isEmpty {
            KXCard {
              Text(rawText).font(.caption).textSelection(.enabled)
            }
          }
          KXErrorText(text: errorMessage)
          KXPrimaryButton(
            title: "Сохранить", icon: "checkmark",
            disabled: (Double(amount.replacingOccurrences(of: ",", with: ".")) ?? 0) <= 0
          ) {
            save()
          }
          KXSecondaryButton(title: "Отмена") { dismiss() }
        }
        .padding(18)
      }
      .scrollDismissesKeyboard(.interactively)
      .kxDismissKeyboardOnTap()
      .kxPageBackground()
      .navigationBarHidden(true)
      .toolbar { KeyboardDoneToolbar() }
      .onAppear { kind = defaultKind }
      .onChange(of: photoItem) { _, item in
        guard let item else { return }
        Task {
          if let data = try? await item.loadTransferable(type: Data.self),
            let image = UIImage(data: data)
          {
            await process(image)
          }
          photoItem = nil
        }
      }
      .sheet(isPresented: $showCamera) {
        CameraPicker { image in Task { await process(image) } }
      }
    }
  }

  private func process(_ image: UIImage) async {
    busy = true
    errorMessage = ""
    defer { busy = false }
    do {
      let document = try await OCRService.recognize(image)
      rawText = document.text
      let parsed = FinanceOCRParser.parse(document.text)
      if let value = parsed.amountHellers { amount = String(Double(value) / 100) }
      if let parsedDate = parsed.date { date = parsedDate }
      note = parsed.description
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func save() {
    guard let value = Double(amount.replacingOccurrences(of: ",", with: ".")), value > 0 else {
      errorMessage = "Введите корректную сумму."
      return
    }
    let entry = FinancialEntry(
      date: date.startOfDay,
      kind: kind,
      amountHellers: Int64(value * 100),
      note: note,
      source: DataSource.ocr.rawValue
    )
    context.insert(entry)
    audit(
      context, action: "import", entityType: "finance", entityID: entry.id.uuidString,
      details: "\(kind.rawValue) \(value) Kč")
    do {
      try context.save()
      dismiss()
    } catch {
      errorMessage = "Не удалось сохранить: \(error.localizedDescription)"
    }
  }
}

// MARK: Auto expenses

struct AutoExpensesView: View {
  @Query(sort: \FuelEntry.date, order: .reverse) private var entries: [FuelEntry]

  @State private var showAdd = false
  @State private var selectedEntry: FuelEntry?

  private var visible: [FuelEntry] { entries.filter { $0.deletedAt == nil } }
  private var total: Int64 { visible.reduce(Int64(0)) { $0 + $1.amountHellers } }

  var body: some View {
    ScrollView {
      VStack(spacing: 12) {
        KXHeader(
          title: "Дизель и авторасходы",
          subtitle: "Топливо и другие расходы автомобиля"
        )
        KXCard {
          VStack(alignment: .leading, spacing: 7) {
            Text("Всего расходов").foregroundStyle(.secondary)
            Text(KXFormat.money(total)).font(.system(size: 34, weight: .bold, design: .rounded))
            let liters = visible.filter { $0.kind == .fuel }.reduce(0.0) { $0 + $1.liters }
            let km = visible.reduce(0.0) { $0 + $1.distanceKm }
            Text("Топливо: \(KXFormat.number(liters)) л · учтено \(KXFormat.number(km)) км")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        KXPrimaryButton(title: "Добавить расход", icon: "plus.circle.fill") {
          showAdd = true
        }

        if visible.isEmpty {
          KXCard { Text("Расходов пока нет.").foregroundStyle(.secondary) }
        }

        ForEach(visible) { entry in
          Button {
            selectedEntry = entry
          } label: {
            KXCard {
              HStack {
                VStack(alignment: .leading, spacing: 4) {
                  Text(entry.kind.rawValue).font(.headline)
                  Text(KXFormat.date(entry.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                  if entry.kind == .fuel {
                    Text(
                      "\(KXFormat.number(entry.liters)) л · \(KXFormat.number(entry.distanceKm)) км"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                  }
                  if !entry.note.isEmpty {
                    Text(entry.note).font(.caption).foregroundStyle(.secondary)
                  }
                }
                Spacer()
                Text(KXFormat.money(entry.amountHellers)).font(.headline)
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
              }
            }
          }
          .buttonStyle(.plain)
        }
      }
      .padding(18)
    }
    .navigationTitle("Авторасходы")
    .navigationBarTitleDisplayMode(.inline)
    .kxPageBackground()
    .sheet(isPresented: $showAdd) {
      AutoExpenseEditorSheet(entry: nil)
    }
    .sheet(item: $selectedEntry) { entry in
      AutoExpenseEditorSheet(entry: entry)
    }
  }
}

struct AutoExpenseEditorSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var context

  let entry: FuelEntry?

  @State private var kind: AutoExpenseKind = .fuel
  @State private var date = Date.now
  @State private var amount = ""
  @State private var liters = ""
  @State private var distanceKm = ""
  @State private var odometer = ""
  @State private var note = ""
  @State private var errorMessage = ""
  @State private var confirmDelete = false

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 15) {
          KXHeader(
            title: entry == nil ? "Новый авторасход" : "Изменить авторасход",
            subtitle: "Топливо отделено от парковки, сервиса и других расходов"
          )
          KXCard {
            VStack(spacing: 14) {
              HStack {
                Text("Тип")
                Spacer()
                Picker("Тип", selection: $kind) {
                  ForEach(AutoExpenseKind.allCases) { Text($0.rawValue).tag($0) }
                }
              }
              DatePicker("Дата", selection: $date, displayedComponents: .date)
              KXInput(title: "Сумма Kč", text: $amount, keyboard: .decimalPad)
              if kind == .fuel {
                KXInput(title: "Литры", text: $liters, keyboard: .decimalPad)
              }
              KXInput(title: "Километраж поездки", text: $distanceKm, keyboard: .decimalPad)
              KXInput(
                title: "Показание одометра (необязательно)", text: $odometer, keyboard: .decimalPad)
              KXInput(title: "Комментарий", text: $note)
            }
          }
          KXErrorText(text: errorMessage)
          KXPrimaryButton(title: "Сохранить", icon: "checkmark") { save() }
          if entry != nil {
            KXSecondaryButton(title: "Удалить", icon: "trash", destructive: true) {
              confirmDelete = true
            }
          }
          KXSecondaryButton(title: "Отмена") { dismiss() }
        }
        .padding(18)
      }
      .scrollDismissesKeyboard(.interactively)
      .kxDismissKeyboardOnTap()
      .kxPageBackground()
      .navigationBarHidden(true)
      .toolbar { KeyboardDoneToolbar() }
      .onAppear {
        kind = entry?.kind ?? .fuel
        date = entry?.date ?? Date.now
        amount = entry.map { String(Double($0.amountHellers) / 100) } ?? ""
        liters = entry.map { String($0.liters) } ?? ""
        distanceKm = entry.map { String($0.distanceKm) } ?? ""
        odometer = entry?.odometer.map { String($0) } ?? ""
        note = entry?.note ?? ""
      }
      .alert("Удалить расход?", isPresented: $confirmDelete) {
        Button("Удалить", role: .destructive) {
          guard let entry else { return }
          entry.deletedAt = Date.now
          audit(
            context, action: "delete", entityType: "autoExpense", entityID: entry.id.uuidString,
            details: entry.kind.rawValue)
          try? context.save()
          dismiss()
        }
        Button("Отмена", role: .cancel) {}
      }
    }
  }

  private func save() {
    errorMessage = ""
    guard let amountValue = Double(amount.replacingOccurrences(of: ",", with: ".")), amountValue > 0
    else {
      errorMessage = "Введите корректную сумму."
      return
    }
    let litersValue = Double(liters.replacingOccurrences(of: ",", with: ".")) ?? 0
    if kind == .fuel && litersValue <= 0 {
      errorMessage = "Для топлива укажите количество литров."
      return
    }
    let distanceValue = Double(distanceKm.replacingOccurrences(of: ",", with: ".")) ?? 0
    let odometerValue = Double(odometer.replacingOccurrences(of: ",", with: "."))

    if let entry {
      entry.kind = kind
      entry.date = date.startOfDay
      entry.amountHellers = Int64(amountValue * 100)
      entry.liters = litersValue
      entry.distanceKm = distanceValue
      entry.odometer = odometerValue
      entry.note = note
      audit(
        context, action: "edit", entityType: "autoExpense", entityID: entry.id.uuidString,
        details: kind.rawValue)
    } else {
      let newEntry = FuelEntry(
        date: date.startOfDay,
        amountHellers: Int64(amountValue * 100),
        liters: litersValue,
        distanceKm: distanceValue,
        odometer: odometerValue,
        kind: kind,
        note: note
      )
      context.insert(newEntry)
      audit(
        context, action: "create", entityType: "autoExpense", entityID: newEntry.id.uuidString,
        details: kind.rawValue)
    }
    do {
      try context.save()
      dismiss()
    } catch {
      errorMessage = "Не удалось сохранить расход: \(error.localizedDescription)"
    }
  }
}

// MARK: Advances

struct AdvancesView: View {
  @Query(sort: \AdvanceEntry.date, order: .reverse) private var entries: [AdvanceEntry]
  @State private var showAdd = false
  @State private var selectedEntry: AdvanceEntry?

  private var visible: [AdvanceEntry] { entries.filter { $0.deletedAt == nil } }

  var body: some View {
    ScrollView {
      VStack(spacing: 12) {
        KXHeader(title: "Авансы", subtitle: "Полученные авансы и возвраты")
        KXCard {
          LabeledContent(
            "Всего авансов",
            value: KXFormat.money(visible.reduce(Int64(0)) { $0 + $1.amountHellers })
          )
          .font(.headline)
        }
        KXPrimaryButton(title: "Добавить аванс", icon: "plus.circle.fill") { showAdd = true }
        ForEach(visible) { entry in
          Button {
            selectedEntry = entry
          } label: {
            KXCard {
              HStack {
                VStack(alignment: .leading, spacing: 4) {
                  Text(KXFormat.date(entry.date)).font(.headline)
                  Text(entry.note).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(KXFormat.money(entry.amountHellers)).font(.headline)
              }
            }
          }
          .buttonStyle(.plain)
        }
      }
      .padding(18)
    }
    .navigationTitle("Авансы")
    .navigationBarTitleDisplayMode(.inline)
    .kxPageBackground()
    .sheet(isPresented: $showAdd) { AdvanceEditorSheet(entry: nil) }
    .sheet(item: $selectedEntry) { AdvanceEditorSheet(entry: $0) }
  }
}

struct AdvanceEditorSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var context
  let entry: AdvanceEntry?

  @State private var date = Date.now
  @State private var amount = ""
  @State private var note = ""
  @State private var errorMessage = ""
  @State private var confirmDelete = false

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 15) {
          KXHeader(title: entry == nil ? "Добавить аванс" : "Изменить аванс")
          KXCard {
            VStack(spacing: 14) {
              DatePicker("Дата", selection: $date, displayedComponents: .date)
              KXInput(title: "Сумма Kč", text: $amount, keyboard: .decimalPad)
              KXInput(title: "Комментарий", text: $note)
            }
          }
          KXErrorText(text: errorMessage)
          KXPrimaryButton(title: "Сохранить", icon: "checkmark") { save() }
          if entry != nil {
            KXSecondaryButton(title: "Удалить", icon: "trash", destructive: true) {
              confirmDelete = true
            }
          }
          KXSecondaryButton(title: "Отмена") { dismiss() }
        }
        .padding(18)
      }
      .scrollDismissesKeyboard(.interactively)
      .kxDismissKeyboardOnTap()
      .kxPageBackground()
      .navigationBarHidden(true)
      .toolbar { KeyboardDoneToolbar() }
      .onAppear {
        date = entry?.date ?? Date.now
        amount = entry.map { String(Double($0.amountHellers) / 100) } ?? ""
        note = entry?.note ?? ""
      }
      .alert("Удалить аванс?", isPresented: $confirmDelete) {
        Button("Удалить", role: .destructive) {
          guard let entry else { return }
          entry.deletedAt = Date.now
          try? context.save()
          dismiss()
        }
        Button("Отмена", role: .cancel) {}
      }
    }
  }

  private func save() {
    guard let value = Double(amount.replacingOccurrences(of: ",", with: ".")), value > 0 else {
      errorMessage = "Введите корректную сумму."
      return
    }
    if let entry {
      entry.date = date.startOfDay
      entry.amountHellers = Int64(value * 100)
      entry.note = note
    } else {
      context.insert(
        AdvanceEntry(date: date.startOfDay, amountHellers: Int64(value * 100), note: note))
    }
    do {
      try context.save()
      dismiss()
    } catch {
      errorMessage = "Не удалось сохранить аванс: \(error.localizedDescription)"
    }
  }
}

// MARK: Salary

struct SalaryView: View {
  @Query(sort: \SalaryPayment.receivedDate, order: .reverse) private var payments: [SalaryPayment]
  @Query(sort: \Route.date, order: .reverse) private var routes: [Route]
  @Query(sort: \Customer.date, order: .reverse) private var customers: [Customer]
  @Query(sort: \FinancialEntry.date, order: .reverse) private var finances: [FinancialEntry]
  @Query(sort: \FuelEntry.date, order: .reverse) private var expenses: [FuelEntry]
  @Query(sort: \AdvanceEntry.date, order: .reverse) private var advances: [AdvanceEntry]

  @State private var showAdd = false
  @State private var selectedPayment: SalaryPayment?

  private var monthRoutes: [Route] {
    routes.filter { $0.deletedAt == nil && $0.date.monthKey == Date.now.monthKey }
  }
  private var expected: Int64 {
    let routeTotal = monthRoutes.reduce(Int64(0)) {
      $0 + EarningsCalculator.route($1, customers: customers).gross
    }
    let extra = finances.filter { $0.deletedAt == nil && $0.date.monthKey == Date.now.monthKey }
      .reduce(Int64(0)) { $0 + ($1.kind.positive ? $1.amountHellers : -$1.amountHellers) }
    let expense = expenses.filter { $0.deletedAt == nil && $0.date.monthKey == Date.now.monthKey }
      .reduce(Int64(0)) { $0 + $1.amountHellers }
    let advance = advances.filter { $0.deletedAt == nil && $0.date.monthKey == Date.now.monthKey }
      .reduce(Int64(0)) { $0 + $1.amountHellers }
    return routeTotal + extra - expense - advance
  }
  private var paid: Int64 {
    payments.filter { $0.deletedAt == nil && $0.receivedDate.monthKey == Date.now.monthKey }
      .reduce(Int64(0)) { $0 + $1.amountHellers }
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 12) {
        KXHeader(title: "Зарплата", subtitle: "Выплаты и сверка с расчётом KurierX")
        KXCard {
          VStack(alignment: .leading, spacing: 9) {
            LabeledContent("Расчёт приложения", value: KXFormat.money(expected))
            LabeledContent("Выплачено", value: KXFormat.money(paid))
            Divider()
            LabeledContent("Разница", value: KXFormat.money(expected - paid))
              .font(.headline)
          }
        }
        KXPrimaryButton(title: "Добавить выплату", icon: "plus.circle.fill") { showAdd = true }
        ForEach(payments.filter { $0.deletedAt == nil }) { payment in
          Button {
            selectedPayment = payment
          } label: {
            KXCard {
              HStack {
                VStack(alignment: .leading, spacing: 4) {
                  Text(KXFormat.date(payment.receivedDate)).font(.headline)
                  Text(
                    "\(KXFormat.shortDate(payment.periodStart)) — \(KXFormat.shortDate(payment.periodEnd))"
                  )
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  Text(payment.note).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(KXFormat.money(payment.amountHellers)).font(.headline)
              }
            }
          }
          .buttonStyle(.plain)
        }
      }
      .padding(18)
    }
    .navigationTitle("Зарплата")
    .navigationBarTitleDisplayMode(.inline)
    .kxPageBackground()
    .sheet(isPresented: $showAdd) { SalaryPaymentEditorSheet(payment: nil) }
    .sheet(item: $selectedPayment) { SalaryPaymentEditorSheet(payment: $0) }
  }
}

struct SalaryPaymentEditorSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var context
  let payment: SalaryPayment?

  @State private var receivedDate = Date.now
  @State private var periodStart =
    Calendar.current.date(byAdding: .month, value: -1, to: Date.now) ?? Date.now
  @State private var periodEnd = Date.now
  @State private var amount = ""
  @State private var note = ""
  @State private var errorMessage = ""
  @State private var confirmDelete = false

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 15) {
          KXHeader(title: payment == nil ? "Новая выплата" : "Изменить выплату")
          KXCard {
            VStack(spacing: 14) {
              DatePicker("Дата получения", selection: $receivedDate, displayedComponents: .date)
              DatePicker("Период от", selection: $periodStart, displayedComponents: .date)
              DatePicker("Период до", selection: $periodEnd, displayedComponents: .date)
              KXInput(title: "Сумма Kč", text: $amount, keyboard: .decimalPad)
              KXInput(title: "Комментарий", text: $note)
            }
          }
          KXErrorText(text: errorMessage)
          KXPrimaryButton(title: "Сохранить", icon: "checkmark") { save() }
          if payment != nil {
            KXSecondaryButton(title: "Удалить", icon: "trash", destructive: true) {
              confirmDelete = true
            }
          }
          KXSecondaryButton(title: "Отмена") { dismiss() }
        }
        .padding(18)
      }
      .scrollDismissesKeyboard(.interactively)
      .kxDismissKeyboardOnTap()
      .kxPageBackground()
      .navigationBarHidden(true)
      .toolbar { KeyboardDoneToolbar() }
      .onAppear {
        receivedDate = payment?.receivedDate ?? Date.now
        periodStart = payment?.periodStart ?? periodStart
        periodEnd = payment?.periodEnd ?? Date.now
        amount = payment.map { String(Double($0.amountHellers) / 100) } ?? ""
        note = payment?.note ?? ""
      }
      .alert("Удалить выплату?", isPresented: $confirmDelete) {
        Button("Удалить", role: .destructive) {
          guard let payment else { return }
          payment.deletedAt = Date.now
          try? context.save()
          dismiss()
        }
        Button("Отмена", role: .cancel) {}
      }
    }
  }

  private func save() {
    guard periodEnd >= periodStart else {
      errorMessage = "Конец периода не может быть раньше начала."
      return
    }
    guard let value = Double(amount.replacingOccurrences(of: ",", with: ".")), value > 0 else {
      errorMessage = "Введите корректную сумму."
      return
    }
    if let payment {
      payment.receivedDate = receivedDate.startOfDay
      payment.periodStart = periodStart.startOfDay
      payment.periodEnd = periodEnd.startOfDay
      payment.amountHellers = Int64(value * 100)
      payment.note = note
    } else {
      context.insert(
        SalaryPayment(
          receivedDate: receivedDate.startOfDay,
          amountHellers: Int64(value * 100),
          periodStart: periodStart.startOfDay,
          periodEnd: periodEnd.startOfDay,
          note: note
        )
      )
    }
    do {
      try context.save()
      dismiss()
    } catch {
      errorMessage = "Не удалось сохранить выплату: \(error.localizedDescription)"
    }
  }
}

// MARK: Goals

struct GoalsView: View {
  @Environment(\.modelContext) private var context
  @Query(sort: \Goal.month, order: .reverse) private var goals: [Goal]

  @State private var showAdd = false
  @State private var selectedGoal: Goal?

  var body: some View {
    ScrollView {
      VStack(spacing: 12) {
        KXHeader(title: "Цели", subtitle: "План заказов и заработка")
        KXPrimaryButton(title: "Добавить цель", icon: "plus.circle.fill") { showAdd = true }

        ForEach(goals.filter { $0.deletedAt == nil }) { goal in
          Button {
            selectedGoal = goal
          } label: {
            KXCard {
              HStack {
                VStack(alignment: .leading, spacing: 5) {
                  Text(goal.month).font(.headline)
                  Text("\(goal.targetOrders) заказов")
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Text(KXFormat.money(goal.targetHellers)).font(.headline)
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
              }
            }
          }
          .buttonStyle(.plain)
        }
      }
      .padding(18)
    }
    .navigationTitle("Цели")
    .navigationBarTitleDisplayMode(.inline)
    .kxPageBackground()
    .sheet(isPresented: $showAdd) { GoalEditorSheet(goal: nil) }
    .sheet(item: $selectedGoal) { GoalEditorSheet(goal: $0) }
  }
}

struct GoalEditorSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var context
  let goal: Goal?

  @State private var monthDate = Date.now
  @State private var targetOrders = ""
  @State private var targetMoney = ""
  @State private var errorMessage = ""
  @State private var confirmDelete = false

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 15) {
          KXHeader(title: goal == nil ? "Новая цель" : "Изменить цель")
          KXCard {
            VStack(spacing: 14) {
              DatePicker("Месяц", selection: $monthDate, displayedComponents: .date)
              KXInput(title: "Цель заказов", text: $targetOrders, keyboard: .numberPad)
              KXInput(title: "Цель заработка Kč", text: $targetMoney, keyboard: .decimalPad)
            }
          }
          KXErrorText(text: errorMessage)
          KXPrimaryButton(title: "Сохранить", icon: "checkmark") { save() }
          if goal != nil {
            KXSecondaryButton(title: "Удалить цель", icon: "trash", destructive: true) {
              confirmDelete = true
            }
          }
          KXSecondaryButton(title: "Отмена") { dismiss() }
        }
        .padding(18)
      }
      .scrollDismissesKeyboard(.interactively)
      .kxDismissKeyboardOnTap()
      .kxPageBackground()
      .navigationBarHidden(true)
      .toolbar { KeyboardDoneToolbar() }
      .onAppear {
        if let goal {
          let components = goal.month.split(separator: "-").compactMap { Int($0) }
          if components.count == 2 {
            monthDate =
              Calendar.current.date(
                from: DateComponents(year: components[0], month: components[1], day: 1)) ?? Date.now
          }
          targetOrders = String(goal.targetOrders)
          targetMoney = String(Double(goal.targetHellers) / 100)
        }
      }
      .alert("Удалить цель?", isPresented: $confirmDelete) {
        Button("Удалить", role: .destructive) {
          guard let goal else { return }
          goal.deletedAt = Date.now
          try? context.save()
          dismiss()
        }
        Button("Отмена", role: .cancel) {}
      }
    }
  }

  private func save() {
    guard let orders = Int(targetOrders), orders > 0 else {
      errorMessage = "Введите цель по заказам."
      return
    }
    let money = Double(targetMoney.replacingOccurrences(of: ",", with: ".")) ?? 0
    let key = monthDate.monthKey
    if let goal {
      goal.month = key
      goal.targetOrders = orders
      goal.targetHellers = Int64(money * 100)
    } else {
      context.insert(Goal(month: key, targetOrders: orders, targetHellers: Int64(money * 100)))
    }
    do {
      try context.save()
      dismiss()
    } catch {
      errorMessage = "Не удалось сохранить цель: \(error.localizedDescription)"
    }
  }
}

// MARK: Backup

struct KurierXBackup: Codable {
  var version: Int
  var createdAt: Date
  var shifts: [BackupShift]
  var routes: [BackupRoute]
  var customers: [BackupCustomer]
  var calendar: [BackupCalendar]
  var finances: [BackupFinancial]
  var expenses: [BackupExpense]
  var advances: [BackupAdvance]
  var goals: [BackupGoal]
}

struct BackupShift: Codable {
  var date: Date
  var warehouse: String
  var status: String
  var plannedRings: Int
  var startedAt: Date?
  var endedAt: Date?
  var queueOdometer: Double?
  var closingOdometer: Double?
  var closeReason: String
  var note: String
}

struct BackupRoute: Codable {
  var originalID: UUID
  var shiftIndex: Int
  var date: Date
  var sequence: Int
  var type: String
  var warehouse: String
  var factualOrders: Int
  var distanceKm: Double?
  var externalRouteID: String?
  var note: String
}

struct BackupCustomer: Codable {
  var routeOriginalID: UUID?
  var date: Date
  var routeSequence: Int
  var routeType: String
  var position: Int
  var photoOrder: Int
  var firstName: String
  var lastName: String
  var address: String
  var normalizedAddress: String?
  var addressVerified: Bool
  var bags: Int
  var tipsHellers: Int64
  var note: String
}

struct BackupCalendar: Codable {
  var date: Date
  var warehouse: String
  var startMinutes: Int
  var plannedRings: Int
  var note: String
}

struct BackupFinancial: Codable {
  var date: Date
  var kind: String
  var amountHellers: Int64
  var note: String
  var source: String
}

struct BackupExpense: Codable {
  var date: Date
  var amountHellers: Int64
  var liters: Double
  var distanceKm: Double
  var odometer: Double?
  var kind: String
  var note: String
}

struct BackupAdvance: Codable {
  var date: Date
  var amountHellers: Int64
  var note: String
}

struct BackupGoal: Codable {
  var month: String
  var targetOrders: Int
  var targetHellers: Int64
}

struct KurierXBackupDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.json] }
  var backup: KurierXBackup

  init(backup: KurierXBackup) {
    self.backup = backup
  }

  init(configuration: ReadConfiguration) throws {
    guard let data = configuration.file.regularFileContents else {
      throw CocoaError(.fileReadCorruptFile)
    }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    backup = try decoder.decode(KurierXBackup.self, from: data)
  }

  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return FileWrapper(regularFileWithContents: try encoder.encode(backup))
  }
}

struct BackupView: View {
  @Environment(\.modelContext) private var context
  @Query private var shifts: [Shift]
  @Query private var routes: [Route]
  @Query private var customers: [Customer]
  @Query private var calendar: [CalendarPlan]
  @Query private var finances: [FinancialEntry]
  @Query private var expenses: [FuelEntry]
  @Query private var advances: [AdvanceEntry]
  @Query private var goals: [Goal]

  @State private var exportDocument: KurierXBackupDocument?
  @State private var showExporter = false
  @State private var showImporter = false
  @State private var message = ""
  @State private var errorMessage = ""

  var body: some View {
    ScrollView {
      VStack(spacing: 14) {
        KXHeader(title: "Резервные копии", subtitle: "Экспорт и восстановление локальных данных")
        KXCard {
          VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Смен", value: "\(shifts.filter { $0.deletedAt == nil }.count)")
            LabeledContent("Трасс", value: "\(routes.filter { $0.deletedAt == nil }.count)")
            LabeledContent("Клиентов", value: "\(customers.filter { $0.deletedAt == nil }.count)")
            LabeledContent(
              "Планов календаря", value: "\(calendar.filter { $0.deletedAt == nil }.count)")
          }
        }
        KXPrimaryButton(title: "Создать резервную копию", icon: "square.and.arrow.up") {
          exportDocument = KurierXBackupDocument(backup: makeBackup())
          showExporter = true
        }
        KXSecondaryButton(title: "Восстановить из файла", icon: "square.and.arrow.down") {
          showImporter = true
        }
        KXErrorText(text: errorMessage)
        if !message.isEmpty {
          Label(message, systemImage: "checkmark.circle.fill")
            .foregroundStyle(Color.kxGreen)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        KXCard {
          Text(
            "Восстановление добавляет объекты в текущую базу и не удаляет существующие данные. Перед импортом рекомендуется создать новую резервную копию."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
      }
      .padding(18)
    }
    .navigationTitle("Резервные копии")
    .navigationBarTitleDisplayMode(.inline)
    .kxPageBackground()
    .fileExporter(
      isPresented: $showExporter,
      document: exportDocument,
      contentType: .json,
      defaultFilename: "KurierX-backup-\(KXFormat.shortDate(Date.now))"
    ) { result in
      if case .failure(let error) = result {
        errorMessage = error.localizedDescription
      } else {
        message = "Резервная копия создана."
      }
    }
    .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
      switch result {
      case .success(let url):
        restore(from: url)
      case .failure(let error):
        errorMessage = error.localizedDescription
      }
    }
  }

  private func makeBackup() -> KurierXBackup {
    let visibleShifts = shifts.filter { $0.deletedAt == nil }
    let shiftIndex = Dictionary(
      uniqueKeysWithValues: visibleShifts.enumerated().map { ($0.element.id, $0.offset) })
    return KurierXBackup(
      version: 1,
      createdAt: Date.now,
      shifts: visibleShifts.map {
        BackupShift(
          date: $0.date,
          warehouse: $0.warehouse.rawValue,
          status: $0.status.rawValue,
          plannedRings: $0.plannedRings,
          startedAt: $0.startedAt,
          endedAt: $0.endedAt,
          queueOdometer: $0.queueOdometer,
          closingOdometer: $0.closingOdometer,
          closeReason: $0.closeReason,
          note: $0.note
        )
      },
      routes: routes.filter { $0.deletedAt == nil }.compactMap { route in
        guard let index = shiftIndex[route.shiftID] else { return nil }
        return BackupRoute(
          originalID: route.id,
          shiftIndex: index,
          date: route.date,
          sequence: route.sequence,
          type: route.type.rawValue,
          warehouse: route.warehouse.rawValue,
          factualOrders: route.factualOrders,
          distanceKm: route.distanceKm,
          externalRouteID: route.externalRouteID,
          note: route.note
        )
      },
      customers: customers.filter { $0.deletedAt == nil }.map {
        BackupCustomer(
          routeOriginalID: $0.routeID,
          date: $0.date,
          routeSequence: $0.routeSequence,
          routeType: $0.routeType.rawValue,
          position: $0.position,
          photoOrder: $0.photoOrder,
          firstName: $0.firstName,
          lastName: $0.lastName,
          address: $0.address,
          normalizedAddress: $0.normalizedAddress,
          addressVerified: $0.addressVerified,
          bags: $0.bags,
          tipsHellers: $0.tipValue,
          note: $0.note
        )
      },
      calendar: calendar.filter { $0.deletedAt == nil }.map {
        BackupCalendar(
          date: $0.date, warehouse: $0.warehouse.rawValue, startMinutes: $0.startMinutes,
          plannedRings: $0.plannedRings, note: $0.note)
      },
      finances: finances.filter { $0.deletedAt == nil }.map {
        BackupFinancial(
          date: $0.date, kind: $0.kind.rawValue, amountHellers: $0.amountHellers, note: $0.note,
          source: $0.source)
      },
      expenses: expenses.filter { $0.deletedAt == nil }.map {
        BackupExpense(
          date: $0.date, amountHellers: $0.amountHellers, liters: $0.liters,
          distanceKm: $0.distanceKm, odometer: $0.odometer, kind: $0.kind.rawValue, note: $0.note)
      },
      advances: advances.filter { $0.deletedAt == nil }.map {
        BackupAdvance(date: $0.date, amountHellers: $0.amountHellers, note: $0.note)
      },
      goals: goals.filter { $0.deletedAt == nil }.map {
        BackupGoal(month: $0.month, targetOrders: $0.targetOrders, targetHellers: $0.targetHellers)
      }
    )
  }

  private func restore(from url: URL) {
    errorMessage = ""
    message = ""
    let accessed = url.startAccessingSecurityScopedResource()
    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
    do {
      let data = try Data(contentsOf: url)
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      let backup = try decoder.decode(KurierXBackup.self, from: data)

      var restoredShifts: [Shift] = []
      for item in backup.shifts {
        let shift = Shift(
          date: item.date,
          warehouse: Warehouse(rawValue: item.warehouse) ?? .liboc,
          status: ShiftStatus(rawValue: item.status) ?? .complete,
          plannedRings: item.plannedRings,
          startedAt: item.startedAt,
          endedAt: item.endedAt,
          queueOdometer: item.queueOdometer,
          closingOdometer: item.closingOdometer,
          closeReason: item.closeReason,
          note: item.note,
          source: .importData
        )
        context.insert(shift)
        restoredShifts.append(shift)
      }

      var routeMap: [UUID: UUID] = [:]
      for item in backup.routes where restoredShifts.indices.contains(item.shiftIndex) {
        let route = Route(
          shiftID: restoredShifts[item.shiftIndex].id,
          date: item.date,
          sequence: item.sequence,
          type: RouteType(rawValue: item.type) ?? .ot,
          warehouse: Warehouse(rawValue: item.warehouse) ?? .liboc,
          factualOrders: item.factualOrders,
          distanceKm: item.distanceKm,
          externalRouteID: item.externalRouteID,
          confirmed: true,
          source: .importData,
          note: item.note
        )
        context.insert(route)
        routeMap[item.originalID] = route.id
      }

      for item in backup.customers {
        context.insert(
          Customer(
            routeID: item.routeOriginalID.flatMap { routeMap[$0] },
            date: item.date,
            routeSequence: item.routeSequence,
            routeType: RouteType(rawValue: item.routeType) ?? .ot,
            position: item.position,
            photoOrder: item.photoOrder,
            firstName: item.firstName,
            lastName: item.lastName,
            address: item.address,
            normalizedAddress: item.normalizedAddress,
            addressVerified: item.addressVerified,
            bags: item.bags,
            tipsHellers: item.tipsHellers,
            source: .importData,
            note: item.note
          )
        )
      }

      for item in backup.calendar {
        context.insert(
          CalendarPlan(
            date: item.date, warehouse: Warehouse(rawValue: item.warehouse) ?? .liboc,
            startMinutes: item.startMinutes, plannedRings: item.plannedRings, source: .importData,
            note: item.note))
      }
      for item in backup.finances {
        context.insert(
          FinancialEntry(
            date: item.date, kind: FinancialKind(rawValue: item.kind) ?? .bonus,
            amountHellers: item.amountHellers, note: item.note,
            source: DataSource.importData.rawValue))
      }
      for item in backup.expenses {
        context.insert(
          FuelEntry(
            date: item.date, amountHellers: item.amountHellers, liters: item.liters,
            distanceKm: item.distanceKm, odometer: item.odometer,
            kind: AutoExpenseKind(rawValue: item.kind) ?? .other, note: item.note))
      }
      for item in backup.advances {
        context.insert(
          AdvanceEntry(date: item.date, amountHellers: item.amountHellers, note: item.note))
      }
      for item in backup.goals {
        context.insert(
          Goal(
            month: item.month, targetOrders: item.targetOrders, targetHellers: item.targetHellers))
      }
      audit(
        context, action: "restore", entityType: "backup", entityID: UUID().uuidString,
        details: "Восстановлена копия от \(KXFormat.date(backup.createdAt))")
      try context.save()
      message = "Данные из резервной копии восстановлены."
    } catch {
      errorMessage = "Не удалось восстановить копию: \(error.localizedDescription)"
    }
  }
}

// MARK: Audit log

struct AuditLogView: View {
  @Query(sort: \AuditEntry.createdAt, order: .reverse) private var entries: [AuditEntry]

  var body: some View {
    ScrollView {
      VStack(spacing: 10) {
        KXHeader(title: "Журнал", subtitle: "История действий в приложении")
        if entries.isEmpty {
          KXCard { Text("Журнал пока пуст.").foregroundStyle(.secondary) }
        }
        ForEach(entries) { entry in
          KXCard {
            VStack(alignment: .leading, spacing: 4) {
              HStack {
                Text(entry.action.uppercased()).font(.caption.bold()).foregroundStyle(Color.kxGreen)
                Spacer()
                Text(KXFormat.shortDate(entry.createdAt)).font(.caption).foregroundStyle(.secondary)
              }
              Text(entry.entityType).font(.headline)
              Text(entry.details).font(.caption).foregroundStyle(.secondary)
            }
          }
        }
      }
      .padding(18)
    }
    .navigationTitle("Журнал")
    .navigationBarTitleDisplayMode(.inline)
    .kxPageBackground()
  }
}

// MARK: Trash

struct TrashView: View {
  @Environment(\.modelContext) private var context
  @EnvironmentObject private var developerAccess: DeveloperAccess

  @Query private var shifts: [Shift]
  @Query private var routes: [Route]
  @Query private var customers: [Customer]
  @Query private var finances: [FinancialEntry]
  @Query private var expenses: [FuelEntry]
  @Query private var advances: [AdvanceEntry]
  @Query private var goals: [Goal]

  var body: some View {
    ScrollView {
      VStack(spacing: 12) {
        KXHeader(title: "Корзина", subtitle: "Удалённые объекты не участвуют в расчётах")
        trashSection(title: "Трассы", count: routes.filter { $0.deletedAt != nil }.count) {
          ForEach(routes.filter { $0.deletedAt != nil }) { route in
            restoreRow("Трасса #\(route.sequence) · \(route.type.rawValue)") {
              route.deletedAt = nil
              try? context.save()
            }
          }
        }
        trashSection(title: "Клиенты", count: customers.filter { $0.deletedAt != nil }.count) {
          ForEach(customers.filter { $0.deletedAt != nil }) { customer in
            restoreRow(customer.displayName) {
              customer.deletedAt = nil
              try? context.save()
            }
          }
        }
        trashSection(title: "Смены", count: shifts.filter { $0.deletedAt != nil }.count) {
          ForEach(shifts.filter { $0.deletedAt != nil }) { shift in
            restoreRow(KXFormat.date(shift.date)) {
              shift.deletedAt = nil
              try? context.save()
            }
          }
        }
        trashSection(title: "Финансы", count: finances.filter { $0.deletedAt != nil }.count) {
          ForEach(finances.filter { $0.deletedAt != nil }) { entry in
            restoreRow("\(entry.kind.rawValue) · \(KXFormat.money(entry.amountHellers))") {
              entry.deletedAt = nil
              try? context.save()
            }
          }
        }
        trashSection(title: "Авторасходы", count: expenses.filter { $0.deletedAt != nil }.count) {
          ForEach(expenses.filter { $0.deletedAt != nil }) { entry in
            restoreRow("\(entry.kind.rawValue) · \(KXFormat.money(entry.amountHellers))") {
              entry.deletedAt = nil
              try? context.save()
            }
          }
        }
        trashSection(title: "Авансы", count: advances.filter { $0.deletedAt != nil }.count) {
          ForEach(advances.filter { $0.deletedAt != nil }) { entry in
            restoreRow(KXFormat.money(entry.amountHellers)) {
              entry.deletedAt = nil
              try? context.save()
            }
          }
        }
        trashSection(title: "Цели", count: goals.filter { $0.deletedAt != nil }.count) {
          ForEach(goals.filter { $0.deletedAt != nil }) { goal in
            restoreRow("\(goal.month) · \(goal.targetOrders) заказов") {
              goal.deletedAt = nil
              try? context.save()
            }
          }
        }
        if developerAccess.isUnlocked {
          KXCard {
            Text("Окончательное удаление рекомендуется выполнять только после резервной копии.")
              .font(.caption)
              .foregroundStyle(.orange)
          }
        }
      }
      .padding(18)
    }
    .navigationTitle("Корзина")
    .navigationBarTitleDisplayMode(.inline)
    .kxPageBackground()
  }

  private func trashSection<Content: View>(
    title: String,
    count: Int,
    @ViewBuilder content: () -> Content
  ) -> some View {
    Group {
      if count > 0 {
        VStack(alignment: .leading, spacing: 8) {
          Text("\(title) · \(count)").font(.title3.bold())
          content()
        }
      }
    }
  }

  private func restoreRow(_ title: String, action: @escaping () -> Void) -> some View {
    KXCard {
      HStack {
        Text(title)
        Spacer()
        Button("Восстановить", action: action)
          .foregroundStyle(Color.kxGreen)
      }
    }
  }
}

// MARK: Developer Mode

struct DeveloperModeView: View {
  @Environment(\.modelContext) private var context
  @EnvironmentObject private var access: DeveloperAccess
  @Query private var preferences: [AppPreference]

  @State private var pin = ""
  @State private var repeatedPIN = ""
  @State private var baseline = ""
  @State private var showResetConfirmation = false
  @State private var localMessage = ""

  private var baselinePreference: AppPreference? {
    preferences.first { $0.key == "ordersBaseline" }
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 15) {
        KXHeader(
          title: "Developer Mode",
          subtitle: "PIN, \(access.biometricName) и служебные функции"
        )

        if access.isUnlocked {
          KXCard {
            VStack(alignment: .leading, spacing: 13) {
              Label("Расширенный режим активен", systemImage: "checkmark.shield.fill")
                .font(.headline)
                .foregroundStyle(Color.kxGreen)

              Toggle(
                "Вход через \(access.biometricName)",
                isOn: Binding(
                  get: { access.faceEnabled },
                  set: { newValue in
                    access.faceEnabled = newValue
                    if newValue {
                      Task { await access.authenticateBiometrics() }
                    }
                  }
                ))

              KXSecondaryButton(title: "Заблокировать режим", icon: "lock.fill") {
                access.lock()
              }

              KXSecondaryButton(title: "Сбросить PIN", icon: "trash", destructive: true) {
                showResetConfirmation = true
              }
            }
          }

          KXCard {
            VStack(alignment: .leading, spacing: 12) {
              Text("Baseline заказов").font(.title3.bold())
              Text(
                "Первый импорт статистики сохраняется как baseline. Здесь его можно изменить или сбросить."
              )
              .font(.caption)
              .foregroundStyle(.secondary)
              KXInput(title: "Baseline", text: $baseline, keyboard: .numberPad)
              HStack(spacing: 12) {
                KXPrimaryButton(title: "Сохранить") { saveBaseline() }
                KXSecondaryButton(title: "Сбросить", destructive: true) { resetBaseline() }
              }
            }
          }

          KXCard {
            VStack(alignment: .leading, spacing: 7) {
              Text("Доступные возможности").font(.title3.bold())
              Label("Редактирование закрытых трасс", systemImage: "pencil")
              Label("Изменение количества заказов и километража", systemImage: "ruler")
              Label("Редактирование завершённых смен", systemImage: "calendar.badge.clock")
              Label("Управление baseline", systemImage: "chart.bar.doc.horizontal")
              Label("Восстановление данных из корзины", systemImage: "arrow.uturn.backward")
            }
          }
        } else if !access.hasPIN {
          KXCard {
            VStack(alignment: .leading, spacing: 12) {
              Text("Первичная настройка")
                .font(.title3.bold())
              Text(
                "PIN ещё не создавался. Установите новый PIN, после чего сможете включить Face ID."
              )
              .foregroundStyle(.secondary)
              KXSecureInput(title: "Новый PIN", text: $pin)
              KXSecureInput(title: "Повторите PIN", text: $repeatedPIN)
              KXPrimaryButton(title: "Создать PIN", icon: "key.fill") {
                if access.createPIN(pin, repeat: repeatedPIN) {
                  pin = ""
                  repeatedPIN = ""
                }
              }
            }
          }
        } else {
          KXCard {
            VStack(alignment: .leading, spacing: 12) {
              Text("Разблокировка")
                .font(.title3.bold())
              KXSecureInput(title: "PIN", text: $pin)
              KXPrimaryButton(title: "Подтвердить", icon: "lock.open.fill") {
                if access.verify(pin) { pin = "" }
              }
              if access.faceEnabled {
                KXSecondaryButton(title: "Войти через \(access.biometricName)", icon: "faceid") {
                  Task { await access.authenticateBiometrics() }
                }
              }
            }
          }
        }

        KXErrorText(text: access.errorMessage)
        if !localMessage.isEmpty {
          Label(localMessage, systemImage: "checkmark.circle.fill")
            .foregroundStyle(Color.kxGreen)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      .padding(18)
    }
    .scrollDismissesKeyboard(.interactively)
    .kxDismissKeyboardOnTap()
    .navigationTitle("Developer Mode")
    .navigationBarTitleDisplayMode(.inline)
    .kxPageBackground()
    .toolbar { KeyboardDoneToolbar() }
    .onAppear {
      baseline = baselinePreference?.value ?? ""
    }
    .alert("Сбросить PIN?", isPresented: $showResetConfirmation) {
      Button("Сбросить", role: .destructive) {
        access.resetPIN()
        pin = ""
        repeatedPIN = ""
      }
      Button("Отмена", role: .cancel) {}
    } message: {
      Text("После сброса нужно будет создать новый PIN. Биометрия также отключится.")
    }
  }

  private func saveBaseline() {
    guard let value = Int(baseline), value >= 0 else {
      access.errorMessage = "Введите корректный baseline."
      return
    }
    if let preference = baselinePreference {
      preference.value = String(value)
    } else {
      context.insert(AppPreference(key: "ordersBaseline", value: String(value)))
    }
    audit(
      context, action: "edit", entityType: "baseline", entityID: "ordersBaseline",
      details: String(value))
    try? context.save()
    localMessage = "Baseline сохранён."
    access.errorMessage = ""
  }

  private func resetBaseline() {
    if let preference = baselinePreference { context.delete(preference) }
    try? context.save()
    baseline = ""
    localMessage = "Baseline сброшен. Следующий импорт станет новым baseline."
  }
}

// MARK: Kilometer overview

struct KilometerOverviewView: View {
  @Query private var shifts: [Shift]
  @Query private var routes: [Route]
  @Query private var expenses: [FuelEntry]

  private var routeKm: Double {
    routes.filter { $0.deletedAt == nil }.compactMap(\.distanceKm).reduce(0, +)
  }

  private var shiftKm: Double {
    shifts.filter { $0.deletedAt == nil }.reduce(0) { result, shift in
      guard let start = shift.queueOdometer, let end = shift.closingOdometer else { return result }
      return result + max(0, end - start)
    }
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 14) {
        KXHeader(title: "Километраж", subtitle: "Сводка по трассам, сменам и расходам")
        KXCard {
          VStack(alignment: .leading, spacing: 9) {
            Text("\(KXFormat.number(routeKm)) км")
              .font(.system(size: 36, weight: .bold, design: .rounded))
            Text("Сумма километража закрытых трасс")
              .foregroundStyle(.secondary)
          }
        }
        KXCard {
          VStack(alignment: .leading, spacing: 9) {
            LabeledContent("По одометрам смен", value: "\(KXFormat.number(shiftKm)) км")
            LabeledContent(
              "В авторасходах",
              value:
                "\(KXFormat.number(expenses.filter { $0.deletedAt == nil }.reduce(0) { $0 + $1.distanceKm })) км"
            )
            LabeledContent("Расхождение", value: "\(KXFormat.number(abs(shiftKm - routeKm))) км")
          }
        }
        KXCard {
          Text(
            "Километраж закрытой трассы редактируется в её карточке после разблокировки Developer Mode."
          )
          .foregroundStyle(.secondary)
        }
      }
      .padding(18)
    }
    .navigationTitle("Километраж")
    .navigationBarTitleDisplayMode(.inline)
    .kxPageBackground()
  }
}

// MARK: Tutorial

struct TutorialView: View {
  private let steps: [(String, String, String)] = [
    (
      "1. Начните смену", "На Главной выберите склад, план колечек и при необходимости одометр.",
      "play.circle.fill"
    ),
    (
      "2. Добавьте трассу",
      "Откройте Сканер → Трасса. Тип выбирается вручную, заказы и километраж можно распознать или исправить.",
      "point.topleft.down.to.point.bottomright.curvepath"
    ),
    (
      "3. Импортируйте заказников",
      "Выберите несколько фото, проверьте порядок, пакеты, чаевые и адреса RÚIAN.", "person.2.fill"
    ),
    (
      "4. Закройте смену",
      "При досрочном закрытии обязательно укажите причину и конечный километраж.",
      "stop.circle.fill"
    ),
    (
      "5. Проверьте статистику",
      "Заработок, чаевые, бонусы, штрафы, дизель и авансы считаются автоматически.",
      "chart.bar.fill"
    ),
    (
      "6. Используйте Developer Mode",
      "Создайте PIN, включите Face ID и редактируйте закрытые данные при необходимости.",
      "shield.lefthalf.filled"
    ),
  ]

  var body: some View {
    ScrollView {
      VStack(spacing: 13) {
        KXHeader(title: "Как пользоваться KurierX")
        ForEach(steps, id: \.0) { step in
          KXCard {
            HStack(alignment: .top, spacing: 13) {
              Image(systemName: step.2)
                .font(.title2)
                .foregroundStyle(Color.kxGreen)
                .frame(width: 35)
              VStack(alignment: .leading, spacing: 5) {
                Text(step.0).font(.headline)
                Text(step.1).foregroundStyle(.secondary)
              }
            }
          }
        }
      }
      .padding(18)
    }
    .navigationTitle("Обучение")
    .navigationBarTitleDisplayMode(.inline)
    .kxPageBackground()
  }
}

// MARK: Settings

struct SettingsView: View {
  @EnvironmentObject private var session: SessionStore

  @AppStorage("kxWeekdayRateHellers") private var weekdayRate = 5_000
  @AppStorage("kxWeekendRateHellers") private var weekendRate = 8_000
  @AppStorage("kxRegionBonusHellers") private var regionBonus = 25_000
  @AppStorage("kxDefaultWarehouse") private var defaultWarehouse = Warehouse.liboc.rawValue

  @State private var weekdayText = ""
  @State private var weekendText = ""
  @State private var regionText = ""
  @State private var testAddress = ""
  @State private var testResult = ""
  @State private var errorMessage = ""

  var body: some View {
    ScrollView {
      VStack(spacing: 14) {
        KXHeader(title: "Настройки")

        KXCard {
          VStack(alignment: .leading, spacing: 12) {
            Text("Склад по умолчанию").font(.headline)
            Picker("Склад", selection: $defaultWarehouse) {
              ForEach(Warehouse.allCases) { Text($0.rawValue).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
          }
        }

        KXCard {
          VStack(alignment: .leading, spacing: 12) {
            Text("Ставки автоматического расчёта").font(.title3.bold())
            KXInput(title: "Пн–Чт, Kč за заказ", text: $weekdayText, keyboard: .decimalPad)
            KXInput(title: "Пт–Вс, Kč за заказ", text: $weekendText, keyboard: .decimalPad)
            KXInput(title: "Доплата Region, Kč", text: $regionText, keyboard: .decimalPad)
            KXPrimaryButton(title: "Сохранить ставки", icon: "checkmark") { saveRates() }
          }
        }

        KXCard {
          VStack(alignment: .leading, spacing: 12) {
            Text("Проверка RÚIAN").font(.title3.bold())
            KXInput(title: "Адрес для проверки", text: $testAddress)
            KXSecondaryButton(title: "Проверить адрес", icon: "mappin.and.ellipse") {
              Task {
                do {
                  testResult =
                    try await RuianAddressService.shared.validate(testAddress) ?? "Адрес не найден"
                } catch {
                  testResult = error.localizedDescription
                }
              }
            }
            if !testResult.isEmpty {
              Text(testResult).font(.caption).foregroundStyle(Color.kxGreen)
            }
          }
        }

        KXErrorText(text: errorMessage)

        KXSecondaryButton(
          title: session.isOwner ? "Выйти из OWNER" : "Выйти из аккаунта",
          icon: "rectangle.portrait.and.arrow.right",
          destructive: true
        ) {
          Task {
            if session.isOwner {
              await session.leaveOwnerToActivation()
            } else {
              await session.signOutUser()
            }
          }
        }
      }
      .padding(18)
    }
    .scrollDismissesKeyboard(.interactively)
    .kxDismissKeyboardOnTap()
    .navigationTitle("Настройки")
    .navigationBarTitleDisplayMode(.inline)
    .kxPageBackground()
    .toolbar { KeyboardDoneToolbar() }
    .onAppear {
      weekdayText = String(Double(weekdayRate) / 100)
      weekendText = String(Double(weekendRate) / 100)
      regionText = String(Double(regionBonus) / 100)
    }
  }

  private func saveRates() {
    guard let weekday = Double(weekdayText.replacingOccurrences(of: ",", with: ".")), weekday > 0,
      let weekend = Double(weekendText.replacingOccurrences(of: ",", with: ".")), weekend > 0,
      let region = Double(regionText.replacingOccurrences(of: ",", with: ".")), region >= 0
    else {
      errorMessage = "Проверьте значения ставок."
      return
    }
    weekdayRate = Int(weekday * 100)
    weekendRate = Int(weekend * 100)
    regionBonus = Int(region * 100)
    errorMessage = ""
  }
}

// MARK: - OWNER Control

struct OwnerControlView: View {
  @EnvironmentObject private var session: SessionStore

  @State private var users: [AdminUser] = []
  @State private var keys: [AdminKey] = []
  @State private var generatedKey = ""
  @State private var selectedUser: AdminUser?
  @State private var keyToDelete: AdminKey?
  @State private var userListener: ListenerRegistration?
  @State private var keyListener: ListenerRegistration?
  @State private var errorMessage = ""

  var body: some View {
    ScrollView {
      VStack(spacing: 14) {
        HStack(alignment: .top) {
          KXHeader(
            title: "KurierX\nControl",
            subtitle: "Пользователи, лицензии и устройства"
          )
          Button {
            Task { await session.leaveOwnerToActivation() }
          } label: {
            Image(systemName: "rectangle.portrait.and.arrow.right")
              .font(.title2)
              .padding(12)
              .background(Color.kxGreen.opacity(0.2), in: RoundedRectangle(cornerRadius: 13))
          }
        }

        KXCard {
          VStack(spacing: 10) {
            KXPrimaryButton(title: "Создать ключ", icon: "key.fill") {
              createKey()
            }
            if !generatedKey.isEmpty {
              HStack {
                Text(generatedKey)
                  .font(.system(.body, design: .monospaced))
                  .bold()
                  .lineLimit(1)
                  .minimumScaleFactor(0.7)
                Spacer()
                Button {
                  UIPasteboard.general.string = generatedKey
                } label: {
                  Image(systemName: "doc.on.doc")
                }
              }
              .padding(12)
              .background(Color.kxSurface2, in: RoundedRectangle(cornerRadius: 12))
            }
          }
        }

        KXErrorText(text: errorMessage)

        KXHeader(title: "Ключи", subtitle: "\(keys.count) всего")
        KXCard {
          VStack(spacing: 0) {
            ForEach(keys) { key in
              HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                  Text(key.display)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                  Text(key.status)
                    .font(.caption)
                    .foregroundStyle(key.status == "UNUSED" ? Color.kxGreen : .secondary)
                }
                Spacer()
                Button {
                  UIPasteboard.general.string = key.display
                } label: {
                  Image(systemName: "doc.on.doc")
                }
                if key.status == "UNUSED" {
                  Button(role: .destructive) {
                    keyToDelete = key
                  } label: {
                    Image(systemName: "trash")
                  }
                }
              }
              .padding(.vertical, 11)
              if key.id != keys.last?.id { Divider() }
            }
          }
        }

        KXHeader(title: "Пользователи", subtitle: "\(users.count) зарегистрировано")
        ForEach(users) { user in
          Button {
            selectedUser = user
          } label: {
            KXCard {
              HStack(spacing: 12) {
                ZStack {
                  Circle().fill(statusColor(user.status).opacity(0.15))
                  Image(systemName: "person.fill")
                    .foregroundStyle(statusColor(user.status))
                }
                .frame(width: 46, height: 46)
                VStack(alignment: .leading, spacing: 4) {
                  Text(user.fullName).font(.headline)
                  Text("#\(user.courierID) · \(user.status)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                  if !user.deviceID.isEmpty {
                    Text("Device: \(String(user.deviceID.prefix(14)))…")
                      .font(.caption2)
                      .foregroundStyle(.tertiary)
                  }
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
              }
            }
          }
          .buttonStyle(.plain)
        }
      }
      .padding(18)
    }
    .navigationTitle("KurierX Control")
    .navigationBarTitleDisplayMode(.inline)
    .kxPageBackground()
    .onAppear(perform: load)
    .onDisappear {
      userListener?.remove()
      keyListener?.remove()
    }
    .sheet(item: $selectedUser) { user in
      UserAdminSheet(user: user)
    }
    .alert(
      "Удалить ключ?",
      isPresented: Binding(
        get: { keyToDelete != nil },
        set: { if !$0 { keyToDelete = nil } }
      )
    ) {
      Button("Удалить", role: .destructive) {
        guard let keyToDelete else { return }
        Firestore.firestore().collection("activation_keys").document(keyToDelete.id).delete()
        self.keyToDelete = nil
      }
      Button("Отмена", role: .cancel) { keyToDelete = nil }
    }
  }

  private func statusColor(_ status: String) -> Color {
    switch status {
    case "ACTIVE": return .kxGreen
    case "FROZEN": return .orange
    case "BLACKLISTED": return .red
    default: return .secondary
    }
  }

  private func load() {
    let database = Firestore.firestore()
    userListener?.remove()
    keyListener?.remove()

    userListener = database.collection("users").addSnapshotListener { snapshot, error in
      if let error {
        errorMessage = error.localizedDescription
        return
      }
      users =
        snapshot?.documents
        .map { AdminUser(id: $0.documentID, data: $0.data()) }
        .sorted { $0.firstName < $1.firstName } ?? []
    }

    keyListener = database.collection("activation_keys").addSnapshotListener { snapshot, error in
      if let error {
        errorMessage = error.localizedDescription
        return
      }
      keys =
        snapshot?.documents
        .map { AdminKey(id: $0.documentID, data: $0.data()) }
        .sorted { $0.display > $1.display } ?? []
    }
  }

  private func createKey() {
    let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    func part() -> String { String((0..<4).compactMap { _ in alphabet.randomElement() }) }
    let key = "KX-\(part())-\(part())-\(part())"
    let normalized = key.filter { $0.isLetter || $0.isNumber }
    let hash = SHA256.hash(data: Data(normalized.utf8))
      .map { String(format: "%02x", $0) }
      .joined()

    Firestore.firestore().collection("activation_keys").document(hash).setData([
      "status": "UNUSED",
      "createdAt": FieldValue.serverTimestamp(),
      "createdBy": session.ownerUID,
      "keySuffix": String(key.suffix(4)),
      "displayKey": key,
    ]) { error in
      if let error {
        errorMessage = error.localizedDescription
      } else {
        generatedKey = key
        UIPasteboard.general.string = key
      }
    }
  }
}

struct AdminKey: Identifiable {
  let id: String
  let display: String
  let status: String

  init(id: String, data: [String: Any]) {
    self.id = id
    display =
      data["displayKey"] as? String
      ?? "••••-\(data["keySuffix"] as? String ?? "")"
    status = data["status"] as? String ?? "UNKNOWN"
  }
}

struct AdminUser: Identifiable {
  let id: String
  var firstName: String
  var lastName: String
  var courierID: String
  var status: String
  var deviceID: String

  var fullName: String {
    let name = (firstName + " " + lastName).trimmingCharacters(in: .whitespaces)
    return name.isEmpty ? "Без имени" : name
  }

  init(id: String, data: [String: Any]) {
    self.id = id
    firstName = data["firstName"] as? String ?? ""
    lastName = data["lastName"] as? String ?? ""
    courierID = data["courierId"] as? String ?? ""
    status = data["status"] as? String ?? "UNKNOWN"
    deviceID = data["deviceId"] as? String ?? ""
  }
}

struct UserAdminSheet: View {
  @Environment(\.dismiss) private var dismiss

  let user: AdminUser

  @State private var firstName = ""
  @State private var lastName = ""
  @State private var courierID = ""
  @State private var errorMessage = ""
  @State private var confirmDelete = false

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 15) {
          KXHeader(title: "Пользователь", subtitle: user.status)
          KXCard {
            VStack(spacing: 12) {
              KXInput(title: "Имя", text: $firstName)
              KXInput(title: "Фамилия", text: $lastName)
              KXInput(title: "Courier ID", text: $courierID, keyboard: .numberPad)
              if !user.deviceID.isEmpty {
                Text(user.deviceID)
                  .font(.system(.caption2, design: .monospaced))
                  .textSelection(.enabled)
                  .foregroundStyle(.secondary)
              }
            }
          }

          KXCard {
            VStack(spacing: 10) {
              KXPrimaryButton(title: "Активировать", icon: "checkmark.circle.fill") {
                updateStatus("ACTIVE")
              }
              KXSecondaryButton(title: "Заморозить", icon: "snowflake") {
                updateStatus("FROZEN")
              }
              KXSecondaryButton(
                title: "В чёрный список", icon: "hand.raised.fill", destructive: true
              ) {
                updateStatus("BLACKLISTED")
              }
            }
          }

          KXErrorText(text: errorMessage)
          KXPrimaryButton(title: "Сохранить профиль", icon: "checkmark") { saveProfile() }
          KXSecondaryButton(title: "Удалить пользователя", icon: "trash", destructive: true) {
            confirmDelete = true
          }
          KXSecondaryButton(title: "Закрыть") { dismiss() }
        }
        .padding(18)
      }
      .scrollDismissesKeyboard(.interactively)
      .kxDismissKeyboardOnTap()
      .kxPageBackground()
      .navigationBarHidden(true)
      .toolbar { KeyboardDoneToolbar() }
      .onAppear {
        firstName = user.firstName
        lastName = user.lastName
        courierID = user.courierID
      }
      .alert("Удалить пользователя?", isPresented: $confirmDelete) {
        Button("Удалить", role: .destructive) {
          Firestore.firestore().collection("users").document(user.id).delete { error in
            if let error { errorMessage = error.localizedDescription } else { dismiss() }
          }
        }
        Button("Отмена", role: .cancel) {}
      }
    }
  }

  private func saveProfile() {
    Firestore.firestore().collection("users").document(user.id).updateData([
      "firstName": firstName,
      "lastName": lastName,
      "courierId": courierID,
      "updatedAt": FieldValue.serverTimestamp(),
    ]) { error in
      if let error { errorMessage = error.localizedDescription } else { dismiss() }
    }
  }

  private func updateStatus(_ status: String) {
    Firestore.firestore().collection("users").document(user.id).updateData([
      "status": status,
      "updatedAt": FieldValue.serverTimestamp(),
    ]) { error in
      if let error { errorMessage = error.localizedDescription } else { dismiss() }
    }
  }
}
