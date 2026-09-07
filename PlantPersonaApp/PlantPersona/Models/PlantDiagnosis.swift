import Foundation

struct VisualAnalysis: Codable, Equatable {
    let title: String
    let category: String
    let summary: String
    let confidence: Int
    let keyFacts: [String]
    let visibleDetails: [String]
    let howItWorksOrUsed: [String]
    let cautions: [String]
    let uncertainty: String?
    let automotive: AutomotiveDiagnostic?

    enum CodingKeys: String, CodingKey {
        case title, category, summary, confidence, keyFacts, visibleDetails, howItWorksOrUsed, cautions, uncertainty, automotive
    }

    init(title: String, category: String, summary: String, confidence: Int, keyFacts: [String], visibleDetails: [String], howItWorksOrUsed: [String], cautions: [String], uncertainty: String?, automotive: AutomotiveDiagnostic?) {
        self.title = title
        self.category = category
        self.summary = summary
        self.confidence = max(0, min(100, confidence))
        self.keyFacts = keyFacts
        self.visibleDetails = visibleDetails
        self.howItWorksOrUsed = howItWorksOrUsed
        self.cautions = cautions
        self.uncertainty = uncertainty
        self.automotive = automotive
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "تحليل الصورة"
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? "غير محدد"
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? "تم تحليل المحتوى، لكن بعض التفاصيل لم تصل بصيغة كاملة."
        confidence = max(0, min(100, try c.decodeIfPresent(Int.self, forKey: .confidence) ?? 50))
        keyFacts = try c.decodeIfPresent([String].self, forKey: .keyFacts) ?? []
        visibleDetails = try c.decodeIfPresent([String].self, forKey: .visibleDetails) ?? []
        howItWorksOrUsed = try c.decodeIfPresent([String].self, forKey: .howItWorksOrUsed) ?? []
        cautions = try c.decodeIfPresent([String].self, forKey: .cautions) ?? []
        uncertainty = try c.decodeIfPresent(String.self, forKey: .uncertainty)
        automotive = try c.decodeIfPresent(AutomotiveDiagnostic.self, forKey: .automotive)
    }
}

struct AutomotiveDiagnostic: Codable, Equatable {
    let isVehicleRelated: Bool
    let probableSystem: String?
    let severity: String?
    let canDrive: String?
    let symptoms: [String]
    let likelyCauses: [AutomotiveCause]
    let checks: [String]
    let fixes: [String]
    let dtcHints: [String]
    let mechanicNote: String?

    enum CodingKeys: String, CodingKey {
        case isVehicleRelated, probableSystem, severity, canDrive, symptoms, likelyCauses, checks, fixes, dtcHints, mechanicNote
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isVehicleRelated = try c.decodeIfPresent(Bool.self, forKey: .isVehicleRelated) ?? true
        probableSystem = try c.decodeIfPresent(String.self, forKey: .probableSystem)
        severity = try c.decodeIfPresent(String.self, forKey: .severity)
        canDrive = try c.decodeIfPresent(String.self, forKey: .canDrive)
        symptoms = try c.decodeIfPresent([String].self, forKey: .symptoms) ?? []
        likelyCauses = try c.decodeIfPresent([AutomotiveCause].self, forKey: .likelyCauses) ?? []
        checks = try c.decodeIfPresent([String].self, forKey: .checks) ?? []
        fixes = try c.decodeIfPresent([String].self, forKey: .fixes) ?? []
        dtcHints = try c.decodeIfPresent([String].self, forKey: .dtcHints) ?? []
        mechanicNote = try c.decodeIfPresent(String.self, forKey: .mechanicNote)
    }
}

struct AutomotiveCause: Codable, Equatable {
    let cause: String
    let probability: Int
    let reasoning: String

    enum CodingKeys: String, CodingKey { case cause, probability, reasoning }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cause = try c.decodeIfPresent(String.self, forKey: .cause) ?? "سبب محتمل"
        probability = max(0, min(100, try c.decodeIfPresent(Int.self, forKey: .probability) ?? 0))
        reasoning = try c.decodeIfPresent(String.self, forKey: .reasoning) ?? ""
    }
}

struct MediaSoundProfile: Codable, Equatable {
    let durationSeconds: Double
    let rms: Double
    let peak: Double
    let zeroCrossingRate: Double
    let dominantPulseHz: Double?
    let note: String
}

struct OBDLiveData: Equatable {
    var rpm: Double?
    var speedKmh: Double?
    var coolantC: Double?
    var throttlePercent: Double?
    var engineLoadPercent: Double?
    var voltage: Double?
}

struct OBDScanResult: Equatable {
    let dtcs: [String]
    let live: OBDLiveData
    let rawSummary: String
}
