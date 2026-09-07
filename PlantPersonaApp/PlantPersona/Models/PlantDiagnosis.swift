import Foundation

struct PlantDiagnosis: Codable, Equatable {
    let plantName: String
    let scientificName: String?
    let healthStatus: String
    let likelyIssue: String
    let confidence: Int
    let urgency: String
    let visualEvidence: [String]
    let careSteps: [String]
    let warning: String?
}

struct PlantPersonaMessage: Codable, Equatable {
    let mood: String
    let title: String
    let message: String
    let shortAction: String
    let voiceRate: Float
    let voicePitch: Float
}
