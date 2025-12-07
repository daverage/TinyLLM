import Foundation

enum ThermalState: String, Codable {
    case nominal
    case moderate
    case heavy
    case hotspot
}

struct ThermalService {
    static func readThermalState() -> ThermalState {
        if let pmset = readFromPMSET(),
           let parsed = parseThermal(from: pmset) {
            return parsed
        }

        if let powermetrics = readFromPowerMetrics(),
           let parsed = parseThermal(from: powermetrics) {
            return parsed
        }

        return .nominal
    }

    private static func readFromPMSET() -> String? {
        let result = ProcessRunner.run("/usr/bin/pmset", ["-g", "thermalsystem"])
        guard result.code == 0 else { return nil }
        return result.out
    }

    private static func readFromPowerMetrics() -> String? {
        let result = ProcessRunner.run("/usr/bin/powermetrics", ["--samplers", "thermal", "-n", "1"])
        guard result.code == 0 else { return nil }
        return result.out
    }

    private static func parseThermal(from output: String) -> ThermalState? {
        let lower = output.lowercased()

        if lower.contains("hotspot") {
            return .hotspot
        }
        if lower.contains("heavy") {
            return .heavy
        }
        if lower.contains("moderate") {
            return .moderate
        }
        if lower.contains("nominal") {
            return .nominal
        }

        let numbers = output.components(separatedBy: CharacterSet.decimalDigits.inverted)
            .compactMap { Int($0) }
        if let first = numbers.first {
            switch first {
            case 3: return .hotspot
            case 2: return .heavy
            case 1: return .moderate
            default: return .nominal
            }
        }

        return nil
    }
}
