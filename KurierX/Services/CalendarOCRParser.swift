import Foundation

struct ParsedCalendarDay: Identifiable {
  let id = UUID()
  var day: Int
  var startMinutes: Int
  var rings: Int
  var warehouse: Warehouse
}
enum CalendarOCRParser {
  static func parse(_ text: String, month: Date) -> [ParsedCalendarDay] {
    let lines = text.components(separatedBy: .newlines).map {
      $0.trimmingCharacters(in: .whitespacesAndNewlines)
    }.filter { !$0.isEmpty }
    var out: [ParsedCalendarDay] = []
    var currentDay: Int?
    var currentTime: Int?
    var currentRings: Int?
    func flush() {
      if let d = currentDay, let t = currentTime, let r = currentRings {
        out.append(.init(day: d, startMinutes: t, rings: r, warehouse: .liboc))
      }
      currentTime = nil
      currentRings = nil
    }
    for raw in lines {
      let s = raw.uppercased().replacingOccurrences(of: " ", with: "")
      if let d = Int(s), d >= 1, d <= 31 {
        if currentDay != nil { flush() }
        currentDay = d
        continue
      }
      if let m = s.range(of: #"([0-2]?\d)[:\.]([0-5]\d)"#, options: .regularExpression) {
        let token = String(s[m]).replacingOccurrences(of: ".", with: ":")
        let p = token.split(separator: ":")
        if p.count == 2, currentDay != nil {
          currentTime = (Int(p[0]) ?? 0) * 60 + (Int(p[1]) ?? 0)
        }
      }
      if let m = s.range(of: #"([1-9]|1\d|20)K"#, options: .regularExpression) {
        currentRings = Int(String(s[m].dropLast()))
      }
    }
    flush()
    var uniq: [Int: ParsedCalendarDay] = [:]
    for x in out { uniq[x.day] = x }
    return uniq.values.sorted { $0.day < $1.day }
  }
}
