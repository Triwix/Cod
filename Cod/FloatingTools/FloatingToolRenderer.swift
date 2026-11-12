import UIKit

/// Rasterizes tool content into real, timestamped video frames. No custom
/// views or controls are inserted into the system's PiP window.
enum FloatingToolRenderer {
  static let size = CGSize(width: 960, height: 540)

  struct ScriptLayout {
    let text: NSAttributedString
    let travel: CGFloat
    let words: WordPresentation
    let lines: LinePresentation
    let margin: CGFloat
    private let storage: NSTextStorage
    private let manager: NSLayoutManager
    private let container: NSTextContainer
    init(_ configuration: FloatingToolConfiguration) {
      margin = configuration.sideMargin
      let wordCount = configuration.text.split(whereSeparator: \.isWhitespace).count
      let pace = configuration.safeTargetReadingDuration.map { Double(max(1, wordCount)) * 60 / $0 } ?? configuration.wordsPerMinute
      words = WordPresentation(
        text: configuration.text, groupSize: configuration.wordsAtATime, wordsPerMinute: pace)
      lines = LinePresentation(text: configuration.text, wordsPerMinute: pace)
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
      switch configuration.prompterMode {
      case .words: return max(1, words.duration)
      case .lines: return max(1, lines.duration)
      case .scroll: return max(1, Double(travel) / configuration.scrollSpeed)
      }
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
        if configuration.prompterMode == .lines {
          drawLines(layout.lines.frame(at: scriptElapsed), configuration: configuration)
          return
        }
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
        if configuration.kind == .slideshow {
          drawSlide(configuration: configuration, elapsed: elapsed, snapshot: snapshot)
          return
        }
        if !snapshot.rows.isEmpty {
          drawRows(snapshot, configuration: configuration)
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

  /// Current line large and centered, the next lines dimmer below, and a
  /// position counter at the bottom.
  private static func drawLines(_ frame: LinePresentation.Frame, configuration: FloatingToolConfiguration) {
    let color = configuration.colors.foreground
    let margin = CGFloat(configuration.sideMargin)
    let width = size.width - margin * 2
    func paragraph() -> NSMutableParagraphStyle {
      let style = NSMutableParagraphStyle()
      style.alignment = .center
      style.lineBreakMode = .byWordWrapping
      return style
    }
    func fitted(_ text: String, size start: CGFloat, weight: UIFont.Weight, alpha: CGFloat, maxHeight: CGFloat)
      -> (NSAttributedString, CGFloat)
    {
      var fontSize = start
      while true {
        let attributed = NSAttributedString(
          string: text,
          attributes: [
            .font: UIFont.systemFont(ofSize: fontSize, weight: weight),
            .foregroundColor: color.withAlphaComponent(alpha), .paragraphStyle: paragraph(),
          ])
        let height = ceil(attributed.boundingRect(
          with: CGSize(width: width, height: .greatestFiniteMagnitude),
          options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height)
        if height <= maxHeight || fontSize <= 18 { return (attributed, min(height, maxHeight)) }
        fontSize -= 2
      }
    }
    let base = CGFloat(configuration.fontSize) * 1.5
    let current = fitted(frame.current, size: base, weight: .semibold, alpha: 1, maxHeight: 250)
    let upcoming = frame.upcoming.enumerated().map { offset, line in
      fitted(line, size: base * 0.62, weight: .medium, alpha: offset == 0 ? 0.55 : 0.32, maxHeight: 80)
    }
    let gap: CGFloat = 18
    let total = current.1 + upcoming.reduce(0) { $0 + $1.1 + gap }
    var y = max(40, (size.height - 60 - total) / 2)
    current.0.draw(with: CGRect(x: margin, y: y, width: width, height: current.1),
      options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
    y += current.1 + gap
    for (text, height) in upcoming {
      text.draw(with: CGRect(x: margin, y: y, width: width, height: height),
        options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
      y += height + gap
    }
    if frame.count > 0 {
      draw("\(frame.index + 1)/\(frame.count)", in: CGRect(x: 40, y: size.height - 62, width: size.width - 80, height: 40),
        size: 26, weight: .medium, color: color.withAlphaComponent(0.5), monospaced: true)
    }
  }

  /// A label/value table for World Clock and System Monitor.
  private static func drawRows(_ snapshot: FloatingToolSnapshot, configuration: FloatingToolConfiguration) {
    let color = configuration.colors.foreground
    let rows = snapshot.rows
    let rowHeight = min(130, (size.height - 80) / CGFloat(max(1, rows.count)))
    let fontSize = min(64, rowHeight * 0.5)
    var y = (size.height - rowHeight * CGFloat(rows.count)) / 2
    for (index, row) in rows.enumerated() {
      if index > 0 {
        color.withAlphaComponent(0.14).setFill()
        UIRectFillUsingBlendMode(CGRect(x: 56, y: y, width: size.width - 112, height: 2), .normal)
      }
      let labelFont = UIFont.systemFont(ofSize: fontSize * 0.72, weight: .medium)
      let noteFont = UIFont.systemFont(ofSize: fontSize * 0.42, weight: .regular)
      let valueFont = UIFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold)
      let hasNote = !row.note.isEmpty
      let labelY = y + (rowHeight - labelFont.lineHeight - (hasNote ? noteFont.lineHeight : 0)) / 2
      (row.label as NSString).draw(
        in: CGRect(x: 64, y: labelY, width: size.width * 0.5, height: labelFont.lineHeight + 4),
        withAttributes: [.font: labelFont, .foregroundColor: color.withAlphaComponent(0.8)])
      if hasNote {
        (row.note as NSString).draw(
          in: CGRect(x: 64, y: labelY + labelFont.lineHeight, width: size.width * 0.5, height: noteFont.lineHeight + 4),
          withAttributes: [.font: noteFont, .foregroundColor: color.withAlphaComponent(0.55)])
      }
      let right = NSMutableParagraphStyle()
      right.alignment = .right
      (row.value as NSString).draw(
        in: CGRect(x: size.width * 0.4, y: y + (rowHeight - valueFont.lineHeight) / 2, width: size.width * 0.6 - 64, height: valueFont.lineHeight + 4),
        withAttributes: [.font: valueFont, .foregroundColor: color, .paragraphStyle: right])
      y += rowHeight
    }
  }

  /// One image of a set, fitted inside the frame, with a small position badge.
  private static func drawSlide(configuration: FloatingToolConfiguration, elapsed: TimeInterval, snapshot: FloatingToolSnapshot) {
    let names = configuration.slideNames
    guard !names.isEmpty else { return }
    let index = Slideshow.index(elapsed: elapsed, interval: configuration.slideInterval, count: names.count)
    if let image = Slideshow.image(named: names[index]) {
      let pixels = image.pixelSize
      let scale = min(size.width / max(1, pixels.width), size.height / max(1, pixels.height))
      let fitted = CGSize(width: pixels.width * scale, height: pixels.height * scale)
      image.draw(in: CGRect(
        x: (size.width - fitted.width) / 2, y: (size.height - fitted.height) / 2,
        width: fitted.width, height: fitted.height))
    }
    let badge = CGRect(x: size.width - 150, y: size.height - 62, width: 126, height: 42)
    UIColor.black.withAlphaComponent(0.45).setFill()
    UIBezierPath(roundedRect: badge, cornerRadius: 21).fill()
    draw("\(index + 1)/\(names.count)", in: badge.insetBy(dx: 4, dy: 5), size: 26, weight: .semibold,
      color: .white, monospaced: true)
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
