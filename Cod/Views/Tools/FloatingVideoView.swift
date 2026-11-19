import AVKit
import SwiftUI

struct FloatingVideoView: View {
  let reference: VideoReference
  var autoFloat = false
  @EnvironmentObject private var coordinator: CaptureCoordinator
  @EnvironmentObject private var pip: PiPPinController
  @Environment(\.dismiss) private var dismiss
  @State private var sound = false
  @State private var repeats = FloatingVideoPlayback.defaultRepeats
  @State private var autoStarted = false
  @State private var cropped: VideoReference?
  @State private var selectingCrop = false
  @State private var isCropping = false
  @State private var cropError: String?
  @State private var cropTask: Task<Void, Never>?
  @State private var speed: Float = 1
  @State private var usesSection = false
  @State private var sectionStart: Double = 0
  @State private var sectionEnd: Double = 0
  private var activeReference: VideoReference { cropped ?? reference }
  private var duration: Double { max(0, activeReference.duration) }
  private var options: FloatingVideoOptions {
    FloatingVideoOptions(
      speed: speed,
      section: usesSection ? FloatingVideoOptions.clampedSection(sectionStart...max(sectionStart, sectionEnd), duration: duration) : nil)
  }

  var body: some View {
    FloatingEditorLayout {
      VideoPreview(reference: activeReference, pip: pip) {
        guard autoFloat, !autoStarted else { return }
        autoStarted = true
        Task { @MainActor in coordinator.floatVideo(activeReference, sound: sound, repeats: repeats, options: options) }
      }.id(activeReference.id)
      Button {
        coordinator.floatVideo(activeReference, sound: sound, repeats: repeats, options: options)
      } label: {
        Label("Float Video", systemImage: "pip.enter").frame(maxWidth: .infinity, minHeight: 36)
      }
      .buttonStyle(CodActionStyle())
      .disabled(coordinator.isWorking || isCropping).accessibilityIdentifier("float-video")
      if isCropping { ProgressView("Preparing cropped video…") }
      if let cropError { Text(cropError).foregroundStyle(.red) }
      if pip.isActive, pip.videoReference?.id == activeReference.id {
        Button("Stop Floating", role: .destructive) { pip.stop() }
          .accessibilityIdentifier("stop-video-float")
      }
      if pip.status == .unsupported {
        Text("Picture in Picture isn't available on this device.").foregroundStyle(.secondary)
      } else if case .failed(let message) = pip.status {
        Text(message).foregroundStyle(.secondary)
      }
    } settings: {
      Section {
        Picker("Speed", selection: $speed) {
          ForEach(FloatingVideoOptions.speeds, id: \.self) { Text(FloatingVideoOptions.speedTitle($0)).tag($0) }
        }
        .accessibilityIdentifier("video-speed")
        if duration > FloatingVideoOptions.minimumSection * 2 {
          Toggle("Play one section", isOn: $usesSection).accessibilityIdentifier("video-section")
          if usesSection {
            LabeledContent("Start", value: FloatingToolConfiguration.time(sectionStart, roundingUp: false))
            Slider(value: $sectionStart, in: 0...(duration - FloatingVideoOptions.minimumSection))
              .accessibilityLabel("Section start")
              .accessibilityIdentifier("video-section-start")
            LabeledContent("End", value: FloatingToolConfiguration.time(sectionEnd, roundingUp: true))
            Slider(value: $sectionEnd, in: FloatingVideoOptions.minimumSection...duration)
              .accessibilityLabel("Section end")
              .accessibilityIdentifier("video-section-end")
          }
        }
      } header: {
        Text("Playback")
      } footer: {
        Text("Speed changes right away while floating. A section plays from Start to End; with Repeat on it repeats just that part. Section changes apply the next time you float.")
      }
      Section {
        Button("Crop Video Region", systemImage: "crop") { selectingCrop = true }
          .disabled(coordinator.isWorking || isCropping || pip.isActive).accessibilityIdentifier("crop-video-region")
        if cropped != nil { Button("Reset to Original Video") { cropped = nil }.disabled(pip.isActive || coordinator.isWorking) }
        Toggle("Video sound", isOn: $sound)
        Toggle("Repeat video", isOn: $repeats).accessibilityIdentifier("video-repeat")
        Text("Duration: \(FloatingToolConfiguration.time(activeReference.duration, roundingUp: true))")
        #if DEBUG && targetEnvironment(simulator)
          if pip.videoReference?.id == reference.id {
            Text("Completed repeats: \(pip.completedVideoLoops)")
              .accessibilityIdentifier("video-repeat-count")
          }
        #endif
      } footer: {
        Text(
          "Repeat is on for newly opened videos. Turn it off to finish at the end. Native pause and seeking controls remain available. Sound is off initially so your music can continue."
        )
      }
    }
    .navigationTitle(reference.name).navigationBarTitleDisplayMode(.inline)
    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } } }
    .onChange(of: sound) { _, value in pip.setVideoSound(value, for: activeReference.id) }
    .onChange(of: repeats) { _, value in pip.setVideoRepeats(value, for: activeReference.id) }
    .onChange(of: speed) { _, value in pip.setVideoSpeed(value, for: activeReference.id) }
    .onChange(of: sectionStart) { _, value in
      if sectionEnd < value + FloatingVideoOptions.minimumSection {
        sectionEnd = min(duration, value + FloatingVideoOptions.minimumSection)
      }
    }
    .onChange(of: sectionEnd) { _, value in
      if sectionStart > value - FloatingVideoOptions.minimumSection {
        sectionStart = max(0, value - FloatingVideoOptions.minimumSection)
      }
    }
    .onAppear { if sectionEnd == 0 { sectionEnd = duration } }
    .fullScreenCover(isPresented: $selectingCrop) {
      SelectionView(image: activeReference.poster, availableActions: [.float], smartRegionsEnabled: false,
        onCancel: { selectingCrop = false }, onAction: { _, _, rect in
          let source = activeReference
          let region = CGRect(x: rect.minX / source.poster.pixelSize.width, y: rect.minY / source.poster.pixelSize.height,
                              width: rect.width / source.poster.pixelSize.width, height: rect.height / source.poster.pixelSize.height)
          selectingCrop = false; isCropping = true; cropError = nil
          cropTask = Task { @MainActor in
            defer { isCropping = false }
            do { cropped = try await VideoRegionCrop.crop(source, region: region) }
            catch { if !Task.isCancelled { cropError = error.localizedDescription } }
          }
        }, primaryTitle: "Apply Crop")
    }
    .onDisappear {
      if !selectingCrop { cropTask?.cancel() }
      if pip.videoReference?.id == activeReference.id, pip.status.isBusy { pip.stop() }
    }
  }
}

private struct VideoPreview: View {
  let reference: VideoReference
  let pip: PiPPinController
  let onReady: () -> Void
  @Environment(\.floatingPreviewHeight) private var height

  var body: some View {
    FloatingVideoHost(reference: reference, pip: pip, onReady: onReady)
      .aspectRatio(
        reference.poster.size.width / max(1, reference.poster.size.height), contentMode: .fit
      )
      .frame(maxHeight: height)
      .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
      .accessibilityLabel("Video preview")
  }
}
