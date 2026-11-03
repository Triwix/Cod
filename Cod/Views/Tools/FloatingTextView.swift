import PhotosUI
import SwiftUI

struct FloatingTextView: View {
  private struct ImportedPhoto {
    let image: UIImage
    let text: String?
    let warning: String?
  }
  let savedReference: SavedReference?
  private let loadsDraft: Bool
  private let recognizesInitially: Bool
  @EnvironmentObject private var coordinator: CaptureCoordinator
  @Environment(\.dismiss) private var dismiss
  @Environment(\.colorScheme) private var colorScheme
  @State private var draft: TextReferenceDraft
  @State private var originalImage: UIImage?
  @State private var recognizedOriginalText: String?
  @State private var keepImageLayout: Bool
  @State private var selectedPhoto: PhotosPickerItem?
  @State private var pendingPhoto: ImportedPhoto?
  @State private var readingPhoto = false
  @State private var loaded = false
  @State private var preview: UIImage?
  @State private var validation: String?
  @State private var errorMessage: String?
  @State private var confirmsOriginalText = false
  @State private var previousDraft: String?
  @State private var imageScroll: ScrollingReference?
  @State private var imageScrollError: String?
  @State private var position = 0.0
  @State private var session: FloatingToolSession?
  @AppStorage("cod.tools.referenceDraft") private var storedDraft = ""
  @AppStorage("cod.tools.referenceDraftMigrated") private var migratedDraft = false
  @AppStorage("cod.tools.referencePrompter") private var storedPrompter = false
  @AppStorage("cod.tools.prompterCountdown") private var countdown = true
  @AppStorage("cod.tools.prompterDelay") private var delay = 3

  init(
    initialText: String = "", savedReference: SavedReference? = nil, originalImage: UIImage? = nil,
    recognizedOriginalText: String? = nil, teleprompter: Bool = false,
    keepImageLayout: Bool = false,
    recognizeInitially: Bool = false
  ) {
    self.savedReference = savedReference
    loadsDraft = savedReference == nil && originalImage == nil && initialText.isEmpty
    recognizesInitially = recognizeInitially
    _draft = State(
      initialValue: .init(text: initialText, saved: savedReference, teleprompter: teleprompter))
    _originalImage = State(initialValue: originalImage)
    _recognizedOriginalText = State(initialValue: recognizedOriginalText)
    _keepImageLayout = State(initialValue: keepImageLayout)
  }

  var body: some View {
    FloatingEditorLayout {
      if let preview {
        FloatingPreviewImage(
          image: preview,
          label: draft.teleprompterEnabled ? "Tool preview" : "Floating text preview")
      }
      if readingPhoto { ProgressView("Preparing photo text…") }
      if let validation { Text(validation).foregroundStyle(.secondary) }
      Button {
        startFloating()
      } label: {
        Label(
          usesImageLayout
            ? "Float Scrolling Image"
            : draft.teleprompterEnabled ? "Float Teleprompter" : "Float Text",
          systemImage: "pip.enter"
        )
        .frame(maxWidth: .infinity, minHeight: 36)
      }
      .buttonStyle(CodActionStyle())
      .accessibilityIdentifier(
        usesImageLayout
          ? "float-scrolling-reference" : draft.teleprompterEnabled ? "float-tool" : "float-text"
      )
      .disabled(preview == nil || coordinator.isWorking || readingPhoto)
      if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
    } settings: {
      Section {
        Toggle("Teleprompter", isOn: $draft.teleprompterEnabled).accessibilityIdentifier(
          "text-teleprompter")
        if draft.teleprompterEnabled, originalImage != nil {
          Toggle("Keep original image layout", isOn: $keepImageLayout).accessibilityIdentifier(
            "text-image-layout")
        }
      } footer: {
        Text(
          usesImageLayout
            ? "Scrolls the photo itself. Text edits and colors don't change its contents."
            : "Off floats a still text card. On exposes scrolling, word presentation and playback settings."
        )
      }
      Section("Text") {
        PhotosPicker(
          selection: $selectedPhoto, matching: .images, preferredItemEncoding: .current,
          photoLibrary: .shared()
        ) {
          Label("Import Photo", systemImage: "text.viewfinder")
        }.accessibilityIdentifier("read-photo-text").disabled(readingPhoto)
        if !usesImageLayout {
          ExampleTextEditor(
            text: $draft.configuration.text, sample: draft.sample, label: "Text to float",
            identifier: "floating-text-editor"
          )
          .disabled(readingPhoto || usesImageLayout)
          HStack(spacing: 12) {
            PasteButton(payloadType: String.self) { values in
              if let value = values.first { draft.configuration.text = value }
            }
            .disabled(readingPhoto || usesImageLayout)
            Spacer()
            Button("Clear") { draft.configuration.text = "" }.disabled(
              draft.configuration.text.isEmpty || usesImageLayout
            )
            .accessibilityIdentifier("clear-text")
            .frame(minHeight: 44)
          }
          if !legacyDrafts.isEmpty {
            Menu("Earlier drafts") {
              ForEach(legacyDrafts, id: \.name) { item in
                Button(item.name) { previousDraft = item.text }
              }
            }
          }
          Text(
            "Leave this empty to float the example. Import Photo reads editable text; Teleprompter can scroll it or preserve the photo's layout."
          )
          .font(.caption).foregroundStyle(.secondary)
          Text("\(draft.configuration.text.count) / \(draft.maximumCharacters) characters").font(
            .caption
          ).foregroundStyle(.secondary).monospacedDigit()
        } else {
          Text(
            "Scrolling the original photo. Turn off Keep original image layout to edit and present its text instead."
          )
          .font(.caption).foregroundStyle(.secondary)
        }
      }
      if draft.teleprompterEnabled {
        if usesImageLayout {
          ReferenceScrollOptions(
            speed: $draft.configuration.scrollSpeed, position: $position, reference: imageScroll)
        } else {
          TeleprompterOptions(configuration: $draft.configuration)
        }
      }
      if !usesImageLayout {
        Section("Readability") {
          FloatingAppearancePicker(
            palette: $draft.configuration.palette, customColors: $draft.configuration.customColors)
          LabeledContent("Text size", value: "\(Int(draft.configuration.fontSize))")
          Slider(value: $draft.configuration.fontSize, in: 28...72, step: 4).accessibilityLabel(
            "Text size")
        }
      }
      if let originalImage {
        Section("Original") {
          DisclosureGroup("Compare with original image") {
            Image(uiImage: originalImage).resizable().scaledToFit().frame(maxHeight: 360)
              .accessibilityLabel("Original image")
          }
          Button("Join Wrapped Lines") {
            draft.configuration.text = RecognizedReferenceText.reflow(draft.configuration.text)
          }
          .disabled(usesImageLayout)
          if recognizedOriginalText != nil {
            Button("Restore Recognized Text & Line Breaks") { confirmsOriginalText = true }
              .disabled(usesImageLayout)
          } else {
            Button("Read Text from Image") {
              Task { await readPhoto(originalImage, confirm: false) }
            }.disabled(readingPhoto)
          }
          Text(
            "Recognition can misread numbers and characters. Check important details against the original."
          )
          .font(.footnote).foregroundStyle(.secondary)
        }
      }
      SavedReferenceSaveSection(
        name: savedReference?.name ?? "", id: savedReference?.id, original: originalImage
      ) { name, id in
        draft.saved(name: name, id: id, originalFilename: savedReference?.originalFilename)
      }.disabled(usesImageLayout)
      if usesImageLayout {
        Text(
          "Named cards save editable text and script settings. Use an image favorite in Library to reuse the original photo."
        )
        .font(.footnote).foregroundStyle(.secondary)
      }
      if let session { Section("Playback") { FloatingToolPlaybackControls(session: session) } }
      Section {
        Text(
          "For shared text, select text → Share → Cod, then open Cod or tap its optional notification. A configured Shortcut can use Float Text With Cod with Shortcut Input. Your image Shortcut is unchanged."
        )
      }
    }
    .navigationTitle("Text").navigationBarTitleDisplayMode(.inline)
    .scrollDismissesKeyboard(.interactively)
    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } } }
    .confirmationDialog(
      "Replace your edited text with the original text recognition?",
      isPresented: $confirmsOriginalText, titleVisibility: .visible
    ) {
      Button("Restore Recognized Text", role: .destructive) {
        if let text = recognizedOriginalText { draft.configuration.text = text }
      }
    }
    .confirmationDialog(
      "Replace the text and source photo in this editor?",
      isPresented: Binding(get: { pendingPhoto != nil }, set: { if !$0 { pendingPhoto = nil } }),
      titleVisibility: .visible
    ) {
      Button("Replace", role: .destructive) {
        if let pendingPhoto { apply(pendingPhoto) }
        pendingPhoto = nil
      }
    }
    .confirmationDialog(
      "Replace the current text with an earlier draft?",
      isPresented: Binding(get: { previousDraft != nil }, set: { if !$0 { previousDraft = nil } }),
      titleVisibility: .visible
    ) {
      Button("Load Draft", role: .destructive) {
        if let previousDraft { draft.configuration.text = previousDraft }
        previousDraft = nil
      }
    }
    .task {
      guard !loaded else { return }
      loaded = true
      if loadsDraft {
        if !migratedDraft {
          storedDraft = legacyText.isEmpty ? legacyScript : legacyText
          storedPrompter = legacyText.isEmpty && !legacyScript.isEmpty
          migratedDraft = true
        }
        draft.configuration.text = storedDraft
        draft.teleprompterEnabled = storedPrompter
      }
      if savedReference?.tool == nil {
        draft.configuration.prompterCountdownEnabled = countdown
        draft.configuration.prompterCountdownSeconds = delay
      }
      prepareImage()
      updatePreview()
      if recognizesInitially, let originalImage { await readPhoto(originalImage, confirm: false) }
    }
    .task(id: selectedPhoto) {
      guard let selectedPhoto else { return }
      coordinator.prioritizeExplicitInput()
      readingPhoto = true
      defer {
        if self.selectedPhoto == selectedPhoto {
          self.selectedPhoto = nil
          readingPhoto = false
        }
      }
      do {
        let data = try await selectedPhoto.loadTransferable(type: Data.self)
        try Task.checkCancellation()
        let image = try VisualFileImport.image(from: data)
        await readPhoto(
          image,
          confirm: !draft.configuration.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
      } catch { if !Task.isCancelled { errorMessage = ImportRecovery.message(for: error) } }
    }
    .onChange(of: draft) { _, value in
      if loaded, value.configuration.text.count <= 20_000 {
        storedDraft = value.configuration.text
        storedPrompter = value.teleprompterEnabled
      }
      countdown = value.configuration.prompterCountdownEnabled
      delay = value.configuration.prompterCountdownSeconds
      updatePreview()
    }
    .onChange(of: keepImageLayout) { _, _ in
      if usesImageLayout { errorMessage = nil }
      updatePreview()
    }
    .onChange(of: position) { _, _ in updatePreview() }
    .onChange(of: colorScheme) { _, _ in updatePreview() }
  }

  private var usesImageLayout: Bool {
    draft.teleprompterEnabled && keepImageLayout && originalImage != nil
  }
  private var style: UIUserInterfaceStyle { colorScheme == .dark ? .dark : .light }
  private var legacyText: String {
    UserDefaults.standard.string(forKey: "cod.tools.textDraft") ?? ""
  }
  private var legacyScript: String {
    let text = UserDefaults.standard.string(forKey: "cod.tools.scriptDraft") ?? ""
    return UserDefaults.standard.bool(forKey: "cod.tools.didSeedScript")
      && text == FloatingToolConfiguration.exampleScript ? "" : text
  }
  private var legacyDrafts: [(name: String, text: String)] {
    [("Previous text draft", legacyText), ("Previous script draft", legacyScript)]
      .filter { !$0.1.isEmpty && $0.1 != draft.configuration.text }
  }
  private func prepareImage() {
    imageScroll = nil
    imageScrollError = nil
    if let originalImage {
      do { imageScroll = try ScrollingReference(images: [originalImage]) } catch {
        imageScrollError = error.localizedDescription
      }
    }
  }
  private func updatePreview() {
    do {
      if usesImageLayout {
        guard let imageScroll else {
          preview = nil
          validation = imageScrollError
          return
        }
        preview = imageScroll.frame(
          elapsed: position * imageScroll.duration(speed: draft.configuration.scrollSpeed),
          speed: draft.configuration.scrollSpeed)
      } else if draft.teleprompterEnabled {
        let config = draft.prepared(for: style)
        try config.validate()
        preview = FloatingToolRenderer.render(
          configuration: config, elapsed: config.prompterStartDelay, date: .now)
      } else {
        preview = try draft.stillImage(for: style)
      }
      validation = nil
    } catch {
      preview = nil
      validation = error.localizedDescription
    }
  }
  private func startFloating() {
    guard let preview else { return }
    coordinator.prioritizeExplicitInput()
    if usesImageLayout, let imageScroll {
      var config = FloatingToolConfiguration(kind: .document)
      config.text = imageScroll.name
      config.scrollSpeed = draft.configuration.scrollSpeed
      config.duration = imageScroll.duration(speed: config.scrollSpeed)
      let created = FloatingToolSession(configuration: config, document: imageScroll)
      session = created
      coordinator.floatTool(created)
    } else if draft.teleprompterEnabled {
      let created = FloatingToolSession(configuration: draft.prepared(for: style))
      session = created
      coordinator.floatTool(created)
    } else {
      dismiss()
      coordinator.floatImmediately(image: preview, origin: .imported)
    }
  }
  private func readPhoto(_ image: UIImage, confirm: Bool) async {
    readingPhoto = true
    defer { readingPhoto = false }
    var text: String?
    var warning: String?
    do {
      let result = try await Recognizer.recognizeText(
        in: image, accuracy: .accurate, usesLanguageCorrection: false)
      if !result.isEmpty {
        text = result.text
      } else {
        warning =
          "No text found. You can still turn on Teleprompter and Keep original image layout to scroll this photo."
      }
    } catch { warning = error.localizedDescription }
    guard !Task.isCancelled else { return }
    let value = ImportedPhoto(image: image, text: text, warning: warning)
    if confirm { pendingPhoto = value } else { apply(value) }
  }
  private func apply(_ photo: ImportedPhoto) {
    originalImage = photo.image
    recognizedOriginalText = photo.text
    if let text = photo.text { draft.configuration.text = RecognizedReferenceText.reflow(text) }
    errorMessage = photo.warning
    prepareImage()
    updatePreview()
  }
}
