import SwiftUI

/// What's floating now, with its live value and the controls people reach for.
struct ActiveSessionCard: View {
  @EnvironmentObject private var pip: PiPPinController

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 12) {
        Image(systemName: icon)
          .font(.title3.weight(.medium)).foregroundStyle(Color.codActionBackground)
          .frame(width: 40, height: 40)
          .background(Color.codActionBackground.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 2) {
          Text(title).font(.headline)
          Text(pip.isActive ? "Floating over other apps" : "Opening floating window…")
            .font(.footnote).foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
        if pip.isActive {
          Text("Live")
            .font(.caption2.weight(.bold)).textCase(.uppercase)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(.green).background(.green.opacity(0.15), in: Capsule())
        }
      }
      if let session = pip.toolSession {
        ActiveSessionValue(session: session)
      }
      Text(
        pip.isActive
          ? "Open another app yourself; Cod doesn't switch apps for you. iOS controls the window's size and position."
          : "Keep Cod open while iOS prepares Picture in Picture."
      )
      .font(.footnote).foregroundStyle(.secondary)
      HStack(spacing: 10) {
        if let session = pip.toolSession, session.configuration.kind.showsLiveDate == false {
          ActiveSessionPlayPause(session: session)
        }
        Button("Stop Floating", role: .destructive) { pip.stop() }
          .buttonStyle(CodActionStyle(emphasis: .secondary, compact: true))
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
  }

  private var title: String {
    if let session = pip.toolSession { return session.title }
    if pip.videoReference != nil { return "Video" }
    return "Image"
  }

  private var icon: String {
    if let session = pip.toolSession { return session.configuration.kind.icon }
    if pip.videoReference != nil { return "film" }
    return "photo"
  }
}

private struct ActiveSessionValue: View {
  @ObservedObject var session: FloatingToolSession

  var body: some View {
    TimelineView(.periodic(from: .now, by: 0.5)) { _ in
      let snapshot = session.snapshot
      let value = snapshot.rows.isEmpty ? snapshot.value : snapshot.rows.map { "\($0.label) \($0.value)" }.joined(separator: " · ")
      if session.configuration.kind != .teleprompter, !value.isEmpty {
        Text(value)
          .font(snapshot.rows.isEmpty ? .system(.title, design: .rounded).weight(.semibold).monospacedDigit() : .subheadline.monospacedDigit())
          .lineLimit(2).minimumScaleFactor(0.6)
          .accessibilityIdentifier("active-session-value")
      }
    }
  }
}

private struct ActiveSessionPlayPause: View {
  @ObservedObject var session: FloatingToolSession

  var body: some View {
    Button(session.isPlaying ? "Pause" : "Resume") {
      if session.isPlaying { session.pause() } else { session.resume() }
    }
    .buttonStyle(CodActionStyle(compact: true))
    .disabled(session.isUpdatingAlarm)
    .accessibilityIdentifier("active-session-play-pause")
  }
}

/// Recently floated tools; tap to float again, long-press to edit or remove.
struct RecentFloatsStrip: View {
  @ObservedObject var recents: RecentFloats
  @EnvironmentObject private var coordinator: CaptureCoordinator

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 10) {
        ForEach(recents.forHome) { item in
          Button {
            coordinator.floatRecent(item.configuration)
          } label: {
            HStack(spacing: 10) {
              Image(systemName: item.configuration.kind.icon)
                .font(.body.weight(.medium)).foregroundStyle(Color.codActionBackground)
              VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                if !item.detail.isEmpty {
                  Text(item.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
              }
              Image(systemName: item.isStarred ? "star.fill" : "play.fill").font(.caption)
                .foregroundStyle(item.isStarred ? Color.yellow : Color.secondary)
            }
            .padding(.horizontal, 12).frame(minHeight: 52)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
          }
          .buttonStyle(.plain)
          .disabled(coordinator.isWorking)
          .accessibilityLabel("Float \(item.title) again" + (item.detail.isEmpty ? "" : ", \(item.detail)"))
          .accessibilityIdentifier("recent-\(item.configuration.kind.rawValue)")
          .contextMenu {
            Button("Edit Before Floating", systemImage: "slider.horizontal.3") {
              coordinator.route = .init(kind: .editor(item.configuration))
            }
            Button(item.isStarred ? "Unstar" : "Star", systemImage: item.isStarred ? "star.slash" : "star") {
              recents.toggleStar(item.id)
            }
            Button("Remove from Recents", systemImage: "minus.circle", role: .destructive) {
              recents.remove(item)
            }
          }
        }
      }
      .padding(.vertical, 2)
    }
  }
}

/// A category card: header plus a grid of tool tiles. Tiles keep the
/// `tool-<kind>` identifiers the rest of the app and tests rely on.
struct ToolCategoryCard<Tiles: View>: View {
  let title: String
  let icon: String
  let tint: Color
  var columns = 3
  @ViewBuilder var tiles: () -> Tiles
  @Environment(\.dynamicTypeSize) private var textSize

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label {
        Text(title).font(.headline)
      } icon: {
        Image(systemName: icon).foregroundStyle(tint)
      }
      .accessibilityAddTraits(.isHeader)
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: textSize.isAccessibilitySize ? 1 : columns), spacing: 10) {
        tiles()
      }
    }
    .padding(.vertical, 6)
  }
}

struct ToolTile: View {
  let title: String
  let icon: String
  let tint: Color
  let identifier: String
  /// Shows a Pro badge until Pro is unlocked. Opening the tool stays free.
  var isPro = false
  let action: () -> Void
  @EnvironmentObject private var pro: ProStore

  private var showsBadge: Bool { isPro && !pro.isPro }

  var body: some View {
    Button(action: action) {
      VStack(spacing: 8) {
        Image(systemName: icon)
          .font(.title3.weight(.medium)).foregroundStyle(tint)
          .frame(width: 44, height: 44)
          .background(tint.opacity(0.14), in: Circle())
        Text(title)
          .font(.caption.weight(.semibold)).foregroundStyle(.primary)
          .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
      }
      .frame(maxWidth: .infinity, minHeight: 96)
      .background(Color(.tertiarySystemFill).opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
      .overlay(alignment: .topTrailing) {
        if showsBadge {
          Text("Pro")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .foregroundStyle(Color.codActionBackground)
            .background(Color.codActionBackground.opacity(0.14), in: Capsule())
            .padding(6)
            .accessibilityHidden(true)
        }
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(title)
    .accessibilityValue(showsBadge ? "Pro" : "")
    .accessibilityIdentifier(identifier)
  }
}

/// How to turn on and use the Safari extension.
struct SafariVideoGuide: View {
  var body: some View {
    List {
      Section {
        Label("Float web videos from Safari", systemImage: "safari").font(.title3.weight(.semibold))
        Text("Cod's Safari extension adds a Float button to videos on web pages. Tap it and the video plays in Picture in Picture over other apps.")
          .foregroundStyle(.secondary)
      }
      Section {
        step(1, "Open iPhone **Settings → Apps → Safari → Extensions**.")
        step(2, "Turn on **Float Video with Cod**, then allow it on **All Websites** or the sites you choose.")
        step(3, "In Safari, open a page with a video and tap **Float** on the video.")
      } header: {
        Text("Turn it on once")
      } footer: {
        Text("No Float button? Tap the extensions button in Safari's address bar, choose Float Video with Cod, then Float video on this page.")
      }
      Section {
        Text("Safari runs the floating video, so it keeps playing with the page's own sound and controls. Some sites don't allow Picture in Picture.")
        Text("The extension doesn't read, store or send anything from the pages you visit.")
          .font(.footnote).foregroundStyle(.secondary)
      } header: { Text("Good to know") }
    }
    .codFormStyle()
    .navigationTitle("Web Video")
    .navigationBarTitleDisplayMode(.inline)
  }

  private func step(_ number: Int, _ text: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Text("\(number)").font(.caption.weight(.medium)).monospacedDigit().foregroundStyle(.secondary)
        .frame(minWidth: 24, minHeight: 24).accessibilityHidden(true)
      Text(.init(text)).font(.subheadline)
    }
  }
}
