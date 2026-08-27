import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Entry point for the share sheet. Loads whatever image was shared, then
/// hands it to the same crop surface the main app uses.
///
/// This extension is deliberately self-contained: with a free provisioning
/// profile there's no App Group, so it can't write into the app's history.
/// Everything it offers (copy, OCR, save to Photos) completes in-process.
final class ShareViewController: UIViewController {
    private var hosting: UIHostingController<ShareRootView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        loadSharedImage()
    }

    private func loadSharedImage() {
        guard let item = (extensionContext?.inputItems as? [NSExtensionItem])?.first,
              let provider = item.attachments?.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) })
        else {
            finish()
            return
        }

        provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] data, _ in
            let image = data.flatMap(UIImage.init(data:))
            DispatchQueue.main.async {
                guard let self else { return }
                guard let image else {
                    self.finish()
                    return
                }
                self.present(image: image.normalizedUp())
            }
        }
    }

    private func present(image: UIImage) {
        let root = ShareRootView(image: image) { [weak self] in self?.finish() }
        let controller = UIHostingController(rootView: root)
        controller.view.backgroundColor = .black
        addChild(controller)
        controller.view.frame = view.bounds
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(controller.view)
        controller.didMove(toParent: self)
        hosting = controller
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
