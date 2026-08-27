// Builds the 1024×1024 app icon from a source drawing.
//
// Handles the two things that make hand-made icons look wrong: the artwork
// sitting off-centre inside a lot of empty space, and the background surviving
// as a white rectangle. The background is removed by flood-filling inwards from
// the edges, so enclosed white areas (the fish's eye) are preserved, then the
// remaining artwork is trimmed to its true bounds and centred.
//
//   swift Tools/makeicon.swift <source-image> <output.png>

import AppKit

let arguments = CommandLine.arguments
guard arguments.count > 2,
      let source = NSImage(contentsOfFile: arguments[1]),
      let sourceRef = source.cgImage(forProposedRect: nil, context: nil, hints: nil)
else {
    print("usage: swift makeicon.swift <source-image> <output.png>")
    exit(1)
}

let width = sourceRef.width
let height = sourceRef.height

// Read the source into a raw RGBA buffer.
var pixels = [UInt8](repeating: 0, count: width * height * 4)
guard let readContext = CGContext(
    data: &pixels,
    width: width, height: height,
    bitsPerComponent: 8, bytesPerRow: width * 4,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { exit(1) }
readContext.draw(sourceRef, in: CGRect(x: 0, y: 0, width: width, height: height))

func isBackground(_ index: Int) -> Bool {
    let r = Int(pixels[index]), g = Int(pixels[index + 1]), b = Int(pixels[index + 2])
    let a = Int(pixels[index + 3])
    return a < 12 || (r > 233 && g > 233 && b > 233)
}

// Flood fill from every edge pixel; anything reachable is background.
var isOutside = [Bool](repeating: false, count: width * height)
var stack: [Int] = []

for x in 0..<width {
    stack.append(x)
    stack.append((height - 1) * width + x)
}
for y in 0..<height {
    stack.append(y * width)
    stack.append(y * width + width - 1)
}

while let point = stack.popLast() {
    guard !isOutside[point], isBackground(point * 4) else { continue }
    isOutside[point] = true
    let x = point % width, y = point / width
    if x > 0 { stack.append(point - 1) }
    if x < width - 1 { stack.append(point + 1) }
    if y > 0 { stack.append(point - width) }
    if y < height - 1 { stack.append(point + width) }
}

// Punch out the background and find what's left.
var minX = width, minY = height, maxX = -1, maxY = -1
for y in 0..<height {
    for x in 0..<width {
        let point = y * width + x
        if isOutside[point] {
            pixels[point * 4 + 3] = 0
        } else {
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
    }
}

guard maxX >= minX, maxY >= minY else {
    print("nothing left after removing the background")
    exit(1)
}

let artWidth = maxX - minX + 1
let artHeight = maxY - minY + 1
print("artwork bounds: \(artWidth)×\(artHeight) at (\(minX),\(minY)) of \(width)×\(height)")

guard let cleaned = readContext.makeImage(),
      let cropped = cleaned.cropping(to: CGRect(x: minX, y: minY, width: artWidth, height: artHeight))
else { exit(1) }

// Compose onto the icon canvas.
let side = 1024
guard let canvas = CGContext(
    data: nil,
    width: side, height: side,
    bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else { exit(1) }

// Water-blue gradient, tying into the app's accent colour.
let colorSpace = CGColorSpaceCreateDeviceRGB()
let gradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [
        CGColor(red: 0.36, green: 0.74, blue: 0.99, alpha: 1),
        CGColor(red: 0.11, green: 0.42, blue: 0.75, alpha: 1),
    ] as CFArray,
    locations: [0, 1]
)!
canvas.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: side),
    end: CGPoint(x: 0, y: 0),
    options: []
)

// Fit the artwork into the safe area and centre it exactly.
let inset: CGFloat = 0.76
let maxSide = CGFloat(side) * inset
let scale = min(maxSide / CGFloat(artWidth), maxSide / CGFloat(artHeight))
let drawWidth = CGFloat(artWidth) * scale
let drawHeight = CGFloat(artHeight) * scale
let drawRect = CGRect(
    x: (CGFloat(side) - drawWidth) / 2,
    y: (CGFloat(side) - drawHeight) / 2,
    width: drawWidth,
    height: drawHeight
)

canvas.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: CGColor(gray: 0, alpha: 0.28))
canvas.draw(cropped, in: drawRect)

guard let output = canvas.makeImage() else { exit(1) }
let destination = URL(fileURLWithPath: arguments[2])
let rep = NSBitmapImageRep(cgImage: output)
guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
try data.write(to: destination)
print("wrote \(destination.path) (\(side)×\(side))")
