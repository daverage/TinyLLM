import Darwin
import Foundation
import IOKit
import IOKit.ps

struct HardwareSpecs {
    let ramGB: Int
    let chipFamily: ChipFamily
    let gpuName: String
    let supportsFlashAttention: Bool
}
@MainActor
enum HardwareService {

    // MARK: - Main entrypoint
    /// Returns a full hardware snapshot used by LLMManager.
    static func detectSpecs(serverBinary: URL?) async -> HardwareSpecs {
        let ram = detectRAM()
        let chip = detectChipFamily()
        let gpu = detectGPUName()
        let flash = detectFlashAttentionSupport(serverBinary: serverBinary)

        return HardwareSpecs(
            ramGB: ram,
            chipFamily: chip,
            gpuName: gpu,
            supportsFlashAttention: flash
        )
    }

    // MARK: - RAM detection
    /// Returns system RAM in whole GiB with memoization.
    static func detectRAM() -> Int {
        ramCacheLock.lock()
        if let cached = cachedRAMGB {
            ramCacheLock.unlock()
            return cached
        }
        ramCacheLock.unlock()

        var size: UInt64 = 0
        var len = MemoryLayout<UInt64>.size
        let result = sysctlbyname("hw.memsize", &size, &len, nil, 0)

        let computed: Int
        if result == 0 {
            let gb = Double(size) / 1024 / 1024 / 1024
            computed = max(4, Int(gb.rounded()))
        } else {
            computed = 8  // fallback
        }

        ramCacheLock.lock()
        cachedRAMGB = computed
        ramCacheLock.unlock()
        return computed
    }

    // MARK: - CPU / chip detection

    static func detectChipFamily() -> ChipFamily {
        // Apple Silicon check
        if let cstr = sysctlString("machdep.cpu.brand_string")?.lowercased() {
            if cstr.contains("m1") { return .m1 }
            if cstr.contains("m2") { return .m2 }
            if cstr.contains("m3") { return .m3 }
            if cstr.contains("m4") { return .m4 }
            if cstr.contains("apple") { return .m1 }  // generic fallback
        }

        // Fallback: Intel or Unknown
        if let arch = sysctlString("hw.machine")?.lowercased(),
            arch.contains("x86")
        {
            return .intel
        }

        return .unknown
    }

    // MARK: - GPU name / Metal device

    static func detectGPUName() -> String {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPCIDevice")
        )
        guard service != 0 else { return "Unknown GPU" }
        defer { IOObjectRelease(service) }

        return ioName(service) ?? "Unknown GPU"
    }

    private static func ioName(_ service: io_service_t) -> String? {
        let key = "model" as CFString
        guard
            let cfValue = IORegistryEntryCreateCFProperty(service, key, kCFAllocatorDefault, 0)?
                .takeRetainedValue()
        else {
            return nil
        }

        if let data = cfValue as? Data,
            let str = String(data: data, encoding: .utf8)
        {
            return str.trimmingCharacters(in: .controlCharacters)
        }

        if let str = cfValue as? String {
            return str.trimmingCharacters(in: .controlCharacters)
        }

        return nil
    }

    // MARK: - System memory usage (global)

    /// Returns memory pressure as a string "62.5%"
    static func getMemoryUsagePercent() -> String {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)

        let hostPort: mach_port_t = mach_host_self()

        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(
                to: integer_t.self,
                capacity: Int(count)
            ) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return "0%" }

        var pageSize: vm_size_t = 0
        host_page_size(hostPort, &pageSize)

        let active = Double(stats.active_count) * Double(pageSize)
        let wired = Double(stats.wire_count) * Double(pageSize)
        let spec = Double(stats.speculative_count) * Double(pageSize)
        let compressed = Double(stats.compressor_page_count) * Double(pageSize)

        let used = active + wired + spec + compressed
        let total = Double(detectRAM()) * 1024 * 1024 * 1024

        let pct = (used / total) * 100
        return String(format: "%.1f%%", pct)
    }

    // MARK: - CPU load fallback

    /// Returns load average (1 min) as a pseudo CPU% fallback.
    static func getCPULoad() -> String {
        var load = [Double](repeating: 0, count: 3)
        let size = load.count
        let res = getloadavg(&load, Int32(size))

        if res > 0 {
            let pct = load[0] * 100 / Double(ProcessInfo.processInfo.activeProcessorCount)
            return String(format: "%.1f%%", pct)
        }
        return "0%"
    }

    // MARK: - Helper: sysctl string

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        sysctlbyname(name, nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: size)
        let result = sysctlbyname(name, &buffer, &size, nil, 0)
        if result == 0 {
            let bytes = buffer.map { UInt8(bitPattern: $0) }
            return String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .controlCharacters)
        }
        return nil
    }

    // MARK: - RAM cache
    private static var cachedRAMGB: Int?

    private static let ramCacheLock = NSLock()
    
    private static func detectFlashAttentionSupport(serverBinary: URL?) -> Bool {
        guard let binary = serverBinary else { return false }
        guard FileManager.default.fileExists(atPath: binary.path) else { return false }

        let result = ProcessRunner.run(binary.path, ["--help"])
        guard result.code == 0 else { return false }
        return result.out.lowercased().contains("flash-attn")
    }
}
