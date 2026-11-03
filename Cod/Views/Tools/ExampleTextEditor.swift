import SwiftUI

/// A sample is a placeholder, never the user's editable or persisted draft.
struct ExampleTextEditor: View {
    @Binding var text: String
    let sample: String
    let label: String
    let identifier: String
    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .scrollContentBackground(.hidden)
                .focused($focused)
                .accessibilityLabel(label)
                .accessibilityHint("Leave empty to float the example, or type your own text. The preview above isn't editable.")
                .accessibilityIdentifier(identifier)
            if text.isEmpty, !focused {
                Text(sample).foregroundStyle(.secondary).lineLimit(5)
                    .padding(.horizontal, 4).padding(.vertical, 8)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .frame(height: 160).clipped()
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = false }
            }
        }
    }
}
