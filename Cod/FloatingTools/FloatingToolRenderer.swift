import UIKit

/// Rasterizes tool content into real, timestamped video frames. No custom
/// views or controls are inserted into the system's PiP window.
enum FloatingToolRenderer {
  static let size = CGSize(width: 960, height: 540)

  struct ScriptLayout {
    let text: NSAttributedString
    let travel: CGFloat
    let words: WordPresentation
    let margin: CGFloat
    private let storage: NSTextStorage
    private let manager: NSLayoutManager
    private let container: NSTextContainer
    init(_ configuration: FloatingToolConfiguration) {
      margin = configuration.sideMargin
      let wordCount = configuration.text.split(whereSeparator: \.isWhitespace).count
      words = WordPresentation(
        text: configuration.text, groupSize: configuration.wordsAtATime,
        wordsPerMinute: configuration.safeTargetReadingDuration.map { Double(wordCount) * 60 / $0 } ?? configuration.wordsPerMinute)
      text = FloatingToolRenderer.script(configuration)
      storage = NSTextStorage(attributedString: text)
      manager = NSLayoutManager()
      container = NSTextContainer(size: CGSize(width: size.width - margin * 2, height: .greatestFiniteMagnitude))
      container.lineFragmentPadding = 0
      manager.addTextContainer(container)
      storage.addLayoutManager(manager)
      manager.ensureLayout(for: container)
      travel = max(0, ceil(manager.usedRect(for: container).height) - (size.height - 96))
    }

    func drawVisibleText(offset: CGFloat, in context: CGContext) {
      let viewport = CGRect(x: 0, y: offset, width: size.width - margin * 2, height: size.height - 96)
      let glyphs = manager.glyphRange(forBoundingRect: viewport, in: container)
      context.saveGState()
      context.clip(to: CGRect(x: margin, y: 48, width: viewport.width, height: viewport.height))
      // Fractional translation avoids rounding the text's origin into steps.
      // Reuse layout and rasterize only visible glyphs, even for long scripts.
      context.translateBy(x: margin, y: 48 - offset)
      manager.drawBackground(forGlyphRange: glyphs, at: .zero)
      manager.drawGlyphs(forGlyphRange: glyphs, at: .zero)
      context.restoreGState()
    }

    func duration(_ configuration: FloatingToolConfiguration) -> TimeInterval {
      if let target = configuration.safeTargetReadingDuration { return target }
      return configuration.prompterMode == .words
        ? max(1, words.duration)
        : max(1, Double(travel) / configuration.scrollSpeed)
    }
  }

  static func script(_ configuration: FloatingToolConfiguration) -> NSAttributedString {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = configuration.lineSpacing
    return NSAttributedString(
      string: configuration.text,
      attributes: [
        .font: UIFont.systemFont(ofSize: configuration.fontSize, weight: .medium),
        .foregroundColor: configuration.colors.foreground,
        .paragraphStyle: paragraph,
      ])
  }

  static func scriptTravel(_ configuration: FloatingToolConfiguration) -> CGFloat {
    ScriptLayout(configuration).travel
  }

  static func render(
    configuration: FloatingToolConfiguration, elapsed: TimeInterval, date: Date,
    scriptLayout: ScriptLayout? = nil
  ) -> UIImage {
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    format.opaque = true
    let snapshot = configuration.snapshot(elapsed: elapsed, date: date)
    return UIGraphicsImageRenderer(size: size, format: format).image { context in
      configuration.colors.background.setFill()
      context.fill(CGRect(origin: .zero, size: size))
      if configuration.kind == .teleprompter {
        let layout = scriptLayout ?? ScriptLayout(configuration)
        let delay = configuration.prompterStartDelay
        if elapsed < delay {
          draw(
            "Starting in", in: CGRect(x: 40, y: 110, width: 880, height: 70),
            size: 44, weight: .medium, color: configuration.colors.foreground)
          draw(
            String(Int(ceil(delay - max(0, elapsed)))),
            in: CGRect(x: 40, y: 200, width: 880, height: 190),
            size: 150, weight: .semibold, color: configuration.colors.foreground, monospaced: true)
          return
        }
        let scriptElapsed = max(0, elapsed - delay)
        if configuration.prompterMode == .words {
          context.cgContext.saveGState()
          context.cgContext.clip(
            to: CGRect(x: 48, y: 48, width: size.width - 96, height: size.height - 96))
          drawWords(layout.words.chunk(at: scriptElapsed), configuration: configuration)
          context.cgContext.restoreGState()
          return
        }
        let travel = layout.travel
        let speed = configuration.safeTargetReadingDuration.map { Double(travel) / $0 } ?? configuration.scrollSpeed
        let offset = min(travel, CGFloat(scriptElapsed * speed))
        if configuration.readingGuide {
          // Blend onto the opaque background; renderer-context fill defaults
          // to copy blending, which can turn this into an opaque black bar.
          context.cgContext.saveGState()
          context.cgContext.setBlendMode(.normal)
          configuration.colors.foreground.withAlphaComponent(0.10).setFill()
          context.cgContext.fill(CGRect(x: layout.margin, y: 100, width: size.width - layout.margin * 2, height: configuration.fontSize * 1.4))
          configuration.colors.foreground.withAlphaComponent(0.65).setFill()
          context.cgContext.fill(CGRect(x: layout.margin - 12, y: 100, width: 4, height: configuration.fontSize * 1.4))
          context.cgContext.restoreGState()
        }
        layout.drawVisibleText(offset: offset, in: context.cgContext)
      } else {
        if configuration.kind == .clock {
          drawClock(snapshot, configuration: configuration)
          return
        }
        if let progress = snapshot.progress {
          let ring = CGRect(x: 253, y: 43, width: 454, height: 454)
          let center = CGPoint(x: ring.midX, y: ring.midY)
          let radius = ring.width / 2
          let start = -CGFloat.pi / 2
          let track = UIBezierPath(ovalIn: ring)
          track.lineWidth = 14
          configuration.colors.foreground.withAlphaComponent(0.18).setStroke()
          track.stroke()
          if progress > 0 {
            let arc = UIBezierPath(
              arcCenter: center, radius: radius, startAngle: start,
              endAngle: start + .pi * 2 * min(1, max(0, progress)), clockwise: true)
            arc.lineWidth = 14
            arc.lineCapStyle = .round
            configuration.colors.foreground.setStroke()
            arc.stroke()
          }
          draw(
            snapshot.title, in: CGRect(x: 300, y: 130, width: 360, height: 55),
            size: 40, weight: .medium, color: configuration.colors.foreground)
          draw(
            snapshot.value, in: CGRect(x: 290, y: 211, width: 380, height: 110),
            size: 96, weight: .semibold, color: configuration.colors.foreground, monospaced: true)
          draw(
            snapshot.detail, in: CGRect(x: 310, y: 345, width: 340, height: 55),
            size: 32, weight: .regular, color: configuration.colors.foreground)
          return
        }
        draw(
          snapshot.title, in: CGRect(x: 40, y: 65, width: 880, height: 65),
          size: 44, weight: .medium, color: configuration.colors.foreground)
        draw(
          snapshot.value, in: CGRect(x: 30, y: 174, width: 900, height: 140),
          size: configuration.kind == .clock ? 100 : 118, weight: .semibold,
          color: configuration.colors.foreground, monospaced: true)
        draw(
          snapshot.detail, in: CGRect(x: 40, y: 365, width: 880, height: 65),
          size: 36, weight: .regular, color: configuration.colors.foreground)
      }
    }
  }

  private static func drawClock(
    _ snapshot: FloatingToolSnapshot, configuration: FloatingToolConfiguration
  ) {
    var lines: [(String, CGFloat, UIFont.Weight, Bool)] = []
    if configuration.showsClockLocation {
      lines.append((snapshot.title, CGFloat(configuration.clockLocationSize), .medium, false))
    }
    lines.append((snapshot.value, CGFloat(configuration.clockTimeSize), .semibold, true))
    if configuration.showsClockDate {
      lines.append((snapshot.detail, CGFloat(configuration.clockDateSize), .regular, false))
    }
    let gap: CGFloat = 30
    let naturalHeight =
      lines.reduce(CGFloat(0)) { $0 + $1.1 * 1.3 } + gap * CGFloat(lines.count - 1)
    let scale = min(1, (size.height - 96) / naturalHeight)
    var y = (size.height - naturalHeight * scale) / 2
    for (text, fontSize, weight, monospaced) in lines {
      let height = fontSize * 1.3 * scale
      draw(
        text, in: CGRect(x: 40, y: y, width: size.width - 80, height: height),
        size: fontSize * scale, weight: weight, color: configuration.colors.foreground,
        monospaced: monospaced)
      y += height + gap * scale
    }
  }

  private static func drawWords(_ text: String, configuration: FloatingToolConfiguration) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineBreakMode = .byWordWrapping
    let rect = CGRect(x: configuration.sideMargin, y: 48, width: size.width - configuration.sideMargin * 2, height: size.height - 96)
    var fontSize = CGFloat(configuration.fontSize) * 2
    var attributed: NSAttributedString
    var measured: CGRect
    repeat {
      attributed = NSAttributedString(
        string: text,
        attributes: [
          .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
          .foregroundColor: configuration.colors.foreground, .paragraphStyle: paragraph,
        ])
      measured = attributed.boundingRect(
        with: CGSize(width: rect.width, height: .greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
      if measured.height <= rect.height, measured.width <= rect.width { break }
      fontSize -= 2
    } while fontSize > 12
    attributed.draw(
      with: CGRect(
        x: rect.minX, y: rect.midY - min(measured.height, rect.height) / 2, width: rect.width,
        height: rect.height), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
  }

  private static func draw(
    _ text: String, in rect: CGRect, size: CGFloat, weight: UIFont.Weight, color: UIColor,
    monospaced: Bool = false
  ) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    // Shrink only as needed for long city names, AM/PM or elapsed hours.
    var font =
      monospaced
      ? UIFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
      : UIFont.systemFont(ofSize: size, weight: weight)
    let measured = (text as NSString).size(withAttributes: [.font: font]).width
    if measured > rect.width {
      let fitted = max(24, size * rect.width / measured)
      font =
        monospaced
        ? .monospacedDigitSystemFont(ofSize: fitted, weight: weight)
        : .systemFont(ofSize: fitted, weight: weight)
    }
    (text as NSString).draw(
      in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
  }
}
