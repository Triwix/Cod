import UIKit

/// Rasterizes tool content into real, timestamped video frames. No custom
/// views or controls are inserted into the system's PiP window.
enum FloatingToolRenderer {
  /// The original wide canvas. Other window shapes use
  /// `FloatWindowShape.size`, with layouts scaled from this design size.
  static let size = FloatWindowShape.wide.size

  struct ScriptLayout {
    let text: NSAttributedString
    let travel: CGFloat
    let words: WordPresentation
    let lines: LinePresentation
    let margin: CGFloat
    let canvas: CGSize
    private let storage: NSTextStorage
    private let manager: NSLayoutManager
    private let container: NSTextContainer
    init(_ configuration: FloatingToolConfiguration) {
      margin = configuration.sideMargin
      let canvas = configuration.windowShape.size
      self.canvas = canvas
      let wordCount = configuration.text.split(whereSeparator: \.isWhitespace).count
      let pace = configuration.safeTargetReadingDuration.map { Double(max(1, wordCount)) * 60 / $0 } ?? configuration.wordsPerMinute
      words = WordPresentation(
        text: configuration.text, groupSize: configuration.wordsAtATime, wordsPerMinute: pace)
      lines = LinePresentation(text: configuration.text, wordsPerMinute: pace)
      text = FloatingToolRenderer.script(configuration)
      storage = NSTextStorage(attributedString: text)
      manager = NSLayoutManager()
      container = NSTextContainer(size: CGSize(width: canvas.width - margin * 2, height: .greatestFiniteMagnitude))
      container.lineFragmentPadding = 0
      manager.addTextContainer(container)
      storage.addLayoutManager(manager)
      manager.ensureLayout(for: container)
      travel = max(0, ceil(manager.usedRect(for: container).height) - (canvas.height - 96))
    }

    func drawVisibleText(offset: CGFloat, in context: CGContext) {
      let viewport = CGRect(x: 0, y: offset, width: canvas.width - margin * 2, height: canvas.height - 96)
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
    scriptLayout: ScriptLayout? = nil, metrics: SystemMetrics? = nil
  ) -> UIImage {
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    format.opaque = true
    let snapshot = configuration.snapshot(elapsed: elapsed, date: date, metrics: metrics)
    let size = configuration.windowShape.size
    // Fonts and fixed spacing scale with the shorter side, relative to the
    // original 960 × 540 design; narrow shapes also shrink text to fit.
    let unit = min(size.width / 960, size.height / 540, 1) * 0.5 + min(size.width, size.height) / 540 * 0.5
    return UIGraphicsImageRenderer(size: size, format: format).image { context in
      configuration.colors.background.setFill()
      context.fill(CGRect(origin: .zero, size: size))
      if configuration.kind == .teleprompter {
        let layout = scriptLayout ?? ScriptLayout(configuration)
        let delay = configuration.prompterStartDelay
        if elapsed < delay {
          let top = (size.height - 280 * unit) / 2
          draw(
            "Starting in", in: CGRect(x: 40, y: top, width: size.width - 80, height: 70 * unit),
            size: 44 * unit, weight: .medium, color: configuration.colors.foreground)
          draw(
            String(Int(ceil(delay - max(0, elapsed)))),
            in: CGRect(x: 40, y: top + 90 * unit, width: size.width - 80, height: 190 * unit),
            size: 150 * unit, weight: .semibold, color: configuration.colors.foreground, monospaced: true)
          return
        }
        let scriptElapsed = max(0, elapsed - delay)
        if configuration.prompterMode == .lines {
          drawLines(layout.lines.frame(at: scriptElapsed), configuration: configuration, canvas: size)
          return
        }
        if configuration.prompterMode == .words {
          context.cgContext.saveGState()
          context.cgContext.clip(
            to: CGRect(x: 48, y: 48, width: size.width - 96, height: size.height - 96))
          drawWords(layout.words.chunk(at: scriptElapsed), configuration: configuration, canvas: size)
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
          drawClock(snapshot, configuration: configuration, canvas: size)
          return
        }
        if configuration.kind == .slideshow {
          drawSlide(configuration: configuration, elapsed: elapsed, snapshot: snapshot, canvas: size)
          return
        }
        if !snapshot.rows.isEmpty {
          drawRows(snapshot, configuration: configuration, canvas: size)
          return
        }
        if let progress = snapshot.progress {
          // 454 of 540 in the original design: the ring keeps that share of
          // the shorter side and its text scales with it.
          let diameter = min(size.width, size.height) * 0.84
          let ring = CGRect(
            x: (size.width - diameter) / 2, y: (size.height - diameter) / 2,
            width: diameter, height: diameter)
          let k = diameter / 454
          let center = CGPoint(x: ring.midX, y: ring.midY)
          let radius = ring.width / 2
          let start = -CGFloat.pi / 2
          let track = UIBezierPath(ovalIn: ring)
          track.lineWidth = 14 * k
          configuration.colors.foreground.withAlphaComponent(0.18).setStroke()
          track.stroke()
          if progress > 0 {
            let arc = UIBezierPath(
              arcCenter: center, radius: radius, startAngle: start,
              endAngle: start + .pi * 2 * min(1, max(0, progress)), clockwise: true)
            arc.lineWidth = 14 * k
            arc.lineCapStyle = .round
            configuration.colors.foreground.setStroke()
            arc.stroke()
          }
          draw(
            snapshot.title,
            in: CGRect(x: center.x - 180 * k, y: ring.minY + 87 * k, width: 360 * k, height: 55 * k),
            size: 40 * k, weight: .medium, color: configuration.colors.foreground)
          draw(
            snapshot.value,
            in: CGRect(x: center.x - 190 * k, y: ring.minY + 168 * k, width: 380 * k, height: 110 * k),
            size: 96 * k, weight: .semibold, color: configuration.colors.foreground, monospaced: true)
          draw(
            snapshot.detail,
            in: CGRect(x: center.x - 170 * k, y: ring.minY + 302 * k, width: 340 * k, height: 55 * k),
            size: 32 * k, weight: .regular, color: configuration.colors.foreground)
          return
        }
        // Title, value and detail as one block, centered for any shape.
        let valueSize: CGFloat = configuration.kind == .speedometer ? 170 : 118
        let heights = [65 * unit, valueSize * 1.19 * unit, 65 * unit]
        let gap = 44 * unit
        var y = (size.height - heights.reduce(0, +) - gap * 2) / 2
        draw(
          snapshot.title, in: CGRect(x: 40, y: y, width: size.width - 80, height: heights[0]),
          size: 44 * unit, weight: .medium, color: configuration.colors.foreground)
        y += heights[0] + gap
        draw(
          snapshot.value, in: CGRect(x: 30, y: y, width: size.width - 60, height: heights[1]),
          size: valueSize * unit, weight: .semibold,
          color: configuration.colors.foreground, monospaced: true)
        y += heights[1] + gap
        draw(
          snapshot.detail, in: CGRect(x: 40, y: y, width: size.width - 80, height: heights[2]),
          size: 36 * unit, weight: .regular, color: configuration.colors.foreground)
      }
    }
  }

  private static func drawClock(
    _ snapshot: FloatingToolSnapshot, configuration: FloatingToolConfiguration, canvas size: CGSize
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
    // Narrow shapes shrink the clock to fit their width as well as height.
    let scale = min(1, (size.height - 96) / naturalHeight, size.width / 960 + 0.25)
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
  private static func drawLines(
    _ frame: LinePresentation.Frame, configuration: FloatingToolConfiguration, canvas size: CGSize
  ) {
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
    let current = fitted(frame.current, size: base, weight: .semibold, alpha: 1, maxHeight: size.height * 0.46)
    // Tall shapes have room for more of the upcoming lines.
    let room = max(1, Int((size.height - 60 - current.1) / 100))
    let upcoming = frame.upcoming.prefix(room).enumerated().map { offset, line in
      fitted(line, size: base * 0.62, weight: .medium, alpha: offset == 0 ? 0.55 : 0.32, maxHeight: max(80, size.height * 0.16))
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
  private static func drawRows(
    _ snapshot: FloatingToolSnapshot, configuration: FloatingToolConfiguration, canvas size: CGSize
  ) {
    let color = configuration.colors.foreground
    let rows = snapshot.rows
    // Many readings in a wide window read better as two columns.
    let columns = rows.count > 5 && size.width > size.height * 1.1 ? 2 : 1
    let perColumn = Int(ceil(Double(rows.count) / Double(columns)))
    let columnWidth = size.width / CGFloat(columns)
    let rowHeight = min(130, (size.height - 80) / CGFloat(max(1, perColumn)))
    let fontSize = min(64, rowHeight * 0.5, columnWidth / 9)
    let top = (size.height - rowHeight * CGFloat(perColumn)) / 2
    for (index, row) in rows.enumerated() {
      let column = index / perColumn
      let inset = CGFloat(column) * columnWidth
      let width = columnWidth
      let y = top + rowHeight * CGFloat(index % perColumn)
      if index % perColumn > 0 {
        color.withAlphaComponent(0.14).setFill()
        UIRectFillUsingBlendMode(CGRect(x: inset + 56, y: y, width: width - 112, height: 2), .normal)
      }
      let margin: CGFloat = columns == 2 ? 40 : 64
      let labelFont = UIFont.systemFont(ofSize: fontSize * 0.72, weight: .medium)
      let noteFont = UIFont.systemFont(ofSize: fontSize * 0.42, weight: .regular)
      let hasNote = !row.note.isEmpty
      let labelY = y + (rowHeight - labelFont.lineHeight - (hasNote ? noteFont.lineHeight : 0)) / 2
      let labelWidth = min(width * 0.5, ceil((row.label as NSString).size(withAttributes: [.font: labelFont]).width))
      (row.label as NSString).draw(
        in: CGRect(x: inset + margin, y: labelY, width: width * 0.5, height: labelFont.lineHeight + 4),
        withAttributes: [.font: labelFont, .foregroundColor: color.withAlphaComponent(0.8)])
      if hasNote {
        (row.note as NSString).draw(
          in: CGRect(x: inset + margin, y: labelY + labelFont.lineHeight, width: width * 0.5, height: noteFont.lineHeight + 4),
          withAttributes: [.font: noteFont, .foregroundColor: color.withAlphaComponent(0.55)])
      }
      // The value takes the rest of the row and shrinks rather than clipping.
      let available = width - margin * 2 - labelWidth - 16
      var valueFont = UIFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold)
      let natural = (row.value as NSString).size(withAttributes: [.font: valueFont]).width
      if natural > available, available > 0 {
        valueFont = .monospacedDigitSystemFont(ofSize: max(14, fontSize * available / natural), weight: .semibold)
      }
      let right = NSMutableParagraphStyle()
      right.alignment = .right
      (row.value as NSString).draw(
        in: CGRect(
          x: inset + width - margin - available, y: y + (rowHeight - valueFont.lineHeight) / 2,
          width: available, height: valueFont.lineHeight + 4),
        withAttributes: [.font: valueFont, .foregroundColor: color, .paragraphStyle: right])
    }
  }

  /// One image of a set, fitted inside the frame, with a small position badge.
  private static func drawSlide(
    configuration: FloatingToolConfiguration, elapsed: TimeInterval, snapshot: FloatingToolSnapshot,
    canvas size: CGSize
  ) {
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

  private static func drawWords(_ text: String, configuration: FloatingToolConfiguration, canvas size: CGSize) {
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
