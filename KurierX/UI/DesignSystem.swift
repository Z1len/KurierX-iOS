import SwiftUI
import UIKit

extension Color {
    static let kxGreen = Color(red: 0.55, green: 0.77, blue: 0.29)
    static let kxBackground = Color(red: 0.045, green: 0.052, blue: 0.058)
    static let kxSurface = Color(red: 0.095, green: 0.092, blue: 0.105)
    static let kxSurface2 = Color(red: 0.12, green: 0.12, blue: 0.135)
    static let kxPurple = Color(red: 0.30, green: 0.22, blue: 0.52)
}

struct KXCard<Content: View>: View {
    let content: Content
    init(content: Content) { self.content = content }
    init(@ViewBuilder _ content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.kxSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.055), lineWidth: 1))
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

struct KXSectionRow: View {
    let title: String; let subtitle: String; let icon: String
    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                Circle().fill(Color.kxGreen.opacity(0.10))
                Image(systemName: icon).font(.system(size: 23, weight: .semibold)).foregroundStyle(Color.kxGreen)
            }.frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 17, weight: .semibold))
                Text(subtitle).font(.system(size: 14)).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(); Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color.kxSurface2, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct KXBrand: View {
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.45))
                Image(systemName: "paperplane.fill").rotationEffect(.degrees(-35)).foregroundStyle(Color.kxGreen).font(.title2)
            }.frame(width: 54, height: 54)
            HStack(spacing: 0) {
                Text("Kurier").font(.system(size: 31, weight: .black, design: .rounded))
                Text("X").font(.system(size: 31, weight: .black, design: .rounded)).foregroundStyle(Color.kxGreen)
            }
            Spacer()
        }
    }
}

struct KeyboardDoneToolbar: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .keyboard) {
            Spacer(); Button("Готово") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
        }
    }
}

extension View {
    func kxDismissKeyboardOnTap() -> some View {
        self.contentShape(Rectangle()).onTapGesture { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
    }
}
