import AVFoundation
import SwiftUI

/// The actual video layer is visible inline while PiP prepares. Unlike the
/// still-image encoder's throwaway host, this is ordinary video playback UI.
final class FloatingVideoHostView: UIView {
    let poster = UIImageView()
    var playbackLayer: AVPlayerLayer?
    var onReady: (() -> Void)?
    override init(frame: CGRect) {
        super.init(frame: frame)
        poster.contentMode = .scaleAspectFit
        addSubview(poster)
        backgroundColor = .black
        clipsToBounds = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) isn't used") }
    override func layoutSubviews() {
        super.layoutSubviews()
        poster.frame = bounds
        playbackLayer?.frame = bounds
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { onReady?() }
    }
}

struct FloatingVideoHost: UIViewRepresentable {
    let reference: VideoReference
    let pip: PiPPinController
    let onReady: () -> Void
    func makeUIView(context: Context) -> FloatingVideoHostView {
        let view = FloatingVideoHostView()
        view.poster.image = reference.poster
        view.onReady = onReady
        pip.inlineVideoHost = view
        return view
    }
    func updateUIView(_ view: FloatingVideoHostView, context: Context) {
        view.poster.image = reference.poster
        view.onReady = onReady
        pip.inlineVideoHost = view
    }
}
