import PencilKit
import SwiftUI

/// Minimal markup surface: draw over the snippet, then flatten and hand back.
struct AnnotateView: View {
    let image: UIImage
    var onDone: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var drawing = PKDrawing()
    @State private var canvasSize: CGSize = .zero

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let displaySize = fittedSize(in: proxy.size)
                ZStack {
                    Color(.systemGroupedBackground)

                    ZStack {
                        Image(uiImage: image)
                            .resizable()
                            .frame(width: displaySize.width, height: displaySize.height)

                        DrawingCanvas(drawing: $drawing)
                            .frame(width: displaySize.width, height: displaySize.height)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .onAppear { canvasSize = displaySize }
                    .onChange(of: displaySize) { _, newValue in canvasSize = newValue }
                }
            }
            .navigationTitle("Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { onDone(flattened()) }
                        .fontWeight(.semibold)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        drawing = PKDrawing()
                    } label: {
                        Label("Clear", systemImage: "eraser")
                    }
                    .disabled(drawing.strokes.isEmpty)
                }
            }
        }
    }

    private func fittedSize(in container: CGSize) -> CGSize {
        let available = CGSize(width: container.width - 24, height: container.height - 24)
        guard image.size.width > 0, image.size.height > 0,
              available.width > 0, available.height > 0 else { return .zero }
        let ratio = min(available.width / image.size.width, available.height / image.size.height)
        return CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
    }

    /// Composites the strokes onto the original at full resolution.
    private func flattened() -> UIImage {
        let target = image.pixelSize
        guard canvasSize.width > 0, target.width > 0 else { return image }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false

        return UIGraphicsImageRenderer(size: target, format: format).image { context in
            image.normalizedUp().draw(in: CGRect(origin: .zero, size: target))
            let strokeImage = drawing.image(
                from: CGRect(origin: .zero, size: canvasSize),
                scale: max(target.width / canvasSize.width, 1)
            )
            strokeImage.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

private struct DrawingCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        // Finger drawing matters here — most people won't have a Pencil out.
        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.marker, color: .systemRed, width: 12)
        canvas.delegate = context.coordinator
        canvas.drawing = drawing

        if let window = UIApplication.shared.activeWindow {
            let picker = PKToolPicker.shared(for: window)
            picker?.setVisible(true, forFirstResponder: canvas)
            picker?.addObserver(canvas)
            DispatchQueue.main.async { canvas.becomeFirstResponder() }
        }
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        if canvas.drawing != drawing { canvas.drawing = drawing }
    }

    func makeCoordinator() -> Coordinator { Coordinator(drawing: $drawing) }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        private let drawing: Binding<PKDrawing>

        init(drawing: Binding<PKDrawing>) { self.drawing = drawing }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            drawing.wrappedValue = canvasView.drawing
        }
    }
}
