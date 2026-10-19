import SwiftUI

/// The crop surface: a frozen image, a dimmed backdrop, and a rectangle you
/// drag out with your finger. This is the screen Cod lives or dies on.
struct SelectionView: View {
    let image: UIImage
    /// Overrides the user's configured action bar. The share extension uses
    /// this to hide actions it can't perform out of process.
    var availableActions: [SnapAction]?
    /// Vision can push a Share extension over its memory limit on large Photos
    /// assets, so that target disables smart-region scanning.
    var smartRegionsEnabled = true
    var onCancel: () -> Void
    var onAction: (SnapAction, UIImage, CGRect) -> Void

    @EnvironmentObject private var settings: AppSettings

    /// Selection in image *pixel* space. `nil` means "no region drawn yet",
    /// in which case actions operate on the whole image.
    @State private var selection: CGRect?
    @State private var dragMode: DragMode?
    /// View-space point the loupe should follow while dragging.
    @State private var activePoint: CGPoint?
    @State private var smartRegions: [CGRect] = []
    @State private var showSmartRegions = false
    @State private var didHintFade = false

    private let minSelectionPixels: CGFloat = 8
    private let handleHitSlop: CGFloat = 30

    private enum DragMode {
        case creating(anchorPixels: CGPoint)
        case moving(original: CGRect, startPixels: CGPoint)
        case resizing(SelectionHandle, original: CGRect, startPixels: CGPoint)
    }

    var body: some View {
        ZStack {
            // The image goes edge to edge…
            cropSurface
                .ignoresSafeArea()

            // …but the chrome stays inside the safe area, so nothing hides
            // under the Dynamic Island or the home indicator.
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                bottomBar
            }
            .padding(.vertical, 8)
        }
        .background(Color.black.ignoresSafeArea())
        .statusBarHidden()
    }

    private var cropSurface: some View {
        GeometryReader { proxy in
            let g = SelectionGeometry.fit(imageSize: image.pixelSize, in: proxy.size)

            ZStack {
                Color.black

                Image(uiImage: image)
                    .resizable()
                    .frame(width: g.displayRect.width, height: g.displayRect.height)
                    .position(x: g.displayRect.midX, y: g.displayRect.midY)

                dimming(g)

                if showSmartRegions, selection == nil {
                    smartRegionOverlay(g)
                }

                if let selection {
                    selectionChrome(rect: g.viewRect(selection), geometry: g)
                }

                Color.clear
                    .contentShape(Rectangle())
                    .gesture(dragGesture(g))

                if settings.showMagnifier, let activePoint {
                    loupe(at: activePoint, geometry: g, container: proxy.size)
                }

                if selection == nil && !didHintFade {
                    hint
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                        .allowsHitTesting(false)
                }
            }
            .onAppear { loadSmartRegions() }
            .task {
                // Get out of the way on its own if the user is just looking.
                try? await Task.sleep(nanoseconds: 2_600_000_000)
                withAnimation(.easeOut(duration: 0.35)) { didHintFade = true }
            }
        }
    }

    // MARK: - Backdrop

    private func dimming(_ g: SelectionGeometry) -> some View {
        Canvas { context, size in
            var path = Path(CGRect(origin: .zero, size: size))
            if let selection {
                path.addRect(g.viewRect(selection))
            }
            context.fill(
                path,
                with: .color(.black.opacity(selection == nil ? 0.35 : 0.62)),
                style: FillStyle(eoFill: true)
            )
        }
        .allowsHitTesting(false)
    }

    private var hint: some View {
        VStack(spacing: 10) {
            Image(systemName: "hand.draw")
                .font(.system(size: 30, weight: .light))
            Text("Drag to select a region")
                .font(.callout.weight(.medium))
            Text(smartRegionsEnabled && settings.smartRegions && !smartRegions.isEmpty
                 ? "or tap a highlighted block"
                 : "Choose an action below to use the whole image")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.white)
        .padding(.vertical, 20)
        .padding(.horizontal, 26)
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .transition(.opacity)
    }

    // MARK: - Smart regions

    private func smartRegionOverlay(_ g: SelectionGeometry) -> some View {
        ForEach(Array(smartRegions.enumerated()), id: \.offset) { _, region in
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(.white.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .background(RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.06)))
                .frame(width: g.viewRect(region).width, height: g.viewRect(region).height)
                .position(x: g.viewRect(region).midX, y: g.viewRect(region).midY)
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    private func loadSmartRegions() {
        guard smartRegionsEnabled, settings.smartRegions, smartRegions.isEmpty else { return }
        Task {
            let regions = await Recognizer.smartRegions(in: image)
            await MainActor.run {
                smartRegions = regions
                withAnimation(.easeOut(duration: 0.25)) { showSmartRegions = !regions.isEmpty }
            }
        }
    }

    // MARK: - Selection chrome

    private func selectionChrome(rect: CGRect, geometry g: SelectionGeometry) -> some View {
        ZStack {
            Rectangle()
                .strokeBorder(.white, lineWidth: 1)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)

            thirdsGrid(rect: rect)

            ForEach(SelectionHandle.allCases, id: \.self) { handle in
                handleView(handle)
                    .position(handle.point(in: rect))
            }
        }
        .allowsHitTesting(false)
    }

    private func thirdsGrid(rect: CGRect) -> some View {
        Path { path in
            for i in 1..<3 {
                let x = rect.minX + rect.width * CGFloat(i) / 3
                path.move(to: CGPoint(x: x, y: rect.minY))
                path.addLine(to: CGPoint(x: x, y: rect.maxY))
                let y = rect.minY + rect.height * CGFloat(i) / 3
                path.move(to: CGPoint(x: rect.minX, y: y))
                path.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
        }
        .stroke(.white.opacity(dragMode == nil ? 0.15 : 0.35), lineWidth: 0.5)
    }

    @ViewBuilder
    private func handleView(_ handle: SelectionHandle) -> some View {
        if handle.isCorner {
            Circle()
                .fill(.white)
                .frame(width: 13, height: 13)
                .shadow(color: .black.opacity(0.5), radius: 2)
        } else {
            Capsule()
                .fill(.white)
                .frame(
                    width: handle == .top || handle == .bottom ? 26 : 5,
                    height: handle == .top || handle == .bottom ? 5 : 26
                )
                .shadow(color: .black.opacity(0.5), radius: 2)
        }
    }

    // MARK: - Loupe placement

    private func loupe(at point: CGPoint, geometry g: SelectionGeometry, container: CGSize) -> some View {
        let diameter: CGFloat = 112
        let margin: CGFloat = 18
        // Keep the loupe out from under the finger, flipping side/vertical as
        // the drag approaches an edge.
        let preferLeft = point.x > container.width / 2
        let preferBelow = point.y < container.height / 3
        var x = preferLeft ? point.x - diameter / 2 - margin - 30 : point.x + diameter / 2 + margin + 30
        var y = preferBelow ? point.y + diameter / 2 + margin + 30 : point.y - diameter / 2 - margin - 30
        x = min(max(x, diameter / 2 + 8), container.width - diameter / 2 - 8)
        y = min(max(y, diameter / 2 + 60), container.height - diameter / 2 - 140)

        return MagnifierLoupe(image: image, geometry: g, point: point, diameter: diameter)
            .position(x: x, y: y)
            .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Gesture

    private func dragGesture(_ g: SelectionGeometry) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let startPixels = g.pixelPoint(value.startLocation)
                let currentPixels = g.pixelPoint(value.location)

                if dragMode == nil {
                    dragMode = resolveMode(startLocation: value.startLocation, geometry: g, startPixels: startPixels)
                    Haptics.tick()
                    withAnimation(.easeOut(duration: 0.15)) { didHintFade = true }
                }

                switch dragMode {
                case let .creating(anchor):
                    let rect = CGRect.between(anchor, currentPixels)
                        .intersection(g.imageBounds)
                    selection = rect.isNull ? nil : rect
                    activePoint = value.location

                case let .moving(original, start):
                    var rect = original
                    rect.origin.x += currentPixels.x - start.x
                    rect.origin.y += currentPixels.y - start.y
                    selection = rect.clamped(to: g.imageBounds)
                    activePoint = nil

                case let .resizing(handle, original, start):
                    let resized = handle.resized(
                        original,
                        dx: currentPixels.x - start.x,
                        dy: currentPixels.y - start.y
                    )
                    selection = resized.intersection(g.imageBounds)
                    activePoint = g.viewPoint(handle.point(in: resized))

                case .none:
                    break
                }
            }
            .onEnded { value in
                let travelled = hypot(value.translation.width, value.translation.height)
                let wasCreating: Bool
                if case .creating = dragMode { wasCreating = true } else { wasCreating = false }

                dragMode = nil
                withAnimation(.easeOut(duration: 0.18)) { activePoint = nil }

                if travelled < 6 && wasCreating {
                    handleTap(at: value.location, geometry: g)
                    return
                }

                // Discard slivers produced by a stray drag.
                if let current = selection,
                   current.width < minSelectionPixels || current.height < minSelectionPixels {
                    withAnimation(.easeOut(duration: 0.18)) { selection = nil }
                    return
                }
                Haptics.snap()
            }
    }

    private func resolveMode(
        startLocation: CGPoint,
        geometry g: SelectionGeometry,
        startPixels: CGPoint
    ) -> DragMode {
        if let selection {
            let viewRect = g.viewRect(selection)
            // Handles win over the body so a small selection stays resizable.
            for handle in SelectionHandle.allCases {
                let point = handle.point(in: viewRect)
                if hypot(point.x - startLocation.x, point.y - startLocation.y) <= handleHitSlop {
                    return .resizing(handle, original: selection, startPixels: startPixels)
                }
            }
            if viewRect.contains(startLocation) {
                return .moving(original: selection, startPixels: startPixels)
            }
        }
        return .creating(anchorPixels: startPixels.clampedInside(g.imageBounds))
    }

    private func handleTap(at location: CGPoint, geometry g: SelectionGeometry) {
        let pixel = g.pixelPoint(location)

        // Tap a detected block to snap the selection onto it.
        if let region = smartRegions
            .filter({ $0.insetBy(dx: -6, dy: -6).contains(pixel) })
            .min(by: { $0.area < $1.area })
        {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                selection = region.integral.intersection(g.imageBounds)
            }
            Haptics.snap()
            return
        }

        if selection != nil {
            withAnimation(.easeOut(duration: 0.18)) { selection = nil }
            Haptics.tick()
        }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack(spacing: 12) {
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Cancel crop")
            .accessibilityIdentifier("cancel-selection")

            Spacer(minLength: 0)

            readout

            Spacer(minLength: 0)

            Menu {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        selection = CGRect(origin: .zero, size: image.pixelSize)
                    }
                    Haptics.snap()
                } label: { Label("Select whole image", systemImage: "square.dashed.inset.filled") }

                Button {
                    withAnimation(.easeOut(duration: 0.18)) { selection = nil }
                } label: { Label("Clear selection", systemImage: "xmark.square.dashed") }
                    .disabled(selection == nil)

                Toggle(isOn: Binding(
                    get: { showSmartRegions },
                    set: { newValue in withAnimation(.easeOut(duration: 0.2)) { showSmartRegions = newValue } }
                )) {
                    Label("Detected blocks", systemImage: "rectangle.dashed")
                }
                .disabled(smartRegions.isEmpty)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var readout: some View {
        Text(readoutText)
            .font(.system(.footnote, design: .monospaced).weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
            .contentTransition(.numericText())
            .animation(.easeOut(duration: 0.12), value: readoutText)
    }

    private var readoutText: String {
        guard let selection else {
            let size = image.pixelSize
            return "Full · \(Int(size.width)) × \(Int(size.height))"
        }
        let pixels = effectiveCropRect(selection)
        return "\(Int(pixels.width)) × \(Int(pixels.height))"
    }

    private var bottomBar: some View {
        ActionBar(actions: availableActions ?? settings.visibleActions) { action in
            guard let (cropped, rect) = crop() else {
                Haptics.warning()
                return
            }
            onAction(action, cropped, rect)
        }
        .padding(.bottom, 6)
    }

    private func crop() -> (UIImage, CGRect)? {
        let rect = effectiveCropRect(
            selection ?? CGRect(origin: .zero, size: image.pixelSize)
        )
        guard let cropped = image.cropped(toPixelRect: rect) else { return nil }
        return (cropped, rect)
    }

    /// This is the same integral pixel rectangle the cropper consumes. Using
    /// it for the readout and history key keeps the dimensions users see
    /// identical to the image they receive.
    private func effectiveCropRect(_ rect: CGRect) -> CGRect {
        rect.integral.intersection(CGRect(origin: .zero, size: image.pixelSize))
    }
}

private extension CGPoint {
    func clampedInside(_ rect: CGRect) -> CGPoint {
        CGPoint(
            x: Swift.min(Swift.max(x, rect.minX), rect.maxX),
            y: Swift.min(Swift.max(y, rect.minY), rect.maxY)
        )
    }
}
