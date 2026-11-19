import SwiftUI
import WebKit

/// A small web view for floating a web video: open a link, start the video,
/// then tap Float (or the Float button on the video). WebKit's own Picture in
/// Picture plays it, so the page and its controls behave as in Safari.
/// Keep this screen open while the video floats.
struct WebVideoView: View {
  var initialURL: URL?

  @Environment(\.dismiss) private var dismiss
  @StateObject private var model = WebVideoModel()
  @State private var address = ""
  @FocusState private var editingAddress: Bool

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 12) {
        Button { model.webView.goBack() } label: { Image(systemName: "chevron.backward") }
          .disabled(!model.canGoBack).accessibilityLabel("Back")
        Button { model.webView.goForward() } label: { Image(systemName: "chevron.forward") }
          .disabled(!model.canGoForward).accessibilityLabel("Forward")
        TextField("Paste a video link", text: $address)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .keyboardType(.URL)
          .submitLabel(.go)
          .focused($editingAddress)
          .onSubmit(open)
          .padding(.horizontal, 12).frame(minHeight: 40)
          .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
          .accessibilityIdentifier("web-address")
        if editingAddress || model.url == nil {
          Button("Go", action: open)
            .disabled(WebVideoLink.url(from: address) == nil)
            .accessibilityIdentifier("web-go")
        } else {
          Button { model.webView.reload() } label: { Image(systemName: "arrow.clockwise") }
            .accessibilityLabel("Reload")
        }
      }
      .padding(.horizontal, 16).padding(.vertical, 10)
      if let error = model.error {
        Text(error).font(.footnote).foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.bottom, 8)
          .accessibilityIdentifier("web-error")
      } else if model.url != nil {
        Text("Start the video, then tap Float. Keep this screen open while it floats.")
          .font(.footnote).foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.bottom, 8)
      }
      ZStack {
        WebVideoContainer(model: model)
        if model.url == nil {
          VStack(spacing: 10) {
            Image(systemName: "play.rectangle.on.rectangle").font(.largeTitle).foregroundStyle(.secondary)
            Text("Paste a link to a page with a video, such as YouTube or Vimeo. Start the video, then tap Float.")
              .multilineTextAlignment(.center).foregroundStyle(.secondary)
          }
          .padding(32)
          .accessibilityIdentifier("web-empty")
        }
      }
    }
    .navigationTitle(model.title.isEmpty ? "Web Video" : model.title)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } }
      ToolbarItem(placement: .topBarTrailing) {
        Button { model.floatLargestVideo() } label: { Label("Float", systemImage: "pip.enter") }
          .disabled(model.url == nil)
          .accessibilityIdentifier("web-float")
      }
    }
    .onAppear {
      guard model.url == nil else { return }
      if let initialURL {
        address = initialURL.absoluteString
        model.load(initialURL)
      } else {
        editingAddress = true
      }
    }
    .onChange(of: model.url) { _, url in if let url, !editingAddress { address = url.absoluteString } }
  }

  private func open() {
    guard let url = WebVideoLink.url(from: address) else {
      model.error = "That doesn't look like a web address."
      return
    }
    editingAddress = false
    model.load(url)
  }
}

@MainActor
final class WebVideoModel: NSObject, ObservableObject, WKNavigationDelegate {
  let webView: WKWebView
  @Published var url: URL?
  @Published var title = ""
  @Published var canGoBack = false
  @Published var canGoForward = false
  @Published var error: String?
  private var observations: [NSKeyValueObservation] = []

  override init() {
    let configuration = WKWebViewConfiguration()
    configuration.allowsInlineMediaPlayback = true
    configuration.allowsPictureInPictureMediaPlayback = true
    configuration.websiteDataStore = .nonPersistent()
    if let script = Self.floatButtonScript {
      configuration.userContentController.addUserScript(
        WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
    }
    webView = WKWebView(frame: .zero, configuration: configuration)
    webView.allowsBackForwardNavigationGestures = true
    super.init()
    webView.navigationDelegate = self
    observations = [
      webView.observe(\.url) { [weak self] view, _ in Task { @MainActor in self?.url = view.url ?? self?.url } },
      webView.observe(\.title) { [weak self] view, _ in Task { @MainActor in self?.title = view.title ?? "" } },
      webView.observe(\.canGoBack) { [weak self] view, _ in Task { @MainActor in self?.canGoBack = view.canGoBack } },
      webView.observe(\.canGoForward) { [weak self] view, _ in
        Task { @MainActor in self?.canGoForward = view.canGoForward }
      },
    ]
  }

  /// The Safari extension's content script also adds a Float button over
  /// videos here. It finds no extension storage, so the button stays on.
  static let floatButtonScript: String? = Bundle.main.url(forResource: "content", withExtension: "js")
    .flatMap { try? String(contentsOf: $0, encoding: .utf8) }

  func load(_ url: URL) {
    error = nil
    self.url = url
    webView.load(URLRequest(url: url))
  }

  /// Floats the largest video on the page. WebKit runs app-evaluated scripts
  /// as a user action, which video playback and Picture in Picture require
  /// (checked in the simulator: the video starts; PiP itself needs a phone).
  func floatLargestVideo() {
    let script = """
      (async () => {
        const videos = [...document.querySelectorAll('video')];
        const video = videos.sort((a, b) => {
          const ra = a.getBoundingClientRect(), rb = b.getBoundingClientRect();
          return rb.width * rb.height - ra.width * ra.height;
        })[0];
        if (!video) return 'none';
        if (video.disablePictureInPicture) video.disablePictureInPicture = false;
        if (video.paused) { try { await video.play(); } catch (_) {} }
        if (typeof video.requestPictureInPicture === 'function') { await video.requestPictureInPicture(); }
        else if (typeof video.webkitSetPresentationMode === 'function') { video.webkitSetPresentationMode('picture-in-picture'); }
        else { return 'unsupported'; }
        return 'ok';
      })()
      """
    webView.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { [weak self] result in
      Task { @MainActor in
        switch result {
        case .success(let value as String) where value == "none":
          self?.error = "No video found on this page yet. Start the video, then tap Float."
        case .success(let value as String) where value == "unsupported":
          self?.error = "This video can't float."
        case .failure:
          self?.error = "This site didn't allow the video to float. Try the Float button on the video, or the video's own Picture in Picture button."
        default:
          self?.error = nil
        }
      }
    }
  }

  nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    Task { @MainActor in self.report(error) }
  }

  nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    Task { @MainActor in self.report(error) }
  }

  private func report(_ error: Error) {
    let nsError = error as NSError
    guard nsError.code != NSURLErrorCancelled else { return }
    self.error = error.localizedDescription
  }
}

private struct WebVideoContainer: UIViewRepresentable {
  let model: WebVideoModel
  func makeUIView(context: Context) -> WKWebView { model.webView }
  func updateUIView(_ uiView: WKWebView, context: Context) {}
}
