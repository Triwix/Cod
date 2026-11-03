import SwiftUI

struct SavedReferenceSaveSection: View {
  @State private var name: String
  @State private var id: UUID
  @State private var saved = false
  @State private var error: String?
  let original: UIImage?
  let makeReference: (String, UUID) -> SavedReference
  init(
    name: String, id: UUID?, original: UIImage? = nil,
    makeReference: @escaping (String, UUID) -> SavedReference
  ) {
    _name = State(initialValue: name)
    _id = State(initialValue: id ?? UUID())
    _saved = State(initialValue: id != nil)
    self.original = original
    self.makeReference = makeReference
  }
  var body: some View {
    Section {
      TextField("Reference name", text: $name).accessibilityIdentifier("reference-name")
      Button(saved ? "Update Saved Reference" : "Save Reference") {
        do {
          _ = try SavedReferenceStore.shared.save(makeReference(name, id), original: original, replacingExisting: saved)
          saved = true
          error = nil
        } catch { self.error = error.localizedDescription }
      }.accessibilityIdentifier("save-reference")
        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      if saved {
        Text("Saved in Library → Saved cards & presets.").font(.footnote).foregroundStyle(
          .secondary)
      }
      if let error { Text(error).foregroundStyle(.red) }
    } header: {
      Text("Save for later")
    } footer: {
      Text(
        "Keeps editable content and settings, even with History off. Saved references and Library favorites can be selected in Float Saved Reference Shortcuts, widgets and controls."
      )
    }
  }
}

struct SavedReferencesView: View {
  @StateObject private var store = SavedReferenceStore.shared
  @EnvironmentObject private var coordinator: CaptureCoordinator
  @State private var query = ""
  @State private var error: String?
  var body: some View {
    List {
      if let error = error ?? store.loadError { Text(error).foregroundStyle(.red) }
      if store.items.isEmpty {
        ContentUnavailableView(
          "No saved cards yet", systemImage: "text.book.closed",
          description: Text("Name and save a text card, script or time-tool preset in its editor."))
      }
      ForEach(
        store.items.filter {
          query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)
            || ($0.text?.text ?? $0.tool?.text ?? "").localizedCaseInsensitiveContains(query)
        }
      ) { item in
        NavigationLink {
          SavedReferenceEditor(reference: item)
        } label: {
          VStack(alignment: .leading) {
            Text(item.name)
            Text(item.detail).font(.caption).foregroundStyle(.secondary)
          }
        }
        .accessibilityIdentifier("saved-reference-\(item.id)")
        .swipeActions {
          Button("Delete", role: .destructive) {
            do { try store.delete(item.id) } catch { self.error = error.localizedDescription }
          }
        }
        .contextMenu {
          Button("Float", systemImage: "pip.enter") { coordinator.floatSavedReference(item.id) }
        }
      }
      Section {
        NavigationLink("New Text or Script") { FloatingTextView() }
      }
      Section("Quick launch") {
        Text(
          "In Shortcuts, add Float Saved Reference and choose a card, preset or Library favorite. You can assign that Shortcut to Back Tap or the Action Button."
        )
        Text(
          "On iOS 18 or later, add Cod's Float Saved Reference widget to your Home Screen, or its configurable control in Control Center or while editing Lock Screen controls. Then choose your reference."
        )
        Text(
          "These supported system actions open Cod to start PiP; they may require unlocking. Cod doesn't switch back to another app automatically. Widget labels show names, not the contents of your references."
        )
      }.font(.footnote).foregroundStyle(.secondary)
    }
    .searchable(
      text: $query, placement: .navigationBarDrawer(displayMode: .always),
      prompt: "Search saved content"
    )
    .codFormStyle()
    .navigationTitle("Saved cards & presets").navigationBarTitleDisplayMode(.inline)
  }
}

struct SavedReferenceEditor: View {
  let reference: SavedReference
  var body: some View {
    if let tool = reference.tool, tool.kind != .teleprompter {
      FloatingToolEditor(
        configuration: tool, savedReference: reference,
        originalImage: SavedReferenceStore.shared.original(for: reference))
    } else {
      FloatingTextView(
        savedReference: reference,
        originalImage: SavedReferenceStore.shared.original(for: reference))
    }
  }
}
