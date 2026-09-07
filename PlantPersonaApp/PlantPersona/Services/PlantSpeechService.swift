import AVFoundation

@MainActor
final class PlantSpeechService {
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ persona: PlantPersonaMessage) {
        stop()
        let utterance = AVSpeechUtterance(string: persona.message)
        utterance.voice = AVSpeechSynthesisVoice(language: "ar-SA") ?? AVSpeechSynthesisVoice(language: "ar")
        utterance.rate = min(max(persona.voiceRate, 0.35), 0.58)
        utterance.pitchMultiplier = min(max(persona.voicePitch, 0.6), 1.6)
        utterance.volume = 1.0
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }
}
