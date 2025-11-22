import SwiftUI

struct FocusRingButtonStyle: ButtonStyle {
    let cornerRadius: CGFloat
    let ringColor: Color
    let ringWidth: CGFloat
    let pressedScale: CGFloat

    init(
        cornerRadius: CGFloat = 12,
        ringColor: Color = Theme.primary,
        ringWidth: CGFloat = 2,
        pressedScale: CGFloat = 0.98
    ) {
        self.cornerRadius = cornerRadius
        self.ringColor = ringColor
        self.ringWidth = ringWidth
        self.pressedScale = pressedScale
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(ringColor, lineWidth: configuration.isPressed ? ringWidth : 0)
                    .opacity(configuration.isPressed ? 0.9 : 0.35)
            )
            .scaleEffect(configuration.isPressed ? pressedScale : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}
