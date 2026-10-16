import SwiftUI
import UIKit

@main
struct LaunchHarnessApp: App {
    var body: some Scene { WindowGroup { LaunchHarness().ignoresSafeArea() } }
}

struct LaunchHarness: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> LaunchHarnessController { LaunchHarnessController() }
    func updateUIViewController(_ controller: LaunchHarnessController, context: Context) {}
}

final class LaunchHarnessController: UIViewController, UIDocumentInteractionControllerDelegate {
    private var document: UIDocumentInteractionController?
    private lazy var image: UIImage = {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 300, height: 200), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 150, height: 200))
            UIColor.blue.setFill()
            context.fill(CGRect(x: 150, y: 0, width: 150, height: 200))
            ("COD FAST TEST" as NSString).draw(at: CGPoint(x: 30, y: 80), withAttributes: [
                .font: UIFont.boldSystemFont(ofSize: 28), .foregroundColor: UIColor.white,
            ])
        }
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false
        let title = UILabel()
        title.text = "Cod Launch Lab"
        title.font = .preferredFont(forTextStyle: .largeTitle)
        stack.addArrangedSubview(title)
        let preview = UIImageView(image: image)
        preview.contentMode = .scaleAspectFit
        preview.heightAnchor.constraint(equalToConstant: 200).isActive = true
        stack.addArrangedSubview(preview)
        let share = UIButton(configuration: .filled())
        share.setTitle("Share Test Image", for: .normal)
        share.addAction(UIAction { [weak self, weak share] _ in
            guard let self else { return }
            let sheet = UIActivityViewController(activityItems: [self.image], applicationActivities: nil)
            sheet.popoverPresentationController?.sourceView = share
            self.present(sheet, animated: true)
        }, for: .touchUpInside)
        stack.addArrangedSubview(share)
        let second = UIButton(configuration: .filled())
        second.setTitle("Share Second Image", for: .normal)
        second.addAction(UIAction { [weak self, weak second] _ in
            guard let self else { return }
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            let image = UIGraphicsImageRenderer(size: CGSize(width: 148, height: 92), format: format).image { context in
                UIColor.green.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 148, height: 92))
            }
            let sheet = UIActivityViewController(activityItems: [image], applicationActivities: nil)
            sheet.popoverPresentationController?.sourceView = second
            self.present(sheet, animated: true)
        }, for: .touchUpInside)
        stack.addArrangedSubview(second)
        let open = UIButton(configuration: .filled())
        open.setTitle("Open Test Image In", for: .normal)
        open.addAction(UIAction { [weak self, weak open] _ in
            guard let self, let open else { return }
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("CodFastTest.png")
            try? self.image.pngData()?.write(to: url, options: .atomic)
            let document = UIDocumentInteractionController(url: url)
            document.uti = "public.png"
            document.name = "CodFastTest.png"
            document.delegate = self
            self.document = document
            document.presentOpenInMenu(from: open.bounds, in: open, animated: true)
        }, for: .touchUpInside)
        stack.addArrangedSubview(open)
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
        ])
    }
    func documentInteractionControllerViewControllerForPreview(_ controller: UIDocumentInteractionController) -> UIViewController { self }
}
