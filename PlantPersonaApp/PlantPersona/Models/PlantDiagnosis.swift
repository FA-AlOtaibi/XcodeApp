import Foundation

private extension KeyedDecodingContainer {
    func decodePercent(forKey key: Key) -> Int {
        if let value = try? decode(Int.self, forKey: key) {
            return max(0, min(100, value))
        }
        if let value = try? decode(Double.self, forKey: key) {
            let normalized = value >= 0 && value <= 1 ? value * 100 : value
            return max(0, min(100, Int(normalized.rounded())))
        }
        if let value = try? decode(String.self, forKey: key) {
            let cleaned = value.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            if let number = Double(cleaned) {
                let normalized = number >= 0 && number <= 1 ? number * 100 : number
                return max(0, min(100, Int(normalized.rounded())))
            }
        }
        return 0
    }
}

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
    let geo: GeoEstimate?

    enum CodingKeys: String, CodingKey {
        case title, category, summary, confidence, keyFacts, visibleDetails, howItWorksOrUsed, cautions, uncertainty, automotive, geo
    }

    init(title: String, category: String, summary: String, confidence: Int, keyFacts: [String], visibleDetails: [String], howItWorksOrUsed: [String], cautions: [String], uncertainty: String?, automotive: AutomotiveDiagnostic?, geo: GeoEstimate? = nil) {
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
        self.geo = geo
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = (try? c.decode(String.self, forKey: .title)) ?? "تحليل الصورة"
        category = (try? c.decode(String.self, forKey: .category)) ?? "عام"
        summary = (try? c.decode(String.self, forKey: .summary)) ?? "تم تحليل المحتوى."
        let parsedConfidence = c.decodePercent(forKey: .confidence)
        confidence = parsedConfidence == 0 ? 50 : parsedConfidence
        keyFacts = (try? c.decode([String].self, forKey: .keyFacts)) ?? []
        visibleDetails = (try? c.decode([String].self, forKey: .visibleDetails)) ?? []
        howItWorksOrUsed = (try? c.decode([String].self, forKey: .howItWorksOrUsed)) ?? []
        cautions = (try? c.decode([String].self, forKey: .cautions)) ?? []
        uncertainty = try? c.decodeIfPresent(String.self, forKey: .uncertainty)
        automotive = try? c.decodeIfPresent(AutomotiveDiagnostic.self, forKey: .automotive)
        geo = try? c.decodeIfPresent(GeoEstimate.self, forKey: .geo)
    }
}

struct GeoEstimate: Codable, Equatable {
    let country: String?
    let city: String?
    let area: String?
    let landmark: String?
    let confidence: Int
    let evidence: [String]
    let latitude: Double?
    let longitude: Double?

    enum CodingKeys: String, CodingKey { case country, city, area, landmark, confidence, evidence, latitude, longitude }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        country = try? c.decodeIfPresent(String.self, forKey: .country)
        city = try? c.decodeIfPresent(String.self, forKey: .city)
        area = try? c.decodeIfPresent(String.self, forKey: .area)
        landmark = try? c.decodeIfPresent(String.self, forKey: .landmark)
        confidence = c.decodePercent(forKey: .confidence)
        evidence = (try? c.decode([String].self, forKey: .evidence)) ?? []
        latitude = try? c.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try? c.decodeIfPresent(Double.self, forKey: .longitude)
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
        isVehicleRelated = (try? c.decode(Bool.self, forKey: .isVehicleRelated)) ?? true
        probableSystem = try? c.decodeIfPresent(String.self, forKey: .probableSystem)
        severity = try? c.decodeIfPresent(String.self, forKey: .severity)
        canDrive = try? c.decodeIfPresent(String.self, forKey: .canDrive)
        symptoms = (try? c.decode([String].self, forKey: .symptoms)) ?? []
        likelyCauses = (try? c.decode([AutomotiveCause].self, forKey: .likelyCauses)) ?? []
        checks = (try? c.decode([String].self, forKey: .checks)) ?? []
        fixes = (try? c.decode([String].self, forKey: .fixes)) ?? []
        dtcHints = (try? c.decode([String].self, forKey: .dtcHints)) ?? []
        mechanicNote = try? c.decodeIfPresent(String.self, forKey: .mechanicNote)
    }
}

struct AutomotiveCause: Codable, Equatable {
    let cause: String
    let probability: Int
    let reasoning: String

    enum CodingKeys: String, CodingKey { case cause, probability, reasoning }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cause = (try? c.decode(String.self, forKey: .cause)) ?? "سبب محتمل"
        probability = c.decodePercent(forKey: .probability)
        reasoning = (try? c.decode(String.self, forKey: .reasoning)) ?? ""
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
