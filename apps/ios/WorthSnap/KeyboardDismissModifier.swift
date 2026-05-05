import SwiftUI

private struct KeyboardDismissModifier: ViewModifier {
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .focused($focused)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") {
                        focused = false
                    }
                }
            }
    }
}

extension View {
    func keyboardDismissToolbar() -> some View {
        modifier(KeyboardDismissModifier())
    }
}
