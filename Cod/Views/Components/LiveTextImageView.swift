import SwiftUI
import VisionKit

/// An image view with Live Text switched on, so text inside a snippet is
/// selectable, and QR codes inside it are tappable, with zero extra UI.
struct LiveTextImageView: UIViewRepresentable {
    let image: UIImage
    var contentMode: UIView.ContentMode = .scaleAspectFit

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView(image: image)
        view.contentMode = contentMode
        view.isUserInteractionEnabled = true
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        guard ImageAnalyzer.isSupported else { return view }
        let interaction = ImageAnalysisInteraction()
        interaction.preferredInteractionTypes = .automatic
        view.addInteraction(interaction)
        context.coordinator.interaction = interaction
        context.coordinator.analyze(image)
        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {
        guard view.image !== image else { return }
        view.image = image
        context.coordinator.analyze(image)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var interaction: ImageAnalysisInteraction?
        private let analyzer = ImageAnalyzer()
        private var task: Task<Void, Never>?

        func analyze(_ image: UIImage) {
            guard ImageAnalyzer.isSupported else { return }
            task?.cancel()
            task = Task { [weak self] in
                guard let self else { return }
                let configuration = ImageAnalyzer.Configuration([.text, .machineReadableCode])
                guard let analysis = try? await analyzer.analyze(image, configuration: configuration) else { return }
                await MainActor.run { self.interaction?.analysis = analysis }
            }
        }

        deinit { task?.cancel() }
    }
}
