import SwiftUI

#if canImport(UIKit)
import UIKit

/// Hosts a gesture recognizer that dismisses the keyboard when tapping anywhere except on active text inputs.
private final class KeyboardDismissalHostingView: UIView {
    private lazy var tapGesture: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        gesture.cancelsTouchesInView = false
        gesture.delaysTouchesBegan = false
        gesture.delaysTouchesEnded = false
        return gesture
    }()

    private weak var installedWindow: UIWindow?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard let currentWindow = window else {
            installedWindow?.removeGestureRecognizer(tapGesture)
            installedWindow = nil
            return
        }
        guard installedWindow !== currentWindow else { return }
        installedWindow?.removeGestureRecognizer(tapGesture)
        currentWindow.addGestureRecognizer(tapGesture)
        installedWindow = currentWindow
    }

    deinit {
        installedWindow?.removeGestureRecognizer(tapGesture)
    }

    @objc private func handleTap(_ sender: UITapGestureRecognizer) {
        guard sender.state == .ended else { return }
        guard let window = sender.view as? UIWindow ?? installedWindow else { return }
        let location = sender.location(in: window)
        guard let hitView = window.hitTest(location, with: nil) else { return }
        if hitView.containsTextInput {
            return
        }
        window.endEditing(true)
    }
}

private extension UIView {
    var containsTextInput: Bool {
        if self is UITextField || self is UITextView {
            return true
        }
        if self as? UITextInput != nil {
            return true
        }
        return superview?.containsTextInput == true
    }
}

private struct KeyboardDismissalRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> KeyboardDismissalHostingView {
        KeyboardDismissalHostingView()
    }

    func updateUIView(_ uiView: KeyboardDismissalHostingView, context: Context) {}
}

private struct KeyboardDismissOnTapModifier: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content
                .background(
                    KeyboardDismissalRepresentable()
                        .allowsHitTesting(false)
                )
        } else {
            content
        }
    }
}

extension View {
    func dismissKeyboardOnTap(enabled: Bool = true) -> some View {
        modifier(KeyboardDismissOnTapModifier(enabled: enabled))
    }
}

#endif
