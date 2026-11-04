import Foundation

enum CropInteractionPolicy {
    static func allowsDoubleTapFloat(actions: [SnapAction], primaryTitle: String?) -> Bool {
        // Custom primary actions, such as applying a video region, still need
        // their explicit confirmation. Hidden Float also hides its gestures.
        primaryTitle == nil && actions.contains(.float)
    }
}
