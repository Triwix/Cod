import SwiftUI
import UIKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

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
    private var music: AVAudioPlayer?
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
        stack.spacing = 12
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
        let text = UIButton(configuration: .filled())
        text.setTitle("Share Test Text", for: .normal)
        text.addAction(UIAction { [weak self, weak text] _ in
            let sheet = UIActivityViewController(activityItems: ["COD TEXT REFERENCE: Gate 7 at 14:30"], applicationActivities: nil)
            sheet.popoverPresentationController?.sourceView = text
            self?.present(sheet, animated: true)
        }, for: .touchUpInside)
        stack.addArrangedSubview(text)
        let pdf = UIButton(configuration: .filled())
        pdf.setTitle("Open Test PDF In", for: .normal)
        pdf.addAction(UIAction { [weak self, weak pdf] _ in
            guard let self, let pdf else { return }
            var data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 300, height: 400)).pdfData { context in
                for (index, color) in [UIColor.red, UIColor.blue].enumerated() {
                    context.beginPage()
                    color.setFill()
                    context.cgContext.fill(CGRect(x: 0, y: 0, width: 300, height: 400))
                    ("COD PDF PAGE \(index + 1)" as NSString).draw(at: CGPoint(x: 20, y: 80), withAttributes: [
                        .font: UIFont.boldSystemFont(ofSize: 22), .foregroundColor: UIColor.white,
                    ])
                }
            }
            if ProcessInfo.processInfo.arguments.contains("--invalid-pdf") {
                data = Data("This is not a PDF".utf8)
            }
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("CodTwoPages.pdf")
            do { try data.write(to: url, options: .atomic) } catch { return }
            let document = UIDocumentInteractionController(url: url)
            document.uti = "com.adobe.pdf"
            document.delegate = self
            self.document = document
            document.presentOpenInMenu(from: pdf.bounds, in: pdf, animated: true)
        }, for: .touchUpInside)
        stack.addArrangedSubview(pdf)
        let gif = UIButton(configuration: .filled())
        gif.setTitle("Open Test GIF In", for: .normal)
        gif.addAction(UIAction { [weak self, weak gif] _ in
            guard let self, let gif else { return }
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, 2, nil) else { return }
            for color in [UIColor.red, .blue] {
                let format = UIGraphicsImageRendererFormat(); format.scale = 1
                let frame = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 180), format: format).image { context in
                    color.setFill(); context.fill(CGRect(x: 0, y: 0, width: 320, height: 180))
                }
                guard let image = frame.cgImage else { return }
                CGImageDestinationAddImage(destination, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.5]] as CFDictionary)
            }
            guard CGImageDestinationFinalize(destination) else { return }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("CodMotionTest.gif")
            do { try (data as Data).write(to: url, options: .atomic) } catch { return }
            let document = UIDocumentInteractionController(url: url)
            document.uti = UTType.gif.identifier; document.delegate = self; self.document = document
            document.presentOpenInMenu(from: gif.bounds, in: gif, animated: true)
        }, for: .touchUpInside)
        stack.addArrangedSubview(gif)
        let video = UIButton(configuration: .filled())
        video.setTitle("Open Test Video In", for: .normal)
        video.addAction(UIAction { [weak self, weak video] _ in
            guard let self, let video else { return }
            Task { @MainActor in
                do {
                    let url = try await FixtureVideo.make(duration: ProcessInfo.processInfo.arguments.contains("--short-video") ? 3 : 30)
                    let document = UIDocumentInteractionController(url: url)
                    document.uti = "public.mpeg-4"
                    document.delegate = self
                    self.document = document
                    document.presentOpenInMenu(from: video.bounds, in: video, animated: true)
                } catch { video.setTitle("Video fixture failed", for: .normal) }
            }
        }, for: .touchUpInside)
        stack.addArrangedSubview(video)
        let musicButton = UIButton(configuration: .filled())
        musicButton.setTitle("Play Test Music", for: .normal)
        musicButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            do {
                if self.music?.isPlaying == true {
                    self.music?.stop()
                    musicButton.setTitle("Play Test Music", for: .normal)
                    return
                }
                let url = try FixtureMusic.make()
                try AVAudioSession.sharedInstance().setCategory(.playback)
                try AVAudioSession.sharedInstance().setActive(true)
                self.music = try AVAudioPlayer(contentsOf: url)
                self.music?.numberOfLoops = 4
                let started = self.music?.play() == true
                musicButton.setTitle(started ? "Stop Test Music" : "Music playback unavailable", for: .normal)
            } catch { musicButton.setTitle("Music fixture failed", for: .normal) }
        }, for: .touchUpInside)
        stack.addArrangedSubview(musicButton)
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
        ])
    }
    func documentInteractionControllerViewControllerForPreview(_ controller: UIDocumentInteractionController) -> UIViewController { self }
}
