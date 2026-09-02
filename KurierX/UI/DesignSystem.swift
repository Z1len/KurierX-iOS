import SwiftUI
import UIKit

extension Color {
  static let kxGreen = Color(red: 0.55, green: 0.77, blue: 0.29)
  static let kxBackground = Color(red: 0.045, green: 0.052, blue: 0.058)
  static let kxSurface = Color(red: 0.095, green: 0.092, blue: 0.105)
  static let kxSurface2 = Color(red: 0.12, green: 0.12, blue: 0.135)
  static let kxPurple = Color(red: 0.30, green: 0.22, blue: 0.52)
}
struct KXCard<C: View>: View {
  let content: C
  init(@ViewBuilder _ c: () -> C) { content = c() }
  var body: some View {
    content.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(
      Color.kxSurface, in: RoundedRectangle(cornerRadius: 22)
    ).overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.055)))
  }
}
struct KXHeader: View {
  let title: String
  var subtitle: String? = nil
  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(title).font(.system(size: 31, weight: .black, design: .rounded))
      if let subtitle { Text(subtitle).font(.system(size: 17)).foregroundStyle(.secondary) }
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
}
struct KeyboardDoneToolbar: ToolbarContent {
  var body: some ToolbarContent {
    ToolbarItemGroup(placement: .keyboard) {
      Spacer()
      Button("Готово") {
        UIApplication.shared.sendAction(
          #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
      }
    }
  }
}
