import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct CalendarViewKX: View {
  @Environment(\.modelContext) var ctx
  @Query(sort: \CalendarPlan.date) var plans: [CalendarPlan]
  @State var month = Date.now
  @State var selectedDay: Date?
  @State var photos: [PhotosPickerItem] = []
  @State var parsed: [ParsedCalendarDay] = []
  @State var review = false
  let cols = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)
  var days: [Date?] {
    let c = Calendar.current
    let i = c.dateInterval(of: .month, for: month)!
    let first = i.start
    let l = (c.component(.weekday, from: first) + 5) % 7
    let n = c.range(of: .day, in: .month, for: month)!.count
    return Array(repeating: nil, count: l)
      + (0..<n).map { c.date(byAdding: .day, value: $0, to: first) }
  }
  var monthTitle: String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "ru_RU")
    f.dateFormat = "LLLL yyyy"
    return f.string(from: month).capitalized
  }
  var body: some View {
    ScrollView {
      VStack(spacing: 14) {
        HStack {
          KXHeader(title: "Календарь", subtitle: "План смен и колечек")
          Button("Сегодня") { month = Date.now }
        }
        KXCard {
          VStack {
            HStack {
              Button {
                month = Calendar.current.date(byAdding: .month, value: -1, to: month)!
              } label: {
                Image(systemName: "chevron.left.circle.fill").font(.title)
              }
              Spacer()
              Text(monthTitle).font(.title2.bold()).lineLimit(1)
              Spacer()
              Button {
                month = Calendar.current.date(byAdding: .month, value: 1, to: month)!
              } label: {
                Image(systemName: "chevron.right.circle.fill").font(.title)
              }
            }
            LazyVGrid(columns: cols, spacing: 6) {
              ForEach(["ПН", "ВТ", "СР", "ЧТ", "ПТ", "СБ", "ВС"], id: \.self) {
                Text($0).font(.caption.bold()).foregroundStyle(.secondary)
              }
              ForEach(Array(days.enumerated()), id: \.offset) { _, d in
                if let d {
                  let p = plans.first { $0.date.sameDay(as: d) }
                  Button {
                    selectedDay = d
                  } label: {
                    VStack(alignment: .leading, spacing: 2) {
                      Text("\(Calendar.current.component(.day,from:d))").bold()
                      if let p {
                        Text(String(format: "%02d:%02d", p.startMinutes / 60, p.startMinutes % 60))
                          .font(.caption2).foregroundStyle(Color.kxGreen).lineLimit(1)
                        Text("\(p.plannedRings)K").font(.caption.bold()).lineLimit(1)
                      }
                    }.padding(7).frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
                      .background(
                        (selectedDay?.sameDay(as: d) ?? false)
                          ? Color.kxPurple.opacity(0.6) : Color.kxSurface2,
                        in: RoundedRectangle(cornerRadius: 10))
                  }.buttonStyle(.plain)
                } else {
                  Color.clear.frame(height: 74)
                }
              }
            }
          }
        }
        PhotosPicker(selection: $photos, maxSelectionCount: 3, matching: .images) {
          Text("Импорт скриншота").frame(maxWidth: .infinity)
        }.buttonStyle(.borderedProminent).tint(Color.kxGreen)
        if let d = selectedDay {
          let ps = plans.filter { $0.date.sameDay(as: d) }
          KXCard {
            VStack(alignment: .leading, spacing: 8) {
              Text(d.formatted(.dateTime.day().month(.wide).year()).capitalized).font(.headline)
              if ps.isEmpty {
                Text("На этот день колечек нет").foregroundStyle(.secondary)
              } else {
                ForEach(ps) { p in
                  HStack {
                    Text(p.warehouse.rawValue)
                    Spacer()
                    Text(
                      String(
                        format: "%02d:%02d · %dK", p.startMinutes / 60, p.startMinutes % 60,
                        p.plannedRings))
                  }
                }
              }
            }
          }
        }
      }.padding(18)
    }.onChange(of: photos) { _, items in
      Task {
        var text = ""
        for item in items {
          if let data = try? await item.loadTransferable(type: Data.self),
            let im = UIImage(data: data), let t = try? await OCRService.recognize(im)
          {
            text += "\n" + t
          }
        }
        parsed = CalendarOCRParser.parse(text, month: month)
        review = !parsed.isEmpty
      }
    }.sheet(isPresented: $review) { CalendarReview(month: month, items: parsed) }
  }
}
struct CalendarReview: View {
  @Environment(\.dismiss) var dismiss
  @Environment(\.modelContext) var ctx
  let month: Date
  @State var items: [ParsedCalendarDay]
  init(month: Date, items: [ParsedCalendarDay]) {
    self.month = month
    _items = State(initialValue: items)
  }
  var body: some View {
    NavigationStack {
      List {
        ForEach($items) { $x in
          VStack {
            HStack {
              Text("День \(x.day)").bold()
              Spacer()
              Text("\(x.rings)K")
            }
            Picker("Склад", selection: $x.warehouse) {
              ForEach(Warehouse.allCases) { Text($0.rawValue).tag($0) }
            }
            DatePicker(
              "Время",
              selection: Binding(
                get: {
                  Calendar.current.date(
                    bySettingHour: x.startMinutes / 60, minute: x.startMinutes % 60, second: 0,
                    of: Date.now)!
                },
                set: { d in
                  x.startMinutes = Calendar.current.component(.hour, from: d) * 60
                    + Calendar.current.component(.minute, from: d)
                }), displayedComponents: .hourAndMinute)
            Stepper("Колечек: \(x.rings)", value: $x.rings, in: 1...20)
          }
        }
      }.navigationTitle("Проверка импорта").toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Сохранить") {
            let c = Calendar.current
            for x in items {
              if let d = c.date(bySetting: .day, value: x.day, of: month) {
                ctx.insert(
                  CalendarPlan(
                    date: d, warehouse: x.warehouse, startMinutes: x.startMinutes,
                    plannedRings: x.rings))
              }
            }
            try? ctx.save()
            dismiss()
          }
        }
      }
    }
  }
}
