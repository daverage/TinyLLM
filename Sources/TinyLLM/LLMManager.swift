import Foundation
import SwiftUI

struct RuntimeMetrics: Equatable {
    var systemMemPercent: Double?
    var llmMemPercent: Double?
    var llmCPUPercent: Double?
    var thermalState: ThermalState = .nominal

    var systemMemoryDisplay: String {
        guard let value = systemMemPercent else { return "—" }
        return Self.formatPercent(value)
    }

    var llmMemoryDisplay: String {
        guard let value = llmMemPercent else { return "—" }
        return Self.formatPercent(value)
    }

    var llmCPUDisplay: String {
        guard let value = llmCPUPercent else { return "—" }
        return Self.formatPercent(value)
    }

    var memorySummary: String {
        let system = systemMemoryDisplay
        if let llm = llmMemPercent {
            return "\(system) · LLM \(Self.formatPercent(llm))"
        }
        return system
    }

    private static func formatPercent(_ value: Double) -> String {
        String(format: "%.1f%%", value)
    }
}

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

private extension MemoryPressureLevel {
    var severity: Int {
        switch self {
        case .low: return 0
        case .moderate: return 1
        case .high: return 2
        case .critical: return 3
        }
    }
}

enum GPUAggressiveness: String, CaseIterable, Identifiable {
    case low
    case balanced
    case high
    case max

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low: return "Low"
        case .balanced: return "Balanced"
        case .high: return "High"
        case .max: return "Max"
        }
    }

    var index: Int {
        switch self {
        case .low: return 0
        case .balanced: return 1
        case .high: return 2
        case .max: return 3
        }
    }
}

enum HostPerformanceProfile: String, CaseIterable, Identifiable {
    case quiet
    case balanced
    case performance

    var id: String { rawValue }

    var label: String {
        switch self {
        case .quiet: return "Quiet"
        case .balanced: return "Balanced"
        case .performance: return "Performance"
        }
    }

    var detail: String {
        switch self {
        case .quiet:
            return "Lower threads/GPU/batch for minimal host impact."
        case .balanced:
            return "Current defaults tuned for stability."
        case .performance:
            return "Maximize throughput with aggressive batching."
        }
    }
}

enum LogDisplayMode: String, CaseIterable, Identifiable {
    case host
    case server
    case combined

    var id: String { rawValue }

    var label: String {
        switch self {
        case .host: return "Host"
        case .server: return "Server"
        case .combined: return "Combined"
        }
    }
}

@MainActor
final class LLMManager: ObservableObject {
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    
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
    var serverLogFile: URL { appSupportRoot.appendingPathComponent("llama-server.log") }
    var hostLogFile: URL { appSupportRoot.appendingPathComponent("tinyllm.log") }
    
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
        static let debugMode = "TinyLLM.debugMode"
        static let gpuAggressiveness = "TinyLLM.gpuAggressiveness"
        static let performanceProfile = "TinyLLM.performanceProfile"
    }
    
    // MARK: - Published Config
    @Published var host: String = "127.0.0.1" { didSet { persist(host, for: DefaultsKey.host) } }
    @Published var port: Int = 8000 { didSet { persist(port, for: DefaultsKey.port) } }
    @Published var ctxSize: Int = 32768 { didSet { persist(ctxSize, for: DefaultsKey.ctxSize) } }
    @Published var batchSize: Int = 512 { didSet { persist(batchSize, for: DefaultsKey.batchSize) } }
    @Published var nGpuLayers: Int = 80 { didSet { persist(nGpuLayers, for: DefaultsKey.nGpuLayers) } }
    @Published var gpuAggressiveness: GPUAggressiveness = .balanced {
        didSet { persist(gpuAggressiveness.rawValue, for: DefaultsKey.gpuAggressiveness) }
    }
    @Published var hostPerformanceProfile: HostPerformanceProfile = .balanced {
        didSet {
            persist(hostPerformanceProfile.rawValue, for: DefaultsKey.performanceProfile)
            guard !isRestoringSettings else { return }
            applyPerformanceProfile(hostPerformanceProfile)
        }
    }
    @Published var threadCount: Int = 4 { didSet { persist(threadCount, for: DefaultsKey.threadCount) } }
    
    // Advanced Config
    @Published var cacheTypeK: String = "q4_0" { didSet { persist(cacheTypeK, for: DefaultsKey.cacheK) } }
    @Published var cacheTypeV: String = "q4_0" { didSet { persist(cacheTypeV, for: DefaultsKey.cacheV) } }
    @Published var enableFlashAttention: Bool = false { didSet { persist(enableFlashAttention, for: DefaultsKey.enableFlash) } }
    @Published var flashAttentionSupported: Bool = false
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
    @Published var logDisplayMode: LogDisplayMode = .host {
        didSet {
            Task {
                await performLogTailUpdate()
            }
        }
    }
    @Published private(set) var runtimeMetrics = RuntimeMetrics()
    @Published var hardwareSummary: String = "Detecting…"
    @Published var gpuSummary: String = "Detecting…"
    
    @Published var healthState: ServerHealthState = .stopped
    @Published var healthNote: String = "Idle"
    
    // Planners / Diagnostics
    @Published var recommendedSummary: String = "Not computed yet"
    @Published var currentRecommendedSettings: RecommendedSettings?
    @Published var effectiveCtxSize: Int = 32768
    @Published var contextWarning: String? = nil
    @Published var debugMode: Bool = false {
        didSet {
            persist(debugMode, for: DefaultsKey.debugMode)
            if debugMode {
                appendLog("Debug mode enabled", level: .info)
            } else {
                appendLog("Debug mode disabled", level: .info)
            }
        }
    }
    @Published var lastBuildDurationSeconds: Double? = nil
    
    // Helpers
    private var hostLogMonitor: DispatchSourceFileSystemObject?
    private var serverLogMonitor: DispatchSourceFileSystemObject?
    private var logTailUpdateTask: Task<Void, Never>?
    private var logTailUpdatePending = false
    private let logTailThrottleInterval: UInt64 = 200_000_000
    private let logTailReadBytes: UInt64 = 32 * 1024
    private let logWriteQueue = DispatchQueue(label: "TinyLLM.logWriter", qos: .utility)

    private var runtimeTask: Task<Void, Never>?
    private var isBatchPersistingSettings = false
    private var lastLogTimestamp: Date?
    private var lastKnownPID: Int32?
    private var lastMemoryWarning: Date?
    private var highMemoryPressureDetectedAt: Date?
    private let memoryPressureGracePeriod: TimeInterval = 6.0
    private var lastAutoThrottleTimestamp: Date?
    private var lastAutoRuntimeThrottleTimestamp: Date?
    private var lastAutoQuantSwitchTimestamp: Date?
    private let autoMemoryCooldown: TimeInterval = 60
    private var startupSafeFallbackApplied = false
    private var isApplyingPerformanceProfile = false
    
    // System Specs Cache
    private var ramGB: Int = 0
    private var chipFamily: ChipFamily = .unknown
    
    var openAIApiBase: String { "http://\(host):\(port)/v1" }
    var maxThreadCount: Int { ProcessInfo.processInfo.activeProcessorCount }
    var recommendedGpuLayerBase: Int {
        recommendedGpuLayerBase(for: max(ramGB, 8), sizeB: estimatedBillions(for: selectedModel), aggressiveness: gpuAggressiveness)
    }
    
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
        
        ensureLogFiles()
        startLogMonitor()
        startRuntimeMonitoring()
        refreshModels()
        
        Task {
            // Detect hardware async, then update UI
            let specs = await HardwareService.detectSpecs(serverBinary: serverBinary)
            self.ramGB = specs.ramGB
            self.chipFamily = specs.chipFamily
            self.hardwareSummary = "Chip: \(specs.chipFamily.rawValue), RAM: \(specs.ramGB) GB"
            self.gpuSummary = specs.gpuName
            self.flashAttentionSupported = specs.supportsFlashAttention
            if !specs.supportsFlashAttention {
                self.enableFlashAttention = false
            }
            
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
                self.applyPerformanceProfile(self.hostPerformanceProfile)
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

        appendDebugLog("Refreshing models from: \(modelsDir.path)")

        var models: [LLMModel] = []
        if let contents = try? FileManager.default.contentsOfDirectory(at: modelsDir, includingPropertiesForKeys: nil) {
            appendDebugLog("Found \(contents.count) files in models directory")

            let ggufFiles = contents.filter { $0.pathExtension.lowercased() == "gguf" }
            appendDebugLog("Found \(ggufFiles.count) .gguf files")

            models = ggufFiles
                .map { LLMModel(filename: $0.lastPathComponent, fullPath: $0) }
                .sorted { $0.filename < $1.filename }

            for model in models {
                appendDebugLog("  - \(model.filename)")
            }
        } else {
            appendDebugLog("Failed to read models directory")
        }

        availableModels = models
        appendDebugLog("Updated availableModels to \(models.count) items")

        await updateModelIndexEntries(with: models)

        if selectedModel == nil || !availableModels.contains(where: { $0.filename == selectedModel?.filename }) {
            selectedModel = availableModels.first
            if let first = availableModels.first {
                appendDebugLog("Auto-selected model: \(first.filename)")
            }
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

        // Adaptive batch size based on memory pressure and thermal state
        let adaptiveBatch = computeAdaptiveBatchSize(baseBatch: batchSize)

        // Thermal-aware GPU layer reduction
        let recommendedGpuBase = recommendedGpuLayerBase(for: max(ramGB, 8), sizeB: sizeB, aggressiveness: gpuAggressiveness)
        let baseGpu = min(nGpuLayers, recommendedGpuBase)
        let adaptiveGpuLayers = computeAdaptiveGpuLayers(baseGpu: baseGpu)

        let cacheFromCtx = max(128, resolvedCtx.value / 4)
        let cacheRamMB = min(max(ramGB, 8) * 256, cacheFromCtx)

        // Args
        var args: [String] = [
            "-m", model.fullPath.path,
            "--host", host, "--port", String(port),
            "--n-gpu-layers", String(adaptiveGpuLayers),
            "--ctx-size", String(resolvedCtx.value),
            "--batch-size", String(adaptiveBatch),
            "--threads", String(threadCount),
            "--temp", String(format: "%.2f", profile.temp),
            "--top-p", String(format: "%.2f", profile.topP),
            "--cache-type-k", cacheTypeK,
            "--cache-type-v", cacheTypeV,
            "--cache-ram", String(cacheRamMB)
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
                let pid = try await processService.startAsync(executable: serverBinary, args: args, outputToFile: serverLogFile)
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
                    outputToFile: serverLogFile
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
                    outputToFile: serverLogFile
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
                outputToFile: serverLogFile
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
                    outputToFile: serverLogFile
                )
                if code == 0 {
                    appendLog("Download completed: \(dest.path)")
                    let fileExists = FileManager.default.fileExists(atPath: dest.path)
                    appendLog("File exists after download: \(fileExists)")

                    if fileExists {
                        if let attrs = try? FileManager.default.attributesOfItem(atPath: dest.path),
                           let size = attrs[.size] as? Int64 {
                            appendLog("Downloaded file size: \(size) bytes")
                        }
                    }

                    await refreshModelsAsync()
                    await MainActor.run {
                        statusText = "Downloaded \(filename)"
                    }
                } else {
                    await MainActor.run {
                        statusText = "Download failed (exit code: \(code))"
                        appendLog("Download failed with exit code: \(code)", level: .error)
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
    func requestRuntimeUpdate() {
        Task {
            await updateRuntimeState()
        }
    }

    @MainActor
    private func updateRuntimeState() async {
        let systemMemoryPercent = percentValue(from: HardwareService.getMemoryUsagePercent())
        var newMetrics = runtimeMetrics
        newMetrics.systemMemPercent = systemMemoryPercent
        newMetrics.thermalState = ThermalService.readThermalState()

        var pid: Int32?
        var processMetrics: ProcessMetrics?

        if await processService.isRunning(), let runningPID = await processService.getPID() {
            pid = runningPID
            if let snapshot = await processService.getProcessMetrics(pid: runningPID) {
                newMetrics.llmCPUPercent = percentValue(from: snapshot.cpuPercent)
                newMetrics.llmMemPercent = percentValue(from: snapshot.memPercent)
                processMetrics = snapshot
            } else {
                newMetrics.llmCPUPercent = nil
                newMetrics.llmMemPercent = nil
            }
        } else {
            newMetrics.llmCPUPercent = nil
            newMetrics.llmMemPercent = nil
        }

        runtimeMetrics = newMetrics
        maybeAdjustForMemory()
        applyStartupSafeFallbackIfNeeded()
        await pollHealth(pid: pid, metrics: processMetrics)
    }
    
    var memoryPressure: MemoryPressureLevel {
        let systemLevel = memoryPressureLevel(forSystem: runtimeMetrics.systemMemPercent)
        let llmLevel = memoryPressureLevel(forLLM: runtimeMetrics.llmMemPercent)
        return systemLevel.severity >= llmLevel.severity ? systemLevel : llmLevel
    }
    
    private func maybeAdjustForMemory() {
        switch memoryPressure {
        case .low, .moderate:
            highMemoryPressureDetectedAt = nil
        case .high, .critical:
            let now = Date()
            if let last = lastMemoryWarning, now.timeIntervalSince(last) < 60 {
                break
            }
            lastMemoryWarning = now
            appendLog("High memory pressure detected (\(runtimeMetrics.memorySummary)). Consider reducing context size, batch size, or choosing a smaller model.", level: .info)
        }

        if shouldTriggerAutoMemoryActions() {
            handleAutoMemoryActions()
        }
    }

    private func memoryPressureLevel(forSystem value: Double?) -> MemoryPressureLevel {
        guard let used = value else { return .low }
        switch used {
        case ..<60: return .low
        case 60..<75: return .moderate
        case 75..<90: return .high
        default: return .critical
        }
    }

    private func memoryPressureLevel(forLLM value: Double?) -> MemoryPressureLevel {
        guard let used = value else { return .low }
        switch used {
        case ..<15: return .low
        case 15..<25: return .moderate
        case 25..<35: return .high
        default: return .critical
        }
    }

    private func applyStartupSafeFallbackIfNeeded() {
        guard !startupSafeFallbackApplied, !manualContextOverride else { return }
        guard memoryPressure == .high || memoryPressure == .critical else { return }

        startupSafeFallbackApplied = true
        let safePlan = planContextSize(desired: 16384, sizeB: estimatedBillions(for: selectedModel))
        let safeCtx = max(4096, min(ctxSize, safePlan.value))
        ctxSize = safeCtx
        batchSize = max(64, min(batchSize, 256))
        nGpuLayers = max(16, min(nGpuLayers, 32))
        contextWarning = "High memory pressure at launch forced safer context/batch defaults."
        appendLog("Startup fallback: ctx \(ctxSize), batch \(batchSize), GPU \(nGpuLayers) due to high pressure.", level: .info)
    }

    private func shouldTriggerAutoMemoryActions() -> Bool {
        guard autoThrottleMemory || autoReduceRuntimeOnPressure || autoSwitchQuantOnPressure else {
            highMemoryPressureDetectedAt = nil
            return false
        }

        switch memoryPressure {
        case .high, .critical:
            let now = Date()
            if let start = highMemoryPressureDetectedAt {
                if now.timeIntervalSince(start) >= memoryPressureGracePeriod {
                    highMemoryPressureDetectedAt = now
                    return true
                }
                return false
            } else {
                highMemoryPressureDetectedAt = now
                return false
            }
        default:
            highMemoryPressureDetectedAt = nil
            return false
        }
    }

    private func handleAutoMemoryActions() {
        // Only run auto-memory actions if server is running
        guard isRunning else { return }

        appendDebugLog("Memory pressure \(memoryPressure.rawValue) (\(runtimeMetrics.memorySummary)), autoThrottle=\(autoThrottleMemory), autoReduce=\(autoReduceRuntimeOnPressure), autoSwitch=\(autoSwitchQuantOnPressure)")
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
    
    private func startRuntimeMonitoring() {
        stopRuntimeMonitoring()
        runtimeTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.updateRuntimeState()
                do {
                    try await Task.sleep(nanoseconds: 3_000_000_000)
                } catch {
                    break
                }
            }
        }
    }
    
    func stopRuntimeMonitoring() {
        runtimeTask?.cancel()
        runtimeTask = nil
    }
    
    private func pollHealth(pid: Int32?, metrics: ProcessMetrics?) async {
        if !(await processService.isRunning()) {
            if isRunning {
                healthState = .crashed
                healthNote = "Server not running (unexpected)"
                isRunning = false
            } else {
                healthState = .stopped
                healthNote = "Server stopped"
            }
            return
        }
        
        guard let pid = pid else {
            healthState = .degraded
            healthNote = "Server running but PID missing"
            return
        }

        guard let metrics = metrics else {
            healthState = .degraded
            healthNote = "Unable to read server metrics"
            return
        }

        lastKnownPID = pid
        let cpuString = metrics.cpuPercent.trimmingCharacters(in: .whitespacesAndNewlines)
        let cpuValue = Double(cpuString.replacingOccurrences(of: "%", with: "")) ?? 0
        let lastLogAge = lastLogTimestamp.map { Date().timeIntervalSince($0) } ?? .infinity
        
        if cpuValue < 1.0 && lastLogAge > 60 {
            healthState = .degraded
            healthNote = "Possible stall: no log activity for \(Int(lastLogAge))s, CPU \(metrics.cpuPercent)"
        } else {
            healthState = .healthy
            healthNote = "Server OK (CPU \(metrics.cpuPercent), mem \(runtimeMetrics.memorySummary))"
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
        clearProcessMetrics()
        didStopServer(intentional: intentional)
        appendLog("Server stopped.")
    }

    private func clearProcessMetrics() {
        var refreshed = runtimeMetrics
        refreshed.llmCPUPercent = nil
        refreshed.llmMemPercent = nil
        runtimeMetrics = refreshed
    }

    private func percentValue(from text: String) -> Double? {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "%", with: "")
        guard !cleaned.isEmpty else { return nil }
        return Double(cleaned)
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
        applyPerformanceProfile(hostPerformanceProfile)
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
        applyPerformanceProfile(hostPerformanceProfile)
    }
    
    func recommendedSettings(for model: LLMModel?) -> RecommendedSettings {
        let sizeB = estimatedBillions(for: model)
        let ram = ramGB > 0 ? ramGB : 16
        
        var ctx = 32768, batch = 512, nGpu = 80
        var cK = "q4_0", cV = "q4_0"
        var flash = (chipFamily == .m2 || chipFamily == .m3 || chipFamily == .m4)
        let threads = max(1, ProcessInfo.processInfo.activeProcessorCount - 2)
        
        if ram <= 8 {
            ctx = sizeB <= 4 ? 16384 : 8192
            batch = 256
            flash = false
        } else if ram <= 16 {
            // For 16GB, use higher context on M3/M4 with efficient unified memory
            let isModernChip = (chipFamily == .m3 || chipFamily == .m4)
            ctx = isModernChip && sizeB <= 7 ? 49152 : 32768
            batch = 512
            cK = "q4_1"
            cV = "q4_1"
        } else {
            let isModernChip = (chipFamily == .m3 || chipFamily == .m4)
            if ram < 32 {
                ctx = isModernChip ? 98304 : 65536
            } else {
                ctx = isModernChip ? 131072 : 98304
            }
            batch = 1024
            cK = "q5_0"
            cV = "q5_0"
        }
        
        let recommendedGpu = recommendedGpuLayerBase(for: ram, sizeB: sizeB, aggressiveness: gpuAggressiveness)
        nGpu = recommendedGpu

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
    
    private func computeAdaptiveBatchSize(baseBatch: Int) -> Int {
        var adaptedBatch = baseBatch

        // Reduce batch size under memory pressure
        switch memoryPressure {
        case .low, .moderate:
            break
        case .high:
            adaptedBatch = max(128, Int(Double(adaptedBatch) * 0.75))
        case .critical:
            adaptedBatch = max(64, Int(Double(adaptedBatch) * 0.5))
        }

        // Further reduce under thermal stress
        switch runtimeMetrics.thermalState {
        case .nominal, .moderate:
            break
        case .heavy:
            adaptedBatch = max(64, Int(Double(adaptedBatch) * 0.75))
            appendDebugLog("Thermal state heavy: reduced batch to \(adaptedBatch)")
        case .hotspot:
            adaptedBatch = max(64, Int(Double(adaptedBatch) * 0.5))
            appendDebugLog("Thermal state hotspot: reduced batch to \(adaptedBatch)")
        }

        return adaptedBatch
    }

    private func computeAdaptiveGpuLayers(baseGpu: Int) -> Int {
        // Reduce GPU layer offloading under thermal stress to decrease Metal workload
        switch runtimeMetrics.thermalState {
        case .nominal:
            return baseGpu
        case .moderate:
            return baseGpu
        case .heavy:
            let reduced = max(32, Int(Double(baseGpu) * 0.66))
            if reduced != baseGpu {
                appendDebugLog("Thermal state heavy: reduced GPU layers from \(baseGpu) to \(reduced)")
            }
            return reduced
        case .hotspot:
            let reduced = max(16, Int(Double(baseGpu) * 0.33))
            if reduced != baseGpu {
                appendDebugLog("Thermal state hotspot: reduced GPU layers from \(baseGpu) to \(reduced)")
            }
            return reduced
        }
    }

    private func planContextSize(desired: Int, sizeB: Double) -> (value: Int, warning: String?) {
        let ram = max(ramGB, 8)
        let ceiling = contextCeiling(for: ram, sizeB: sizeB)
        let val = min(desired, ceiling)
        let warn = desired > ceiling ? "Requested ctx \(desired) > safe ceiling \(ceiling) for ~\(sizeB)B on \(ram)GB. Using \(val)." : nil
        return (val, warn)
    }

    private func applyPerformanceProfile(_ profile: HostPerformanceProfile) {
        guard !isApplyingPerformanceProfile else { return }
        isApplyingPerformanceProfile = true
        defer { isApplyingPerformanceProfile = false }

        let rec = recommendedSettings(for: selectedModel)
        let sizeB = estimatedBillions(for: selectedModel)
        let recommendedGpu = recommendedGpuLayerBase(for: max(ramGB, 8), sizeB: sizeB, aggressiveness: gpuAggressiveness)
        let baseGpu = max(rec.nGpu, 16)

        switch profile {
        case .quiet:
            threadCount = max(1, min(rec.threads, 4))
            batchSize = max(64, rec.batch / 2)
            nGpuLayers = max(16, min(baseGpu, recommendedGpu / 2))
        case .balanced:
            threadCount = rec.threads
            batchSize = rec.batch
            nGpuLayers = rec.nGpu
        case .performance:
            threadCount = maxThreadCount
            batchSize = min(4096, max(rec.batch * 2, 256))
            nGpuLayers = min(999, max(baseGpu, recommendedGpu))
        }
    }

    private func contextCeiling(for ram: Int, sizeB: Double) -> Int {
        let clampedRam = max(ram, 8)
        let isModernChip = (chipFamily == .m3 || chipFamily == .m4)

        switch clampedRam {
        case ...8:
            return sizeB <= 4 ? 16384 : 8192
        case ...16:
            if sizeB > 7 {
                return 32768
            }
            return isModernChip ? 49152 : 32768
        case 17...31:
            return isModernChip ? 98304 : 65536
        default:
            return 131072
        }
    }

    private func recommendedGpuLayerBase(for ram: Int, sizeB: Double, aggressiveness: GPUAggressiveness) -> Int {
        let clampedRam = max(ram, 8)
        let index = aggressiveness.index

        switch clampedRam {
        case ...8:
            let values = [30, 40, 50, 60]
            let base = values[index]
            if sizeB > 7 {
                return max(20, base - 10)
            }
            return base
        case ...16:
            let values = [80, 100, 110, 120]
            return values[index]
        case 17...31:
            let values = [120, 140, 160, 180]
            return values[index]
        default:
            let values = [256, 512, 768, 999]
            return values[index]
        }
    }
    
    private func modelAlias(for model: LLMModel) -> String {
        let base = model.filename.replacingOccurrences(of: ".gguf", with: "")
        return base.replacingOccurrences(of: " ", with: "_")
    }
    
    // MARK: - Logging Utils
    private func ensureLogFiles() {
        for file in [hostLogFile, serverLogFile] {
            if !FileManager.default.fileExists(atPath: file.path) {
                FileManager.default.createFile(atPath: file.path, contents: nil)
            }
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
        let timestamp = Self.isoFormatter.string(from: Date())
        let line = "[\(timestamp)] [\(level.rawValue)] \(message)\n"
        let logTarget = hostLogFile
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
        stopLogMonitor()
        hostLogMonitor = makeLogMonitor(for: hostLogFile)
        serverLogMonitor = makeLogMonitor(for: serverLogFile)
        scheduleLogTailUpdate()
    }

    private func stopLogMonitor() {
        hostLogMonitor?.cancel()
        hostLogMonitor = nil
        serverLogMonitor?.cancel()
        serverLogMonitor = nil
    }

    private func makeLogMonitor(for file: URL) -> DispatchSourceFileSystemObject? {
        let fd = open(file.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend], queue: .main)
        source.setEventHandler { [weak self] in
            self?.scheduleLogTailUpdate()
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        return source
    }
    
    private func scheduleLogTailUpdate() {
        logTailUpdatePending = true
        guard logTailUpdateTask == nil else { return }
        logTailUpdateTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { return }
                if !self.logTailUpdatePending { break }
                self.logTailUpdatePending = false
                do {
                    try await Task.sleep(nanoseconds: self.logTailThrottleInterval)
                } catch {
                    break
                }
                await self.performLogTailUpdate()
            }
            await MainActor.run {
                self?.logTailUpdateTask = nil
            }
        }
    }

    @MainActor
    private func performLogTailUpdate() async {
        let hostTail = readLastLines(from: hostLogFile)
        let serverTail = readLastLines(from: serverLogFile)

        switch logDisplayMode {
        case .host:
            logTail = hostTail
        case .server:
            logTail = serverTail
        case .combined:
            var combined: [String] = []
            if !hostTail.isEmpty {
                combined.append("=== Host ===")
                combined.append(hostTail)
            }
            if !serverTail.isEmpty {
                combined.append("=== Server ===")
                combined.append(serverTail)
            }
            logTail = combined.joined(separator: "\n")
        }

        lastLogTimestamp = Date()
    }

    private func readLastLines(from file: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return "" }
        defer { try? handle.close() }
        let fileSize = (try? handle.seekToEnd()) ?? 0
        let readOffset = fileSize > logTailReadBytes ? fileSize - logTailReadBytes : 0
        try? handle.seek(toOffset: readOffset)
        let data = handle.readDataToEndOfFile()
        let str = String(data: data, encoding: .utf8) ?? ""
        return str.components(separatedBy: "\n").suffix(100).joined(separator: "\n")
    }

    func clearLogs() {
        // Truncate the host log file
        do {
            try "".write(to: hostLogFile, atomically: true, encoding: .utf8)
            logTail = ""
            appendLog("Logs cleared by user")
        } catch {
            appendLog("Failed to clear host log file: \(error.localizedDescription)", level: .error)
        }
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
        if let v = defaults.object(forKey: DefaultsKey.debugMode) as? Bool { debugMode = v }
        if let v = defaults.string(forKey: DefaultsKey.gpuAggressiveness), let mode = GPUAggressiveness(rawValue: v) {
            gpuAggressiveness = mode
        }
        if let v = defaults.string(forKey: DefaultsKey.performanceProfile), let profile = HostPerformanceProfile(rawValue: v) {
            hostPerformanceProfile = profile
        }
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
