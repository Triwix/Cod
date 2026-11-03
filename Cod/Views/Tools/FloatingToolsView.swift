import SwiftUI

struct FloatingToolRows: View {
  var body: some View {
    Section {
      NavigationLink {
        FloatingTextView()
      } label: {
        CodRowLabel("Text", systemImage: "text.alignleft", detail: "Type, paste or read a photo")
      }.accessibilityIdentifier("tool-text")
    } header: {
      Text("Text & reading")
    } footer: {
      Text(
        "Turn on Teleprompter to scroll or show word groups"
      )
    }
    Section {
      ForEach(FloatingToolKind.allCases.filter { $0 != .teleprompter && $0 != .document }) { kind in
        NavigationLink {
          FloatingToolEditor(kind: kind)
        } label: {
          CodRowLabel(kind.title, systemImage: kind.icon)
        }.accessibilityIdentifier("tool-\(kind.rawValue)")
      }
    } header: {
      Text("Time & focus")
    }
  }
}

struct PDFReferenceView: View {
  private enum PageField: Hashable { case page, first, last }
  let reference: PDFReference
  @EnvironmentObject private var coordinator: CaptureCoordinator
  @Environment(\.dismiss) private var dismiss
  @State private var pageInput = "1"
  @State private var autoScroll = false
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
        } else if !autoScroll, let image {
          dismiss()
          coordinator.floatImmediately(image: image, origin: .imported)
        }
      } label: {
        Label(autoScroll ? "Float Scrolling Pages" : "Float Page", systemImage: "pip.enter")
          .frame(maxWidth: .infinity, minHeight: 36)
      }
      .buttonStyle(CodActionStyle())
      .accessibilityIdentifier(autoScroll ? "float-scrolling-reference" : "float-pdf-page")
      .disabled(coordinator.isWorking || !canFloat)
      if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
    } settings: {
      Section("Pages") {
        Toggle("Auto-scroll pages", isOn: $autoScroll).accessibilityIdentifier("auto-scroll-pdf")
        if autoScroll {
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
    .onChange(of: autoScroll) { _, enabled in
      focusedPage = nil
      errorMessage = nil
      if enabled, let page = selectedPageIndex {
        firstInput = String(page + 1)
        lastInput = String(page + 1)
      }
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
    .task(id: autoScroll ? nil : selectedPageIndex) {
      guard !autoScroll, let index = selectedPageIndex else { return }
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
  private var canFloat: Bool {
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
