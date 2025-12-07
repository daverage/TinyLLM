import Foundation
import Darwin

struct ProcessMetrics {
    let cpuPercent: String   // e.g. "24.3%"
    let memPercent: String   // e.g. "1.2%"
}

actor ProcessService {
    private var process: Process?
    private var logTask: Task<Void, Never>?
    
    // MARK: - Synchronous commands (git, cmake, curl, etc.)
    
    /// Runs a command synchronously and returns the exit code.
    /// Good for git clone, cmake, curl, etc.
    func runSync(
        executable: String,
        args: [String],
        currentDir: URL? = nil,
        outputToFile: URL? = nil
    ) throws -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = args
        
        if let dir = currentDir {
            p.currentDirectoryURL = dir
        }
        
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        
        try p.run()
        p.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let str = String(data: data, encoding: .utf8),
           let logURL = outputToFile {
            appendToFile(url: logURL, text: str)
        }
        
        return p.terminationStatus
    }
    
    // MARK: - Async server process (llama-server)
    
    /// Starts llama-server asynchronously and returns its PID.
    func startAsync(
        executable: URL,
        args: [String],
        outputToFile: URL? = nil
    ) async throws -> Int32 {
        // If an old process is still around, kill it first.
        if let existing = process, existing.isRunning {
            existing.terminate()
        }
        
        let p = Process()
        p.executableURL = executable
        p.arguments = args
        
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        
        logTask?.cancel()
        logTask = nil

        if let logURL = outputToFile {
            // Stream output into the log file on a background queue.
            let handle = pipe.fileHandleForReading
            logTask = Task.detached {
                defer { try? handle.close() }
                await withTaskCancellationHandler(operation: {
                    while true {
                        if Task.isCancelled { break }
                        let data = handle.readData(ofLength: 4096)
                        if data.isEmpty { break }
                        if let chunk = String(data: data, encoding: .utf8) {
                            appendToFile(url: logURL, text: chunk)
                        }
                    }
                }, onCancel: {
                    try? handle.close()
                })
            }
        }
        
        try p.run()
        process = p
        return p.processIdentifier
    }
    
    /// Gracefully terminates the running server, if any.
    func terminate() async {
        guard let p = process else { return }
        if p.isRunning {
            p.terminate()
            // Give it a moment to die; if not, force kill.
            Task.detached { [weak p] in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if let proc = p, proc.isRunning {
                    kill(proc.processIdentifier, SIGKILL)
                }
            }
        }
        logTask?.cancel()
        logTask = nil
        process = nil
    }
    
    /// Returns true if the managed process is currently running.
    func isRunning() async -> Bool {
        if let p = process {
            return p.isRunning
        }
        return false
    }
    
    /// Returns the PID of the managed process, if any.
    func getPID() async -> Int32? {
        return process?.processIdentifier
    }
    
    // MARK: - Per-process metrics (CPU, MEM)
    
    /// Returns CPU and memory usage for a given PID using `ps`.
    func getProcessMetrics(pid: Int32) async -> ProcessMetrics? {
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-p", String(pid), "-o", "%cpu,%mem"]
        
        let pipe = Pipe()
        ps.standardOutput = pipe
        ps.standardError = pipe
        
        do {
            try ps.run()
            ps.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                return nil
            }
            
            // Example output:
            //  %CPU %MEM
            //  23.4  1.2
            let lines = output.split(separator: "\n").map { String($0) }
            guard lines.count >= 2 else { return nil }
            
            let parts = lines[1]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(whereSeparator: { $0.isWhitespace })
                .map { String($0) }
            
            guard parts.count >= 2 else { return nil }
            
            let cpuVal = parts[0]
            let memVal = parts[1]

            let cpu = cpuVal.hasSuffix("%") ? cpuVal : cpuVal + "%"
            let mem = memVal.hasSuffix("%") ? memVal : memVal + "%"

            return ProcessMetrics(cpuPercent: cpu, memPercent: mem)
        } catch {
            return nil
        }
    }
}

// MARK: - File append helper (global, non-actor)

private func appendToFile(url: URL, text: String) {
    if !FileManager.default.fileExists(atPath: url.path) {
        FileManager.default.createFile(atPath: url.path, contents: nil)
    }
    do {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        handle.seekToEndOfFile()
        if let data = text.data(using: .utf8) {
            handle.write(data)
        }
    } catch {
        // Ignore write failures; logging should never crash the app.
    }
}
