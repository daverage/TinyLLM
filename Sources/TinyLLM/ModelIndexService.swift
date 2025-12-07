import Foundation

/// Stores metadata about each model (quant, size, speed, last-use).
/// This allows TinyLLM to:
/// – auto-select best quant
/// – skip heavy rescans
/// – quickly show metadata
/// – benchmark + remember tokens/sec
actor ModelIndexService {
    
    // MARK: - Types
    
    struct ModelRecord: Codable, Identifiable {
        let id: UUID
        let filename: String
        let sizeBytes: Int64
        let approxBillions: Double
        let lastSeen: Date
        let lastTPS: Double?   // tokens/sec from last benchmark
        
        init(
            filename: String,
            sizeBytes: Int64,
            approxBillions: Double,
            lastSeen: Date,
            lastTPS: Double?,
            id: UUID = UUID()
        ) {
            self.id = id
            self.filename = filename
            self.sizeBytes = sizeBytes
            self.approxBillions = approxBillions
            self.lastSeen = lastSeen
            self.lastTPS = lastTPS
        }
    }
    
    // MARK: - Properties
    
    private let indexURL: URL
    private var records: [String: ModelRecord] = [:]   // key = filename

    private var saveTask: Task<Void, Never>?
    private var needsSave = false
    private let encoder = JSONEncoder()
    private let debounceInterval: UInt64 = 300_000_000
    
    // MARK: - Init
    
    init(appSupportRoot: URL) {
        self.indexURL = appSupportRoot.appendingPathComponent("model_index.json")
        load()
    }
    
    // MARK: - Public APIs
    
    /// List of all models with metadata.
    var allRecords: [ModelRecord] {
        records.values.sorted { $0.filename < $1.filename }
    }
    
    /// Snapshot of all records keyed by filename.
    func snapshotRecords() -> [String: ModelRecord] {
        records
    }

    /// Called when scanning the models folder.
    /// Updates or creates a record for that file.
    func updateRecord(for filename: String, at path: URL) async {
        let attrs = (try? FileManager.default.attributesOfItem(atPath: path.path)) ?? [:]
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        
        let approxB = estimateParametersFromSize(sizeBytes: size)
        
        let existing = records[filename]
        
        let newRecord = ModelRecord(
            filename: filename,
            sizeBytes: size,
            approxBillions: approxB,
            lastSeen: Date(),
            lastTPS: existing?.lastTPS,   // preserve speed result
            id: existing?.id ?? UUID()
        )
        
        records[filename] = newRecord
        scheduleSave()
    }
    
    /// Store benchmarking results (tokens/sec).
    func recordTPS(for filename: String, tps: Double) async {
        guard let rec = records[filename] else { return }
        
        let updated = ModelRecord(
            filename: rec.filename,
            sizeBytes: rec.sizeBytes,
            approxBillions: rec.approxBillions,
            lastSeen: Date(),
            lastTPS: tps,
            id: rec.id
        )
        
        records[filename] = updated
        scheduleSave()
    }
    
    /// Best quant selection:
    /// returns the filename with *highest* TPS among quant variants.
    ///
    /// For example:
    ///   Qwen2.5-Coder-7B-Q4_K_M.gguf
    ///   Qwen2.5-Coder-7B-Q6_K.gguf
    ///
    /// If we have benchmark results, pick fastest.
    /// Otherwise fall back to smallest-quant-file.
    func bestQuantVariant(for baseName: String) -> ModelRecord? {
        let matches = records.values.filter { $0.filename.contains(baseName) }
        if matches.isEmpty { return nil }
        
        // Prefer highest TPS if available
        let withTPS = matches.filter { $0.lastTPS != nil }
        if !withTPS.isEmpty {
            return withTPS.max { ($0.lastTPS ?? 0) < ($1.lastTPS ?? 0) }
        }
        
        // Otherwise, choose smallest (faster quant usually has smaller size)
        return matches.min { $0.sizeBytes < $1.sizeBytes }
    }
    
    // MARK: - Disk
    
    private func load() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        
        if let decoded = try? JSONDecoder().decode([String: ModelRecord].self, from: data) {
            self.records = decoded
        }
    }
    
    private func scheduleSave() {
        needsSave = true
        saveTask?.cancel()
        saveTask = Task.detached { [weak self] in
            try? await Task.sleep(nanoseconds: self?.debounceInterval ?? 300_000_000)
            await self?.flushSave()
        }
    }

    private func flushSave() async {
        guard needsSave else { return }
        needsSave = false
        let snapshot = records
        guard let data = try? encoder.encode(snapshot) else { return }
        let url = indexURL
        try? data.write(to: url, options: .atomic)
    }
    
    // MARK: - Helpers
    
    /// Approximate # of billions of parameters from file size.
    ///
    /// Rough rule of thumb (GGUF quantised models):
    ///   params ≈ (bytes / 1e9) × factor
    ///
    /// Different quant types compress differently, but this gives a good-enough signal.
    private func estimateParametersFromSize(sizeBytes: Int64) -> Double {
        let gb = Double(sizeBytes) / 1_000_000_000
        let approx = gb / 1.0   // simple: 1 GB = ~1B params in common quant tiers
        return max(0.5, round(approx * 2) / 2.0)   // round to nearest 0.5B
    }
}
