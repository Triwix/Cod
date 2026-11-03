import AVFoundation

/// Deliberately audible playback in a separate simulator test app, not a
/// silent-audio keepalive and never part of the shipped Cod target.
enum FixtureMusic {
    static func make() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("CodAudioTest.caf")
        let format = AVAudioFormat(standardFormatWithSampleRate: 22_050, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 22_050 * 90)!
        buffer.frameLength = buffer.frameCapacity
        let values = buffer.floatChannelData![0]
        for index in 0..<Int(buffer.frameLength) {
            values[index] = Float(0.08 * sin(2 * Double.pi * 220 * Double(index) / 22_050))
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }
}
