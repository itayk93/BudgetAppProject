import SwiftUI

struct TopRoundedSheetShape: Shape {
    var radius: CGFloat = 32

    func path(in rect: CGRect) -> Path {
        let bezier = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: [.topLeft, .topRight],
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(bezier.cgPath)
    }
}

struct ActionCard: ViewModifier {
    let isDestructive: Bool

    func body(content: Content) -> some View {
        content
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(
                                isDestructive ? Color.red.opacity(0.25) : Color.gray.opacity(0.18),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 3)
            )
    }
}

extension View {
    func actionCard(destructive: Bool = false) -> some View {
        modifier(ActionCard(isDestructive: destructive))
    }
}
