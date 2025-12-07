import Foundation
import SwiftUI

enum ServerHealthState: String {
    case stopped
    case starting
    case healthy
    case degraded
    case crashed
}

enum MemoryPressureLevel: String {
    case low
    case moderate
    case high
    case critical
}

@MainActor
final class LLMManager: ObservableObject {
    
    // MARK: - Services
    private let processService = ProcessService()
    private let modelIndexService: ModelIndexService
    
    // MARK: - State Properties
    private let defaults = UserDefaults.standard
    private var isRestoringSettings = false
    
    // Public paths
    let appSupportRoot: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("TinyLLM", conformingTo: .directory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    
    var llamaCPPDir: URL { appSupportRoot.appendingPathComponent("llama.cpp", conformingTo: .directory) }
    var buildDir: URL { llamaCPPDir.appendingPathComponent("build", conformingTo: .directory) }
    var serverBinary: URL { llamaCPPDir.appendingPathComponent("build/bin/llama-server") }
    var modelsDir: URL { appSupportRoot.appendingPathComponent("models", conformingTo: .directory) }
    var logFile: URL { appSupportRoot.appendingPathComponent("llama-server.log") }
    
    // MARK: - Defaults Keys
    struct DefaultsKey {
        static let host = "TinyLLM.host"
        static let port = "TinyLLM.port"
        static let ctxSize = "TinyLLM.ctxSize"
        static let batchSize = "TinyLLM.batchSize"
        static let nGpuLayers = "TinyLLM.nGpuLayers"
        static let threadCount = "TinyLLM.threadCount"
        static let cacheK = "TinyLLM.cacheK"
        static let cacheV = "TinyLLM.cacheV"
        static let enableFlash = "TinyLLM.enableFlash"
        static let enableRopeScaling = "TinyLLM.enableRopeScaling"
        static let ropeScalingValue = "TinyLLM.ropeScalingValue"
        static let enableAutoKV = "TinyLLM.enableAutoKV"
        static let manualContextOverride = "TinyLLM.manualContextOverride"
        static let extraArgsRaw = "TinyLLM.extraArgsRaw"
        static let selectedModel = "TinyLLM.selectedModel"
        static let profile = "TinyLLM.profile"
        static let customURL = "TinyLLM.customURL"
        static let customFilename = "TinyLLM.customFilename"
        static let autoApplyRecommended = "TinyLLM.autoApplyRecommended"
        static let autoThrottleMemory = "TinyLLM.autoThrottleMemory"
        static let autoReduceRuntimeOnPressure = "TinyLLM.autoReduceRuntimeOnPressure"
        static let autoSwitchQuantOnPressure = "TinyLLM.autoSwitchQuantOnPressure"
    }
    
    // MARK: - Published Config
    @Published var host: String = "127.0.0.1" { didSet { persist(host, for: DefaultsKey.host) } }
    @Published var port: Int = 8000 { didSet { persist(port, for: DefaultsKey.port) } }
    @Published var ctxSize: Int = 32768 { didSet { persist(ctxSize, for: DefaultsKey.ctxSize) } }
    @Published var batchSize: Int = 512 { didSet { persist(batchSize, for: DefaultsKey.batchSize) } }
    @Published var nGpuLayers: Int = 80 { didSet { persist(nGpuLayers, for: DefaultsKey.nGpuLayers) } }
    @Published var threadCount: Int = 4 { didSet { persist(threadCount, for: DefaultsKey.threadCount) } }
    
    // Advanced Config
    @Published var cacheTypeK: String = "q4_0" { didSet { persist(cacheTypeK, for: DefaultsKey.cacheK) } }
    @Published var cacheTypeV: String = "q4_0" { didSet { persist(cacheTypeV, for: DefaultsKey.cacheV) } }
    @Published var enableFlashAttention: Bool = false { didSet { persist(enableFlashAttention, for: DefaultsKey.enableFlash) } }
    @Published var enableRopeScaling: Bool = false { didSet { persist(enableRopeScaling, for: DefaultsKey.enableRopeScaling) } }
    @Published var ropeScalingValue: Double = 1.0 { didSet { persist(ropeScalingValue, for: DefaultsKey.ropeScalingValue) } }
    @Published var enableAutoKV: Bool = true { didSet { persist(enableAutoKV, for: DefaultsKey.enableAutoKV) } }
    @Published var manualContextOverride: Bool = false { didSet { persist(manualContextOverride, for: DefaultsKey.manualContextOverride) } }
    @Published var extraArgsRaw: String = "" { didSet { persist(extraArgsRaw, for: DefaultsKey.extraArgsRaw) } }
    @Published var autoApplyRecommended: Bool = true { didSet { persist(autoApplyRecommended, for: DefaultsKey.autoApplyRecommended) } }

    @Published var autoThrottleMemory: Bool = false { didSet { persist(autoThrottleMemory, for: DefaultsKey.autoThrottleMemory) } }
    @Published var autoReduceRuntimeOnPressure: Bool = false { didSet { persist(autoReduceRuntimeOnPressure, for: DefaultsKey.autoReduceRuntimeOnPressure) } }
    @Published var autoSwitchQuantOnPressure: Bool = false { didSet { persist(autoSwitchQuantOnPressure, for: DefaultsKey.autoSwitchQuantOnPressure) } }

    // Download / Custom
    @Published var customURL: String = "" { didSet { persist(customURL, for: DefaultsKey.customURL) } }
    @Published var customFilename: String = "" { didSet { persist(customFilename, for: DefaultsKey.customFilename) } }
    
    // Runtime State
    @Published var availableModels: [LLMModel] = []
    @Published var selectedModel: LLMModel? { didSet { persist(selectedModel?.filename, for: DefaultsKey.selectedModel) } }
    @Published var profile: LLMProfile = .coding {
        didSet { updateProfileDetail() }
    }
    @Published private var modelRecordCache: [String: ModelIndexService.ModelRecord] = [:]
    @Published var profileDetail: String = LLMProfile.coding.detail
    @Published var isRunning = false
    @Published var statusText: String = "Idle"
    @Published var logTail: String = ""
    @Published var cpuPercent: String = "-"
    @Published var memPercent: String = "-"
    @Published var hardwareSummary: String = "Detecting…"
    @Published var gpuSummary: String = "Detecting…"
    @Published var thermalState: ThermalState = .nominal
    
    @Published var healthState: ServerHealthState = .stopped
    @Published var healthNote: String = "Idle"
    
    // Planners / Diagnostics
    @Published var recommendedSummary: String = "Not computed yet"
    @Published var currentRecommendedSettings: RecommendedSettings?
    @Published var effectiveCtxSize: Int = 32768
    @Published var contextWarning: String? = nil
    @Published var debugMode: Bool = false
    @Published var lastBuildDurationSeconds: Double? = nil
    
    // Helpers
    private var logMonitor: DispatchSourceFileSystemObject?
    private let logWriteQueue = DispatchQueue(label: "TinyLLM.logWriter", qos: .utility)

    private var healthTask: Task<Void, Never>?
    private var isBatchPersistingSettings = false
    private var lastLogTimestamp: Date?
    private var lastKnownPID: Int32?
    private var lastMemoryWarning: Date?
    private var lastAutoThrottleTimestamp: Date?
    private var lastAutoRuntimeThrottleTimestamp: Date?
    private var lastAutoQuantSwitchTimestamp: Date?
    private let autoMemoryCooldown: TimeInterval = 60
    
    // System Specs Cache
    private var ramGB: Int = 0
    private var chipFamily: ChipFamily = .unknown
    
    var openAIApiBase: String { "http://\(host):\(port)/v1" }
    var maxThreadCount: Int { ProcessInfo.processInfo.activeProcessorCount }
    
    // Presets
    let presets: [Preset] = [
        .init(label: "Qwen2.5 Coder 7B", url: "https://huggingface.co/unsloth/Qwen2.5-Coder-7B-Instruct-128K-GGUF/resolve/main/Qwen2.5-Coder-7B-Instruct-Q4_K_M.gguf", filename: "Qwen2.5-Coder-7B-Instruct-Q4_K_M.gguf"),
        .init(label: "Mistral 7B v0.3", url: "https://huggingface.co/bartowski/Mistral-7B-Instruct-v0.3-GGUF/resolve/main/Mistral-7B-Instruct-v0.3-Q4_K_M.gguf", filename: "Mistral-7B-Instruct-v0.3-Q4_K_M.gguf"),
        .init(label: "Phi-3 Mini", url: "https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-gguf/resolve/main/Phi-3-mini-4k-instruct-q4.gguf", filename: "Phi-3-mini-4k-instruct-q4.gguf"),
        .init(label: "DeepSeek-R1-0528 8B", url: "https://huggingface.co/unsloth/DeepSeek-R1-0528-Qwen3-8B-GGUF/resolve/main/DeepSeek-R1-0528-Qwen3-8B-Q4_K_M.gguf", filename: "DeepSeek-R1-0528-Qwen3-8B-Q4_K_M.gguf")
    ]


    // MARK: - Initialization
    init() {
        self.modelIndexService = ModelIndexService(appSupportRoot: appSupportRoot)
        isRestoringSettings = true
        loadSettings()
        isRestoringSettings = false
        
        ensureLogFile()
        startLogMonitor()
        startHealthMonitoring()
        refreshModels()
        
        Task {
            // Detect hardware async, then update UI
            let specs = await HardwareService.detectSpecs()
            self.ramGB = specs.ramGB
            self.chipFamily = specs.chipFamily
            self.hardwareSummary = "Chip: \(specs.chipFamily.rawValue), RAM: \(specs.ramGB) GB"
            self.gpuSummary = specs.gpuName
            
            // Validate thread count
            if self.threadCount == 0 {
                self.threadCount = max(1, ProcessInfo.processInfo.activeProcessorCount - 2)
            }
            
            let rec = self.recommendedSettings(for: self.selectedModel)
            await MainActor.run {
                self.currentRecommendedSettings = rec
                self.recommendedSummary = rec.summary
                self.effectiveCtxSize = rec.ctx
                self.contextWarning = rec.warning
                if self.autoApplyRecommended {
                    self.applyRecommended(rec)
                }
            }
        }
    }
    
    // MARK: - Public Controls
    
    func refreshModels() {
        Task {
            await refreshModelsAsync()
        }
    }

    private func refreshModelsAsync() async {
        try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        var models: [LLMModel] = []
        if let contents = try? FileManager.default.contentsOfDirectory(at: modelsDir, includingPropertiesForKeys: nil) {
            models = contents
                .filter { $0.pathExtension.lowercased() == "gguf" }
                .map { LLMModel(filename: $0.lastPathComponent, fullPath: $0) }
                .sorted { $0.filename < $1.filename }
        }

        availableModels = models
        await updateModelIndexEntries(with: models)

        if selectedModel == nil || !availableModels.contains(where: { $0.filename == selectedModel?.filename }) {
            selectedModel = availableModels.first
        }
    }

    private func updateModelIndexEntries(with models: [LLMModel]) async {
        for model in models {
            await modelIndexService.updateRecord(for: model.filename, at: model.fullPath)
        }
        await refreshModelRecordCache()
    }

    private func refreshModelRecordCache() async {
        let snapshot = await modelIndexService.snapshotRecords()
        modelRecordCache = snapshot
    }

    func modelRecord(for model: LLMModel) -> ModelIndexService.ModelRecord? {
        modelRecordCache[model.filename]
    }
    
    func startServer() {
        guard !isRunning else { return }
        guard let model = selectedModel else { statusText = "No model selected."; return }
        
        if !FileManager.default.fileExists(atPath: serverBinary.path) {
            rebuildLlamaCPP(autoStartAfter: true)
            return
        }
        
        // Planning
        let sizeB = estimatedBillions(for: model)
        let resolvedCtx = resolveContextPlan(sizeB: sizeB)
        effectiveCtxSize = resolvedCtx.value
        contextWarning = resolvedCtx.warning
        
        // Args
        var args: [String] = [
            "-m", model.fullPath.path,
            "--host", host, "--port", String(port),
            "--n-gpu-layers", String(nGpuLayers),
            "--ctx-size", String(resolvedCtx.value),
            "--batch-size", String(batchSize),
            "--threads", String(threadCount),
            "--temp", String(format: "%.2f", profile.temp),
            "--top-p", String(format: "%.2f", profile.topP),
            "--cache-type-k", cacheTypeK,
            "--cache-type-v", cacheTypeV
        ]
        
        if enableFlashAttention { args.append(contentsOf: ["--flash-attn", "on"]) }
        if enableRopeScaling {
            let ropeScaleFormatted = String(format: "%.1f", ropeScalingValue)
            args.append(contentsOf: ["--rope-scaling", "linear", "--rope-scale", ropeScaleFormatted])
        }
        let extra = extraArgsRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !extra.isEmpty { args.append(contentsOf: extra.components(separatedBy: " ")) }
        args.append(contentsOf: ["--alias", modelAlias(for: model)])
        
        statusText = "Launching..."
        appendLog("Starting server: \(args.joined(separator: " "))")
        
        Task {
            do {
                let pid = try await processService.startAsync(executable: serverBinary, args: args, outputToFile: logFile)
                isRunning = true
                statusText = "Running \(model.filename)"
                didStartServer(pid: pid)
                appendLog("Started with PID \(pid)")
            } catch {
                await handleServerCrash(reason: "Launch failed: \(error.localizedDescription)")
            }
        }
    }
    
    func stopServer(statusNote: String? = nil) {
        Task { @MainActor in
            await processService.terminate()
            finalizeServerStop(statusNote: statusNote, intentional: true)
        }
    }

    func stopServerBlocking(statusNote: String? = nil, timeout: TimeInterval = 5.0) {
        guard isRunning else { return }
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached { [processService] in
            await processService.terminate()
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + timeout)
        finalizeServerStop(statusNote: statusNote, intentional: true)
    }

    private func handleServerCrash(reason: String) async {
        appendLog(reason, level: .error)
        statusText = reason
        healthState = .crashed
        healthNote = reason
        await processService.terminate()
        isRunning = false
        didStopServer(intentional: false)
        appendLog("Server halted to keep the app stable.", level: .info)
    }
    
    func rebuildLlamaCPP(autoStartAfter: Bool = false) {
        statusText = "Checking repo..."
        ensureLlamaRepo() // async check
        
        statusText = "Building..."
        appendLog("Starting rebuild.")
        
        Task {
            let start = Date()
            do {
                try? FileManager.default.createDirectory(at: buildDir, withIntermediateDirectories: true)
                
                let cmakeArgs = [
                    "-S", llamaCPPDir.path,
                    "-B", buildDir.path,
                    "-DLLAMA_METAL=ON",
                    "-DLLAMA_BUILD_SERVER=ON"
                ]
                
                let cmakeCode = try await processService.runSync(
                    executable: "/usr/bin/cmake",
                    args: cmakeArgs,
                    currentDir: llamaCPPDir,
                    outputToFile: logFile
                )
                guard cmakeCode == 0 else {
                    statusText = "CMake failed (\(cmakeCode))"
                    appendLog("CMake failed with code \(cmakeCode)", level: .error)
                    return
                }
                
                let buildCode = try await processService.runSync(
                    executable: "/usr/bin/cmake",
                    args: ["--build", "build", "--config", "Release", "-j", "\(maxThreadCount)"],
                    currentDir: llamaCPPDir,
                    outputToFile: logFile
                )
                guard buildCode == 0 else {
                    statusText = "Build failed (\(buildCode))"
                    appendLog("Build failed with code \(buildCode)", level: .error)
                    return
                }
                
                let elapsed = Date().timeIntervalSince(start)
                await MainActor.run {
                    lastBuildDurationSeconds = elapsed
                    statusText = "Build complete in \(String(format: "%.1fs", elapsed))"
                    appendLog("Build complete in \(String(format: "%.1fs", elapsed))")
                    if autoStartAfter {
                        self.startServer()
                    }
                }
            } catch {
                statusText = "Build error"
                appendLog("Build Exception: \(error)", level: .error)
            }
        }
    }
    
    private func ensureLlamaRepo() {
        let cmake = llamaCPPDir.appendingPathComponent("CMakeLists.txt")
        if FileManager.default.fileExists(atPath: cmake.path) { return }
        
        appendLog("Cloning llama.cpp...")
        Task {
            try? await processService.runSync(
                executable: "/usr/bin/git",
                args: ["clone", "https://github.com/ggerganov/llama.cpp", "llama.cpp"],
                currentDir: appSupportRoot,
                outputToFile: logFile
            )
        }
    }
    
    // MARK: - Downloads
    func downloadPreset(_ preset: Preset) {
        downloadModel(from: preset.url, saveAs: preset.filename, label: preset.label)
    }
    
    func downloadCustom() {
        let url = customURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let filename = customFilename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty, !filename.isEmpty else {
            statusText = "Enter URL and filename"
            return
        }
        downloadModel(from: url, saveAs: filename, label: "Custom")
    }
    
    private func downloadModel(from urlStr: String, saveAs filename: String, label: String) {
        statusText = "Downloading \(label)…"
        appendLog("Downloading model from \(urlStr) to \(filename)")
        
        Task {
            do {
                try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
                let dest = modelsDir.appendingPathComponent(filename)
                let code = try await processService.runSync(
                    executable: "/usr/bin/curl",
                    args: ["-L", "--progress-bar", "-o", dest.path, urlStr],
                    outputToFile: logFile
                )
                if code == 0 {
                    await MainActor.run {
                        refreshModels()
                        statusText = "Downloaded \(filename)"
                    }
                } else {
                    await MainActor.run {
                        statusText = "Download failed"
                    }
                }
            } catch {
                await MainActor.run {
                    statusText = "Download error"
                }
            }
        }
    }

    // MARK: - Benchmarks
    func benchmarkSelectedModel() {
        guard let model = selectedModel else {
            statusText = "Choose a model to benchmark."
            return
        }

        statusText = "Benchmarking \(model.filename)…"
        appendLog("Benchmarking \(model.filename)")

        let service = BenchmarkService()
        Task { @MainActor in
            do {
                let result = try await service.runBenchmark(
                    modelFilename: model.filename,
                    baseURL: openAIApiBase
                )
                await modelIndexService.recordTPS(for: model.filename, tps: result.tokensPerSecond)
                await refreshModelRecordCache()
                statusText = "Benchmark complete: \(String(format: "%.1f TPS", result.tokensPerSecond))"
                appendLog("Benchmark result: \(String(format: "%.1f TPS", result.tokensPerSecond))")
            } catch {
                statusText = "Benchmark failed"
                appendLog("Benchmark error: \(error.localizedDescription)", level: .error)
            }
        }
    }

    // MARK: - Metrics
    func updateMetrics() {
        // 1. System Memory (Native)
        memPercent = HardwareService.getMemoryUsagePercent()

        // 2. Process CPU (via actor)
        Task {
            if await processService.isRunning(), let pid = await processService.getPID() {
                if let metrics = await processService.getProcessMetrics(pid: pid) {
                    cpuPercent = metrics.cpu
                    // optionally use process mem instead of system mem
                }
            } else {
                cpuPercent = HardwareService.getCPULoad() // fallback to load avg
            }
        }
        
        maybeAdjustForMemory()
    }

    func refreshThermalState() {
        Task {
            let state = ThermalService.readThermalState()
            await MainActor.run {
                thermalState = state
            }
        }
    }
    
    var memoryPressure: MemoryPressureLevel {
        let stripped = memPercent.replacingOccurrences(of: "%", with: "")
        let used = Double(stripped) ?? 0
        switch used {
        case ..<60: return .low
        case 60..<75: return .moderate
        case 75..<90: return .high
        default: return .critical
        }
    }
    
    private func maybeAdjustForMemory() {
        switch memoryPressure {
        case .low, .moderate:
            break
        case .high, .critical:
            let now = Date()
            if let last = lastMemoryWarning, now.timeIntervalSince(last) < 60 {
                break
            }
            lastMemoryWarning = now
            appendLog("High memory pressure detected (\(memPercent)). Consider reducing context size, batch size, or choosing a smaller model.", level: .info)
        }

        handleAutoMemoryActions()
    }

    private func handleAutoMemoryActions() {
        appendDebugLog("Memory pressure \(memoryPressure.rawValue), autoThrottle=\(autoThrottleMemory), autoReduce=\(autoReduceRuntimeOnPressure), autoSwitch=\(autoSwitchQuantOnPressure)")
        guard memoryPressure == .high || memoryPressure == .critical else { return }
        if autoReduceRuntimeIfNeeded() { return }
        if autoSwitchQuantVariantIfNeeded() { return }
        autoThrottleServerIfNeeded()
    }

    private func autoReduceRuntimeIfNeeded() -> Bool {
        guard autoReduceRuntimeOnPressure else { return false }
        guard shouldRespectCooldown(&lastAutoRuntimeThrottleTimestamp, interval: autoMemoryCooldown) else { return false }

        let newCtx = max(1024, Int(Double(ctxSize) * 0.75))
        let newBatch = max(64, Int(Double(batchSize) * 0.75))
        guard newCtx < ctxSize || newBatch < batchSize else { return false }

        appendDebugLog("Auto-reduce proposes ctx \(newCtx), batch \(newBatch)")

        ctxSize = newCtx
        batchSize = newBatch
        effectiveCtxSize = newCtx
        contextWarning = "Auto-reduced context/batch after high memory pressure"
        appendLog("Auto-reduced ctx to \(ctxSize) and batch to \(batchSize) after memory pressure.", level: .info)
        return true
    }

    private func autoSwitchQuantVariantIfNeeded() -> Bool {
        guard autoSwitchQuantOnPressure else { return false }
        guard shouldRespectCooldown(&lastAutoQuantSwitchTimestamp, interval: autoMemoryCooldown) else { return false }
        guard let current = selectedModel else { return false }

        let base = baseModelName(for: current.filename)
        guard let best = bestQuantVariantCache(for: base), best.filename != current.filename else { return false }
        let candidateURL = modelsDir.appendingPathComponent(best.filename)
        guard FileManager.default.fileExists(atPath: candidateURL.path) else { return false }

        appendDebugLog("Auto-switch candidate \(best.filename) found for base \(base)")

        selectedModel = LLMModel(filename: best.filename, fullPath: candidateURL)
        appendLog("Auto-switched to \(best.filename) due to memory pressure.", level: .info)
        restartServerAfterModelSwitch()
        return true
    }

    private func autoThrottleServerIfNeeded() {
        guard autoThrottleMemory else { return }
        guard isRunning else { return }
        guard shouldRespectCooldown(&lastAutoThrottleTimestamp, interval: autoMemoryCooldown) else { return }

        appendDebugLog("Auto-throttle triggered, stopping server")

        appendLog("Automatic stop triggered by high memory pressure.", level: .info)
        stopServer(statusNote: "Stopped (memory safeguard)")
    }

    private func restartServerAfterModelSwitch() {
        guard isRunning else { return }

        Task {
            await MainActor.run {
                statusText = "Restarting with fallback model..."
            }
            await processService.terminate()
            await MainActor.run {
                isRunning = false
                didStopServer(intentional: true)
                appendLog("Server stopped for quant switch restart.", level: .info)
            }
            await MainActor.run {
                startServer()
            }
        }
    }

    private func baseModelName(for filename: String) -> String {
        var trimmed = filename
        if trimmed.hasSuffix(".gguf") {
            trimmed = String(trimmed.dropLast(5))
        }

        if let range = trimmed.range(of: "-Q", options: [.backwards, .caseInsensitive]) {
            let after = trimmed.index(range.lowerBound, offsetBy: 2, limitedBy: trimmed.endIndex)
            if let after = after, after < trimmed.endIndex, trimmed[after].isNumber {
                trimmed = String(trimmed[..<range.lowerBound])
            }
        }

        return trimmed
    }

    private func bestQuantVariantCache(for baseName: String) -> ModelIndexService.ModelRecord? {
        let matches = modelRecordCache.values.filter { $0.filename.contains(baseName) }
        if matches.isEmpty { return nil }

        let withTPS = matches.filter { $0.lastTPS != nil }
        if !withTPS.isEmpty {
            return withTPS.max { ($0.lastTPS ?? 0) < ($1.lastTPS ?? 0) }
        }

        return matches.min { $0.sizeBytes < $1.sizeBytes }
    }

    private func shouldRespectCooldown(_ timestamp: inout Date?, interval: TimeInterval) -> Bool {
        let now = Date()
        if let last = timestamp, now.timeIntervalSince(last) < interval {
            return false
        }
        timestamp = now
        return true
    }
    
    func startHealthMonitoring() {
        healthTask?.cancel()
        healthTask = Task.detached { [weak self] in
            while !Task.isCancelled {
                await self?.pollHealth()
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch {
                    break
                }
            }
        }
    }
    
    func stopHealthMonitoring() {
        healthTask?.cancel()
        healthTask = nil
    }
    
    private func pollHealth() async {
        // If server is not supposed to be running, reflect that.
        if !(await processService.isRunning()) {
            if isRunning {
                // Unexpected stop
                healthState = .crashed
                healthNote = "Server not running (unexpected)"
                isRunning = false
            } else {
                healthState = .stopped
                healthNote = "Server stopped"
            }
            return
        }
        
        if let pid = await processService.getPID(),
           let metrics = await processService.getProcessMetrics(pid: pid) {
            lastKnownPID = pid
            let cpuString = metrics.cpu.trimmingCharacters(in: .whitespacesAndNewlines)
            let cpuValue = Double(cpuString.replacingOccurrences(of: "%", with: "")) ?? 0
            let lastLogAge = lastLogTimestamp.map { Date().timeIntervalSince($0) } ?? .infinity
            
            if cpuValue < 1.0 && lastLogAge > 60 {
                healthState = .degraded
                healthNote = "Possible stall: no log activity for \(Int(lastLogAge))s, CPU \(metrics.cpu)"
            } else {
                healthState = .healthy
                healthNote = "Server OK (\(metrics.cpu) CPU, mem \(memPercent))"
            }
        } else {
            healthState = .degraded
            healthNote = "Unable to read server metrics"
        }
    }
    
    private func didStartServer(pid: Int32) {
        lastKnownPID = pid
        healthState = .starting
        healthNote = "Starting server (pid \(pid))"
        lastLogTimestamp = Date()
    }
    
    private func didStopServer(intentional: Bool) {
        lastKnownPID = nil
        healthState = intentional ? .stopped : .crashed
        healthNote = intentional ? "Server stopped" : "Server crashed"
    }

    private func finalizeServerStop(statusNote: String?, intentional: Bool) {
        isRunning = false
        statusText = statusNote ?? "Stopped"
        cpuPercent = "-"
        memPercent = "-"
        didStopServer(intentional: intentional)
        appendLog("Server stopped.")
    }
    
    // MARK: - Planning Logic (Business Logic)
    func updateRecommended() {
        let rec = recommendedSettings(for: selectedModel)
        currentRecommendedSettings = rec
        recommendedSummary = rec.summary
        if autoApplyRecommended {
            applyRecommended(rec)
        }
        refreshRuntimePlanner()
    }

    func applyRecommendedSettings() {
        let rec = recommendedSettings(for: selectedModel)
        currentRecommendedSettings = rec
        recommendedSummary = rec.summary
        applyRecommended(rec)
        refreshRuntimePlanner()
    }

    private func applyRecommended(_ rec: RecommendedSettings) {
        isBatchPersistingSettings = true
        ctxSize = rec.ctx
        batchSize = rec.batch
        nGpuLayers = rec.nGpu
        cacheTypeK = rec.cacheK
        cacheTypeV = rec.cacheV
        enableFlashAttention = rec.flash
        threadCount = rec.threads
        isBatchPersistingSettings = false

        effectiveCtxSize = rec.ctx
        contextWarning = rec.warning

        persistBatch([
            DefaultsKey.ctxSize: rec.ctx,
            DefaultsKey.batchSize: rec.batch,
            DefaultsKey.nGpuLayers: rec.nGpu,
            DefaultsKey.cacheK: rec.cacheK,
            DefaultsKey.cacheV: rec.cacheV,
            DefaultsKey.enableFlash: rec.flash,
            DefaultsKey.threadCount: rec.threads,
        ])
    }
    
    func recommendedSettings(for model: LLMModel?) -> RecommendedSettings {
        let sizeB = estimatedBillions(for: model)
        let ram = ramGB > 0 ? ramGB : 16
        
        var ctx = 32768, batch = 512, nGpu = 80
        var cK = "q4_0", cV = "q4_0"
        var flash = (chipFamily == .m2 || chipFamily == .m3 || chipFamily == .m4)
        let threads = max(1, ProcessInfo.processInfo.activeProcessorCount - 2)
        
        if ram <= 8 {
            ctx = sizeB <= 4 ? 8192 : 4096
            batch = 256
            nGpu = sizeB <= 4 ? 48 : 28
            flash = false
        } else if ram <= 16 {
            ctx = 32768
            batch = 512
            nGpu = sizeB <= 7 ? 999 : 64
            cK = "q4_1"
            cV = "q4_1"
        } else {
            ctx = 32768
            batch = 1024
            nGpu = 999
            cK = "q5_0"
            cV = "q5_0"
        }
        
        let cPlan = planContextSize(desired: ctx, sizeB: sizeB)
        let summary = "ctx=\(cPlan.value), gpu=\(nGpu), KV=\(cK)/\(cV)"
        let note = plannerNote(sizeB: sizeB, ram: ram, chip: chipFamily, ctx: cPlan.value, batch: batch, nGpu: nGpu, cacheK: cK, cacheV: cV, flash: flash, warning: cPlan.warning)
        return RecommendedSettings(ctx: cPlan.value, batch: batch, nGpu: nGpu, cacheK: cK, cacheV: cV, flash: flash, threads: threads, summary: summary, warning: cPlan.warning, note: note)
    }
    
    func refreshRuntimePlanner() {
        let sizeB = estimatedBillions(for: selectedModel)
        let resolved = resolveContextPlan(sizeB: sizeB)
        effectiveCtxSize = resolved.value
        contextWarning = resolved.warning
        let ram = max(ramGB, 8)
        let note = "Runtime ctx plan: \(resolved.value) on \(ram)GB, model ~\(sizeB)B."
        appendLog(note)
    }
    
    private func plannerNote(sizeB: Double, ram: Int, chip: ChipFamily, ctx: Int, batch: Int, nGpu: Int, cacheK: String, cacheV: String, flash: Bool, warning: String?) -> String {
        var parts: [String] = []
        parts.append("Model ~\(sizeB)B on \(ram)GB \(chip.rawValue)")
        parts.append("ctx=\(ctx), batch=\(batch), gpuLayers=\(nGpu)")
        parts.append("KV=\(cacheK)/\(cacheV)")
        if flash { parts.append("FlashAttn=ON") }
        if let w = warning { parts.append("Warning: \(w)") }
        return parts.joined(separator: " | ")
    }
    
    private func resolveContextPlan(sizeB: Double) -> (value: Int, warning: String?) {
        if manualContextOverride {
            return (ctxSize, "Manual override in effect. Host will not down-tune context.")
        }
        return planContextSize(desired: ctxSize, sizeB: sizeB)
    }
    
    private func estimatedBillions(for model: LLMModel?) -> Double {
        guard let name = model?.filename.lowercased() else { return 7.0 }
        if name.contains("32b") { return 32.0 }
        if name.contains("14b") { return 14.0 }
        if name.contains("8b")  { return 8.0 }
        if name.contains("7b")  { return 7.0 }
        if name.contains("3b")  { return 3.0 }
        if name.contains("1b")  { return 1.0 }
        return 7.0
    }
    
    private func planContextSize(desired: Int, sizeB: Double) -> (value: Int, warning: String?) {
        let ram = max(ramGB, 8)
        let ceiling = ram <= 8 ? (sizeB <= 4 ? 16384 : 8192) : (ram <= 16 ? 32768 : 65536)
        let val = min(desired, ceiling)
        let warn = desired > ceiling ? "Requested ctx \(desired) > safe ceiling \(ceiling) for ~\(sizeB)B on \(ram)GB. Using \(val)." : nil
        return (val, warn)
    }
    
    private func modelAlias(for model: LLMModel) -> String {
        let base = model.filename.replacingOccurrences(of: ".gguf", with: "")
        return base.replacingOccurrences(of: " ", with: "_")
    }
    
    // MARK: - Logging Utils
    private func ensureLogFile() {
        if !FileManager.default.fileExists(atPath: logFile.path) {
            FileManager.default.createFile(atPath: logFile.path, contents: nil)
        }
    }
    
    private enum LogLevel: String {
        case info = "INFO"
        case error = "ERROR"
        case debug = "DEBUG"
    }

    private func appendLog(_ message: String, level: LogLevel = .info) {
        guard level != .debug || debugMode else { return }
        lastLogTimestamp = Date()
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] [\(level.rawValue)] \(message)\n"
        let logTarget = logFile
        logWriteQueue.async {
            do {
                let handle = try FileHandle(forWritingTo: logTarget)
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                if let data = line.data(using: .utf8) {
                    handle.write(data)
                }
            } catch {
                // Ignore logging errors; failure shouldn't crash the UI.
            }
        }
    }

    private func appendDebugLog(_ message: String) {
        appendLog(message, level: .debug)
    }
    
    private func startLogMonitor() {
        let fd = open(logFile.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend], queue: .main)
        source.setEventHandler { [weak self] in self?.updateLogTail() }
        source.setCancelHandler { close(fd) }
        logMonitor = source
        source.resume()
    }
    
    private func updateLogTail() {
        guard let handle = try? FileHandle(forReadingFrom: logFile) else { return }
        defer { try? handle.close() }
        let tailBytes: UInt64 = 64 * 1024
        let fileSize = (try? handle.seekToEnd()) ?? 0
        let readOffset = fileSize > tailBytes ? fileSize - tailBytes : 0
        try? handle.seek(toOffset: readOffset)
        let data = handle.readDataToEndOfFile()
        let str = String(data: data, encoding: .utf8) ?? ""
        logTail = str.components(separatedBy: "\n").suffix(100).joined(separator: "\n")
        lastLogTimestamp = Date()
    }

    // MARK: - Persistence
    private func updateProfileDetail() {
        profileDetail = profile.detail
        persist(profile.rawValue, for: DefaultsKey.profile)
    }

    private func loadSettings() {
        if let v = defaults.string(forKey: DefaultsKey.host) { host = v }
        if let v = defaults.object(forKey: DefaultsKey.port) as? Int { port = v }
        if let v = defaults.object(forKey: DefaultsKey.ctxSize) as? Int { ctxSize = v }
        if let v = defaults.object(forKey: DefaultsKey.batchSize) as? Int { batchSize = v }
        if let v = defaults.object(forKey: DefaultsKey.nGpuLayers) as? Int { nGpuLayers = v }
        if let v = defaults.object(forKey: DefaultsKey.threadCount) as? Int { threadCount = v }
        if let v = defaults.string(forKey: DefaultsKey.cacheK) { cacheTypeK = v }
        if let v = defaults.string(forKey: DefaultsKey.cacheV) { cacheTypeV = v }
        if let v = defaults.object(forKey: DefaultsKey.enableFlash) as? Bool { enableFlashAttention = v }
        if let v = defaults.object(forKey: DefaultsKey.enableRopeScaling) as? Bool { enableRopeScaling = v }
        if let v = defaults.object(forKey: DefaultsKey.ropeScalingValue) as? Double { ropeScalingValue = v }
        if let v = defaults.object(forKey: DefaultsKey.enableAutoKV) as? Bool { enableAutoKV = v }
        if let v = defaults.string(forKey: DefaultsKey.selectedModel),
           let url = try? FileManager.default.contentsOfDirectory(at: modelsDir, includingPropertiesForKeys: nil).first(where: { $0.lastPathComponent == v }) {
            selectedModel = LLMModel(filename: v, fullPath: url)
        }
        if let v = defaults.string(forKey: DefaultsKey.profile), let p = LLMProfile(rawValue: v) { profile = p }
        if let v = defaults.string(forKey: DefaultsKey.extraArgsRaw) { extraArgsRaw = v }
        if let v = defaults.string(forKey: DefaultsKey.customURL) { customURL = v }
        if let v = defaults.string(forKey: DefaultsKey.customFilename) { customFilename = v }
        if let v = defaults.object(forKey: DefaultsKey.manualContextOverride) as? Bool { manualContextOverride = v }
        if let v = defaults.object(forKey: DefaultsKey.autoApplyRecommended) as? Bool { autoApplyRecommended = v }
        if let v = defaults.object(forKey: DefaultsKey.autoThrottleMemory) as? Bool { autoThrottleMemory = v }
        if let v = defaults.object(forKey: DefaultsKey.autoReduceRuntimeOnPressure) as? Bool { autoReduceRuntimeOnPressure = v }
        if let v = defaults.object(forKey: DefaultsKey.autoSwitchQuantOnPressure) as? Bool { autoSwitchQuantOnPressure = v }
    }

    private func persist<T>(_ value: T?, for key: String) {
        guard !isRestoringSettings && !isBatchPersistingSettings else { return }
        if let value = value { defaults.set(value, forKey: key) }
        else { defaults.removeObject(forKey: key) }
    }

    private func persistBatch(_ values: [String: Any?]) {
        guard !isRestoringSettings else { return }
        for (key, value) in values {
            if let value = value {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }
    
    // MARK: - Context Compression
    // (Intentionally left to higher-level agents/clients; host stays mechanical.)
}
