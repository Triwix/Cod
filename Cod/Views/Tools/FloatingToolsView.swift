import SwiftUI

/// How a PDF floats: one still page, pages you turn with the floating
/// window's skip buttons, or a continuously scrolling range.
enum PDFFloatMode: String, CaseIterable, Identifiable {
  case page, flip, scroll
  var id: String { rawValue }
  var title: String {
    switch self {
    case .page: return "One Page"
    case .flip: return "Flip Pages"
    case .scroll: return "Auto-scroll"
    }
  }
}

struct PDFReferenceView: View {
  private enum PageField: Hashable { case page, first, last }
  let reference: PDFReference
  @EnvironmentObject private var coordinator: CaptureCoordinator
  @Environment(\.dismiss) private var dismiss
  @State private var pageInput = "1"
  @State private var mode: PDFFloatMode
  @State private var flipInterval = 10.0
  @State private var flipShape: FloatWindowShape?
  @State private var flipPreview: UIImage?
  @State private var firstInput = "1"
  @State private var lastInput = "1"
  @State private var speed = 32.0
  @State private var position = 0.0
  @State private var image: UIImage?
  @State private var renderedPageIndex: Int?
  @State private var scrolling: ScrollingReference?
  @State private var preparedRange: PDFScrollRange?
  @State private var preparing = false
  @State private var errorMessage: String?
  @State private var session: FloatingToolSession?
  @FocusState private var focusedPage: PageField?

  init(reference: PDFReference) {
    self.reference = reference
    // A multi-page PDF opens ready to flip through, like a document.
    _mode = State(initialValue: reference.pageCount > 1 ? .flip : .page)
    _lastInput = State(initialValue: String(min(reference.pageCount, Slideshow.maximumImages)))
  }

  private var autoScroll: Bool { mode == .scroll }

  var body: some View {
    FloatingEditorLayout {
      if autoScroll {
        if let scrolling, preparedRange == scrollRange {
          FloatingPreviewImage(
            image: scrolling.frame(
              elapsed: position * scrolling.duration(speed: speed), speed: speed),
            label: "Scrolling PDF preview")
        }
        if preparing { ProgressView("Preparing pages…") }
      } else if mode == .flip {
        if let flipPreview { FloatingPreviewImage(image: flipPreview, label: "First page preview") }
      } else if let image {
        FloatingPreviewImage(image: image, label: "PDF page preview")
      }
      Button {
        focusedPage = nil
        coordinator.prioritizeExplicitInput()
        if autoScroll, let scrolling, preparedRange == scrollRange {
          var config = FloatingToolConfiguration(kind: .document)
          config.text = scrolling.name
          config.duration = scrolling.duration(speed: speed)
          config.scrollSpeed = speed
          let created = FloatingToolSession(configuration: config, document: scrolling)
          session = created
          coordinator.floatTool(created)
        } else if mode == .flip, let range = scrollRange {
          floatPages(range)
        } else if mode == .page, let image {
          guard coordinator.unlocks(.pdf) else { return }
          dismiss()
          coordinator.floatImmediately(image: image, origin: .imported)
        }
      } label: {
        Label(floatTitle, systemImage: "pip.enter")
          .frame(maxWidth: .infinity, minHeight: 36)
      }
      .buttonStyle(CodActionStyle())
      .accessibilityIdentifier(floatIdentifier)
      .disabled(coordinator.isWorking || !canFloat)
      if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
    } settings: {
      Section {
        Picker("Show", selection: $mode) {
          ForEach(PDFFloatMode.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("pdf-mode")
        if mode == .flip {
          pageField("From page", input: $firstInput, focus: .first, identifier: "flip-first-page")
          pageField("To page", input: $lastInput, focus: .last, identifier: "flip-last-page")
          if flipRange == nil {
            Text("Choose 2 to \(Slideshow.maximumImages) pages between 1 and \(reference.pageCount).")
              .foregroundStyle(.red).accessibilityIdentifier("pdf-flip-validation")
          }
        } else if autoScroll {
          pageField("From page", input: $firstInput, focus: .first, identifier: "scroll-first-page")
          pageField("To page", input: $lastInput, focus: .last, identifier: "scroll-last-page")
          if scrollRange == nil {
            Text(
              "Enter a range from 1 to \(reference.pageCount), with the last page after the first."
            )
            .foregroundStyle(.red).accessibilityIdentifier("pdf-range-validation")
          }
          Text(
            "Up to 20 pages within the 24,000-pixel canvas limit. Pages prepare automatically; cropping is available with Auto-scroll off."
          )
          .font(.footnote).foregroundStyle(.secondary)
        } else {
          HStack {
            Text("Page")
            Spacer(minLength: 4)
            TextField("Page number", text: $pageInput).keyboardType(.numberPad)
              .multilineTextAlignment(.trailing).textFieldStyle(.roundedBorder).frame(width: 58)
              .focused($focusedPage, equals: .page)
              .accessibilityLabel("Page number").accessibilityIdentifier("pdf-page-number")
            Text("of \(reference.pageCount)").foregroundStyle(.secondary)
            Stepper(
              "Page",
              value: Binding(get: { selectedPageIndex ?? 0 }, set: { pageInput = String($0 + 1) }),
              in: 0...max(0, reference.pageCount - 1)
            )
            .labelsHidden().fixedSize().accessibilityIdentifier("pdf-page")
            .accessibilityLabel("Change page")
            .accessibilityValue("\((selectedPageIndex ?? 0) + 1) of \(reference.pageCount)")
          }
          if selectedPageIndex == nil {
            Text("Enter a page from 1 to \(reference.pageCount).")
              .foregroundStyle(.red).accessibilityIdentifier("pdf-page-validation")
          }
          Button {
            guard let image else { return }
            coordinator.prioritizeExplicitInput()
            dismiss()
            coordinator.restoreFloatingSelection(image)
          } label: {
            Label("Crop a Region", systemImage: "crop").frame(maxWidth: .infinity, minHeight: 36)
          }
          .buttonStyle(CodActionStyle(emphasis: .secondary)).accessibilityIdentifier("crop-pdf-region").disabled(!canFloat)
          Text("Only the selected page is rendered. Your original PDF isn't changed.")
            .font(.footnote).foregroundStyle(.secondary)
        }
      } header: {
        Text("Pages")
      } footer: {
        if mode == .flip {
          Text("Opens paused on the first page. Use the floating window's skip buttons to go back or forward one page. Press play to turn pages automatically.")
        }
      }
      if mode == .flip {
        Section("Window") {
          FloatWindowShapePicker(selection: Binding(
            get: { flipShape ?? flipPreview.map { FloatWindowShape.closest(to: $0.size) } ?? .tall },
            set: { flipShape = $0 }))
        }
        Section {
          LabeledContent("When playing, next page every", value: "\(Int(flipInterval)) s")
          Slider(value: $flipInterval, in: Slideshow.intervalRange, step: 1)
            .accessibilityLabel("Seconds per page")
        }
      }
      if autoScroll {
        ReferenceScrollOptions(speed: $speed, position: $position, reference: scrolling)
      }
      if let session { Section("Playback") { FloatingToolPlaybackControls(session: session) } }
    }
    .navigationTitle(reference.name).navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } }
      ToolbarItemGroup(placement: .keyboard) {
        Spacer()
        Button("Done") { focusedPage = nil }
      }
    }
    .onChange(of: mode) { _, newMode in
      focusedPage = nil
      errorMessage = nil
      if newMode == .scroll, let page = selectedPageIndex {
        firstInput = String(page + 1)
        lastInput = String(page + 1)
      }
    }
    .task(id: mode == .flip ? firstInput : nil) {
      guard mode == .flip, let first = PDFPageSelection.index(firstInput, count: reference.pageCount) else {
        flipPreview = nil
        return
      }
      flipPreview = try? reference.image(pageIndex: first, maximumEdge: 900)
    }
    .onReceive(
      NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)
    ) { notification in
      guard let field = notification.object as? UITextField,
        ["Page number", "From page", "To page"].contains(field.placeholder ?? ""),
        field.keyboardType == .numberPad
      else { return }
      DispatchQueue.main.async {
        guard field.isFirstResponder else { return }
        field.selectedTextRange = field.textRange(
          from: field.beginningOfDocument, to: field.endOfDocument)
      }
    }
    .task(id: mode == .page ? selectedPageIndex : nil) {
      guard mode == .page, let index = selectedPageIndex else { return }
      do {
        image = try reference.image(pageIndex: index)
        renderedPageIndex = index
        errorMessage = nil
      } catch {
        image = nil
        renderedPageIndex = nil
        errorMessage = error.localizedDescription
      }
    }
    .task(id: autoScroll ? scrollRange : nil) {
      scrolling = nil
      preparedRange = nil
      preparing = false
      guard autoScroll, let range = scrollRange else { return }
      preparing = true
      defer { if !Task.isCancelled { preparing = false } }
      do {
        try await Task.sleep(for: .milliseconds(150))
        let prepared = try ScrollingReference.pdf(reference, first: range.first, last: range.last)
        try Task.checkCancellation()
        scrolling = prepared
        preparedRange = range
        errorMessage = nil
      } catch is CancellationError {} catch { errorMessage = error.localizedDescription }
    }
  }

  private var selectedPageIndex: Int? {
    PDFPageSelection.index(pageInput, count: reference.pageCount)
  }
  private var scrollRange: PDFScrollRange? {
    .init(first: firstInput, last: lastInput, pageCount: reference.pageCount)
  }
  private var flipRange: PDFScrollRange? {
    guard let range = scrollRange, range.last - range.first + 1 >= 2,
      range.last - range.first + 1 <= Slideshow.maximumImages
    else { return nil }
    return range
  }
  private var floatTitle: String {
    switch mode {
    case .page: return "Float Page"
    case .flip: return "Float Pages"
    case .scroll: return "Float Scrolling Pages"
    }
  }
  private var floatIdentifier: String {
    switch mode {
    case .page: return "float-pdf-page"
    case .flip: return "float-pdf-pages"
    case .scroll: return "float-scrolling-reference"
    }
  }

  /// Renders the range as an image set that opens paused; the floating
  /// window's skip buttons then turn one page at a time.
  private func floatPages(_ range: PDFScrollRange) {
    // Ask before rendering pages that couldn't float anyway.
    guard coordinator.unlocks(.pdf) else { return }
    preparing = true
    defer { preparing = false }
    do {
      let pages = try (range.first...range.last).map { number in
        try autoreleasepool { try reference.image(pageIndex: number - 1, maximumEdge: CGFloat(Slideshow.storedEdge)) }
      }
      var config = FloatingToolConfiguration(kind: .slideshow)
      config.slideNames = try Slideshow.store(pages)
      config.slideInterval = flipInterval
      config.startsPaused = true
      config.setName = "\(reference.name) · \(range.first)–\(range.last)"
      config.windowShape = flipShape ?? FloatWindowShape.closest(to: pages[0].size)
      config.interfaceStyle = coordinator.currentInterfaceStyle
      let created = FloatingToolSession(configuration: config)
      session = created
      errorMessage = nil
      coordinator.floatTool(created, feature: .pdf)
    } catch { errorMessage = error.localizedDescription }
  }

  private var canFloat: Bool {
    if mode == .flip { return !preparing && flipRange != nil }
    if autoScroll {
      return !preparing && scrolling != nil && scrollRange != nil && preparedRange == scrollRange
    }
    return image != nil && selectedPageIndex != nil && renderedPageIndex == selectedPageIndex
  }
  private func pageField(
    _ title: String, input: Binding<String>, focus: PageField, identifier: String
  ) -> some View {
    LabeledContent(title) {
      TextField(title, text: input).keyboardType(.numberPad).multilineTextAlignment(.trailing)
        .textFieldStyle(.roundedBorder).frame(width: 80).focused($focusedPage, equals: focus)
        .accessibilityIdentifier(identifier)
    }
  }
}
