import Foundation

struct BenchmarkResult {
    let latencySeconds: TimeInterval
    let tokensGenerated: Int

    var tokensPerSecond: Double {
        guard latencySeconds > 0 else { return Double(tokensGenerated) }
        return Double(tokensGenerated) / latencySeconds
    }
}

enum BenchmarkError: LocalizedError {
    case invalidURL
    case badStatus(Int)
    case noData

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Unable to build the benchmark URL."
        case .badStatus(let code):
            return "Server returned status \(code)."
        case .noData:
            return "No data returned from the benchmark."
        }
    }
}

final class BenchmarkService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func runBenchmark(modelFilename: String, baseURL: String) async throws -> BenchmarkResult {
        guard let url = URL(string: "\(baseURL)/completions") else {
            throw BenchmarkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = CompletionPayload(
            model: modelFilename,
            prompt: "Hello, how are you?",
            maxTokens: 24,
            temperature: 0.2,
            topP: 0.9
        )

        request.httpBody = try JSONEncoder().encode(payload)

        let start = Date()
        let (data, response) = try await session.data(for: request)
        let elapsed = Date().timeIntervalSince(start)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw BenchmarkError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }

        guard !data.isEmpty else {
            throw BenchmarkError.noData
        }

        let usage = (try? JSONDecoder().decode(CompletionResponse.self, from: data))?.usage?.totalTokens
        let tokens = usage ?? payload.maxTokens

        return BenchmarkResult(latencySeconds: elapsed, tokensGenerated: tokens)
    }
}

private struct CompletionPayload: Encodable {
    let model: String
    let prompt: String
    let maxTokens: Int
    let temperature: Double
    let topP: Double

    enum CodingKeys: String, CodingKey {
        case model
        case prompt
        case maxTokens = "max_tokens"
        case temperature
        case topP = "top_p"
    }
}

private struct CompletionResponse: Decodable {
    struct Usage: Decodable {
        let totalTokens: Int?

        enum CodingKeys: String, CodingKey {
            case totalTokens = "total_tokens"
        }
    }

    let usage: Usage?
}
