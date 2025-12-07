import Foundation

// MARK: - Basic Model Container

struct LLMModel: Identifiable, Equatable, Hashable {
    let id = UUID()
    let filename: String
    let fullPath: URL
    
    static func == (lhs: LLMModel, rhs: LLMModel) -> Bool {
        lhs.filename == rhs.filename
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(filename)
    }
}

// MARK: - Profiles

enum LLMProfile: String, CaseIterable, Identifiable, Codable {
    case coding
    case creative
    case strict
    case balanced
    
    var id: String { rawValue }
    
    var label: String {
        switch self {
        case .coding:   return "Coding"
        case .creative: return "Creative"
        case .strict:   return "Strict"
        case .balanced: return "Balanced"
        }
    }
    
    var detail: String {
        switch self {
        case .coding:
            return "Lower temperature, higher top-p stability. Good for precise reasoning and code."
        case .creative:
            return "Higher temperature, diverse top-p. Better for ideation and open-ended tasks."
        case .strict:
            return "Very low temperature, deterministic. Avoids hallucinations."
        case .balanced:
            return "Middle ground between creativity and accuracy."
        }
    }
    
    var temp: Double {
        switch self {
        case .coding: return 0.15
        case .creative: return 0.85
        case .strict: return 0.05
        case .balanced: return 0.35
        }
    }
    
    var topP: Double {
        switch self {
        case .coding: return 0.9
        case .creative: return 0.95
        case .strict: return 0.85
        case .balanced: return 0.9
        }
    }
}

// MARK: - Recommended Settings

struct RecommendedSettings {
    let ctx: Int
    let batch: Int
    let nGpu: Int
    let cacheK: String
    let cacheV: String
    let flash: Bool
    let threads: Int
    
    let summary: String
    let warning: String?
    let note: String?
}

// MARK: - Download Preset

struct Preset: Identifiable {
    let id = UUID()
    let label: String
    let url: String
    let filename: String
}

// MARK: - Chip Family

enum ChipFamily: String {
    case intel = "Intel"
    case m1 = "Apple M1"
    case m2 = "Apple M2"
    case m3 = "Apple M3"
    case m4 = "Apple M4"
    case unknown = "Unknown"
}
