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
}

struct AutomotiveCause: Codable, Equatable {
    let cause: String
    let probability: Int
    let reasoning: String
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
