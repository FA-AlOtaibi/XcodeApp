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
}
