import SwiftUI

enum PinAction {
    case copyImage
    case copyText
    case save
    case share
    case sendToPiP
    case recrop
}

/// Hosts every floating snippet above the rest of the app. The overlay itself
/// is transparent to touches — only the pin cards take input.
struct PinOverlay: View {
    @ObservedObject var manager: PinManager
    var onAction: (PinAction, Pin) -> Void

    var body: some View {
        GeometryReader { proxy in
            ForEach(manager.pins) { pin in
                PinCard(
                    pin: pin,
                    bounds: proxy.size,
                    isFocused: manager.focusedID == pin.id,
                    onAction: onAction
                )
                .environmentObject(manager)
            }
        }
        .ignoresSafeArea()
    }
}

private struct PinCard: View {
    let pin: Pin
    let bounds: CGSize
    let isFocused: Bool
    var onAction: (PinAction, Pin) -> Void

    @EnvironmentObject private var manager: PinManager
    @EnvironmentObject private var settings: AppSettings

    @GestureState private var dragTranslation: CGSize = .zero
    @GestureState private var pinchScale: CGFloat = 1
    @State private var gripWidth: CGFloat?

    private var liveWidth: CGFloat {
        let base = gripWidth ?? pin.width
        return max(60, min(base * pinchScale, 1200))
    }

    private var liveHeight: CGFloat { liveWidth / max(pin.aspect, 0.05) }

    private var liveCenter: CGPoint {
        CGPoint(
            x: pin.center.x + dragTranslation.width,
            y: pin.center.y + dragTranslation.height
        )
    }

    var body: some View {
        Group {
            if pin.isCollapsed {
                collapsedChip
            } else {
                expandedCard
            }
        }
        .position(liveCenter)
    }

    // MARK: - Expanded

    private var expandedCard: some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: pin.image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: liveWidth, height: liveHeight)
                .clipShape(RoundedRectangle(cornerRadius: settings.pinCornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: settings.pinCornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.22), lineWidth: 0.5)
                )
                .shadow(
                    color: (settings.pinShadow.color ?? .clear).opacity(settings.pinShadow == .none ? 0 : 0.45),
                    radius: isFocused ? 18 : 11,
                    y: isFocused ? 7 : 4
                )
                .opacity(pin.opacity)

            closeButton

            resizeGrip
                .frame(width: liveWidth, height: liveHeight, alignment: .bottomTrailing)
        }
        .frame(width: liveWidth, height: liveHeight)
        .contentShape(RoundedRectangle(cornerRadius: settings.pinCornerRadius, style: .continuous))
        .gesture(dragGesture.simultaneously(with: pinchGesture))
        .onTapGesture(count: 2) { manager.toggleCollapsed(pin.id) }
        .onTapGesture { manager.bringToFront(pin.id) }
        .contextMenu { menuItems }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: pin.isCollapsed)
    }

    private var closeButton: some View {
        Button {
            manager.remove(pin.id)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(.black.opacity(0.62), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isFocused ? 1 : 0.55)
        .accessibilityLabel("Close pin")
        .accessibilityHint("Removes this pin from Cod without deleting its saved history image.")
    }

    private var resizeGrip: some View {
        Image(systemName: "arrow.down.right")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(.black.opacity(0.62), in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
            .opacity(isFocused ? 1 : 0.55)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .accessibilityLabel("Resize pin")
            .accessibilityValue("\(Int(pin.width)) points wide")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: manager.setWidth(pin.width + 24, for: pin.id)
                case .decrement: manager.setWidth(pin.width - 24, for: pin.id)
                @unknown default: break
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        // Diagonal drag: use the dominant axis so the gesture
                        // feels predictable on very wide or very tall snippets.
                        let delta = (value.translation.width + value.translation.height) / 2
                        gripWidth = max(60, min(pin.width + delta * 2, 1200))
                    }
                    .onEnded { _ in
                        if let width = gripWidth { manager.setWidth(width, for: pin.id) }
                        gripWidth = nil
                        Haptics.tick()
                    }
            )
    }

    // MARK: - Collapsed

    private var collapsedChip: some View {
        HStack(spacing: 7) {
            Image(uiImage: pin.image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 26, height: 26)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.black.opacity(0.7), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
        .contentShape(Capsule())
        .gesture(dragGesture)
        .onTapGesture { manager.toggleCollapsed(pin.id) }
        .contextMenu { menuItems }
    }

    // MARK: - Gestures

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .updating($dragTranslation) { value, state, _ in
                state = value.translation
            }
            .onChanged { _ in
                if manager.focusedID != pin.id { manager.bringToFront(pin.id) }
            }
            .onEnded { value in
                let proposed = CGPoint(
                    x: pin.center.x + value.translation.width,
                    y: pin.center.y + value.translation.height
                )
                manager.setCenter(clamped(proposed), for: pin.id)
                Haptics.tick()
            }
    }

    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .updating($pinchScale) { value, state, _ in state = value }
            .onEnded { value in
                manager.setWidth(pin.width * value, for: pin.id)
                Haptics.tick()
            }
    }

    /// Keeps a decent grab handle on screen so a pin can never be lost.
    private func clamped(_ point: CGPoint) -> CGPoint {
        let insetX = min(liveWidth / 2, 44)
        let insetY = min(liveHeight / 2, 44)
        return CGPoint(
            x: min(max(point.x, insetX), bounds.width - insetX),
            y: min(max(point.y, insetY), bounds.height - insetY)
        )
    }

    // MARK: - Menu

    @ViewBuilder
    private var menuItems: some View {
        Button { onAction(.copyImage, pin) } label: { Label("Copy Image", systemImage: "doc.on.doc") }
        Button { onAction(.copyText, pin) } label: { Label("Copy Text", systemImage: "text.viewfinder") }
        Button { onAction(.save, pin) } label: { Label("Save to Photos", systemImage: "square.and.arrow.down") }
        Button { onAction(.share, pin) } label: { Label("Share", systemImage: "square.and.arrow.up") }
        Divider()
        Button { onAction(.sendToPiP, pin) } label: {
            Label("Float Over Other Apps", systemImage: "pip.enter")
        }
        Button { manager.toggleCollapsed(pin.id) } label: {
            Label(pin.isCollapsed ? "Expand" : "Collapse", systemImage: pin.isCollapsed ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left")
        }
        Divider()
        Button(role: .destructive) { manager.remove(pin.id) } label: {
            Label("Close Pin", systemImage: "xmark")
        }
    }
}
