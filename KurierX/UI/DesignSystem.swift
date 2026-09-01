import SwiftUI
import UIKit

extension Color {
    static let kxGreen = Color(red: 0.55, green: 0.77, blue: 0.29)
    static let kxBackground = Color(red: 0.055, green: 0.065, blue: 0.075)
    static let kxSurface = Color(red: 0.095, green: 0.105, blue: 0.12)
    static let kxSurface2 = Color(red: 0.13, green: 0.14, blue: 0.16)
}

struct KXCard<Content: View>: View {
    let content: Content
    init(content: Content) { self.content = content }
    init(@ViewBuilder _ content: () -> Content) { self.content = content() }
    var body: some View {
        content.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.kxSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }
}

struct KXHeader: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 30, weight: .black, design: .rounded))
            if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct KXMetric: View {
    let title: String; let value: String; let icon: String
    var body: some View {
        KXCard(content: HStack(spacing: 12) {
            Image(systemName: icon).font(.title2).foregroundStyle(Color.kxGreen)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.title3.bold())
            }
            Spacer()
        })
    }
}

struct KXRow: View {
    let title: String; let subtitle: String; let icon: String
    var tint: Color = .kxGreen
    var body: some View {
        HStack(spacing: 14) {
            ZStack { RoundedRectangle(cornerRadius: 12).fill(tint.opacity(0.16)); Image(systemName: icon).foregroundStyle(tint) }.frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 3) { Text(title).font(.headline); Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            Spacer(); Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
        }.padding(.vertical, 5)
    }
}

struct KeyboardDoneToolbar: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .keyboard) {
            Spacer(); Button("Готово") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
        }
    }
}
