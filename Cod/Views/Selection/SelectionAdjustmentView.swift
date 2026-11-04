import SwiftUI

/// The same pixel selection as the canvas, adjustable with native controls for
/// VoiceOver, Switch Control, keyboard users and anyone wanting precise edges.
struct SelectionAdjustmentView: View {
    @Binding var selection: CGRect
    let imageSize: CGSize
    @Environment(\.dismiss) private var dismiss

    private var bounds: CGRect { CGRect(origin: .zero, size: imageSize) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(SelectionEdge.allCases, id: \.self) { edge in
                        Stepper(value: Binding(
                            get: { Int(edge.value(in: selection)) },
                            set: { selection = edge.adjusting(selection, to: CGFloat($0), in: bounds) }
                        ), in: edge.range(in: selection, bounds: bounds)) {
                            LabeledContent(edge.title, value: "\(Int(edge.value(in: selection))) px")
                        }
                        .accessibilityIdentifier("crop-edge-\(edge.rawValue)")
                    }
                } header: { Text("Crop edges") } footer: {
                    Text("Positions are measured from the image's top-left corner in pixels. Each adjustment keeps the opposite edge in place.")
                }
                Section {
                    LabeledContent("Selection", value: "\(Int(selection.width)) × \(Int(selection.height)) px")
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Selection")
                        .accessibilityValue("\(Int(selection.width)) × \(Int(selection.height)) pixels")
                        .accessibilityIdentifier("adjusted-crop-size")
                    Button("Select Whole Image") { selection = bounds }
                }
            }
            .navigationTitle("Adjust Crop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
