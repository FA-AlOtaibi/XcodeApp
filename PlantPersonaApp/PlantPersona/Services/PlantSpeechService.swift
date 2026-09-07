import AVFoundation
import Foundation

@MainActor
final class PlantSpeechService: ObservableObject {
    enum Style: String, CaseIterable, Identifiable {
        case natural = "طبيعي"
        case calm = "هادي"
        case playful = "مرح"
        case dramatic = "درامي"
        case tiny = "صغير"

        var id: String { rawValue }
        var rate: Float {
            switch self {
            case .natural: return 1.0
            case .calm: return 0.88
            case .playful: return 1.08
            case .dramatic: return 0.82
            case .tiny: return 1.12
            }
        }
        var pitch: Float {
            switch self {
            case .natural: return 1.0
            case .calm: return 0.92
            case .playful: return 1.12
            case .dramatic: return 0.82
            case .tiny: return 1.28
            }
        }
        var icon: String {
            switch self {
            case .natural: return "waveform"
            case .calm: return "moon.stars.fill"
            case .playful: return "sparkles"
            case .dramatic: return "theatermasks.fill"
            case .tiny: return "leaf.fill"
            }
        }
    }

    struct VoiceOption: Identifiable, Hashable {
        let id: String
        let name: String
        let language: String
        let quality: AVSpeechSynthesisVoiceQuality

        var subtitle: String {
            switch quality {
            case .premium: return "Premium"
            case .enhanced: return "Enhanced"
            default: return language
            }
        }
    }

    private let synthesizer = AVSpeechSynthesizer()
    @Published var selectedVoiceID: String {
        didSet { UserDefaults.standard.set(selectedVoiceID, forKey: "plant.voice.id") }
    }
    @Published var style: Style {
        didSet { UserDefaults.standard.set(style.rawValue, forKey: "plant.voice.style") }
    }
    @Published var speed: Double {
        didSet { UserDefaults.standard.set(speed, forKey: "plant.voice.speed") }
    }

    init() {
        selectedVoiceID = UserDefaults.standard.string(forKey: "plant.voice.id") ?? ""
        style = Style(rawValue: UserDefaults.standard.string(forKey: "plant.voice.style") ?? "") ?? .natural
        let stored = UserDefaults.standard.object(forKey: "plant.voice.speed") as? Double
        speed = stored ?? 1.0
    }

    var arabicVoices: [VoiceOption] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.lowercased().hasPrefix("ar") }
            .sorted {
                if $0.quality.rawValue != $1.quality.rawValue { return $0.quality.rawValue > $1.quality.rawValue }
                return $0.name < $1.name
            }
            .map { VoiceOption(id: $0.identifier, name: $0.name, language: $0.language, quality: $0.quality) }
    }

    func speak(_ persona: PlantPersonaMessage) {
        speakText(persona.message, baseRate: persona.voiceRate, basePitch: persona.voicePitch)
    }

    func preview() {
        speakText("هلا! أنا صوت نبتتك الجديد. كذا أحسن ولا أرجع أتكلم كأني جهاز ملاحة قديم؟", baseRate: 0.48, basePitch: 1.0)
    }

    func stop() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }

    private func speakText(_ text: String, baseRate: Float, basePitch: Float) {
        stop()
        let utterance = AVSpeechUtterance(string: normalizedArabic(text))
        if !selectedVoiceID.isEmpty, let voice = AVSpeechSynthesisVoice(identifier: selectedVoiceID) {
            utterance.voice = voice
        } else {
            utterance.voice = bestArabicVoice()
        }
        utterance.rate = min(max(baseRate * style.rate * Float(speed), 0.36), 0.57)
        utterance.pitchMultiplier = min(max(basePitch * style.pitch, 0.72), 1.42)
        utterance.volume = 1.0
        utterance.preUtteranceDelay = 0.08
        utterance.postUtteranceDelay = 0.08
        synthesizer.speak(utterance)
    }

    private func bestArabicVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.lowercased().hasPrefix("ar") }
        return voices.sorted { $0.quality.rawValue > $1.quality.rawValue }.first
            ?? AVSpeechSynthesisVoice(language: "ar-SA")
            ?? AVSpeechSynthesisVoice(language: "ar")
    }

    private func normalizedArabic(_ value: String) -> String {
        value
            .replacingOccurrences(of: "%", with: " بالمئة ")
            .replacingOccurrences(of: "&", with: " و ")
            .replacingOccurrences(of: "…", with: ". ")
            .replacingOccurrences(of: "!", with: "! ")
            .replacingOccurrences(of: "؟", with: "؟ ")
            .replacingOccurrences(of: "“", with: "")
            .replacingOccurrences(of: "”", with: "")
            .replacingOccurrences(of: "\n", with: ". ")
    }
}
