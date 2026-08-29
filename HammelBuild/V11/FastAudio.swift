import Foundation

extension AppModel {
    /// Kept for compatibility with the existing quick-actions UI.
    /// The previous implementation used stereo center cancellation and did not
    /// actually separate vocals from music. Route it to the bundled HTDemucs
    /// CoreML model so every existing call now performs real source separation.
    func separateCenterAudioFast(from item: LocalMedia, keepVoice: Bool) async {
        await separateWithDemucs(from: item, keepVoice: keepVoice)
    }
}
