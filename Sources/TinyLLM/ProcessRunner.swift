import Foundation

/// A lightweight utility for running shell commands and capturing output.
/// This is used for small, short-lived operations (not for llama-server).
enum ProcessRunner {
    
    // MARK: - Run a command and capture output
    
    /// Runs a command synchronously.
    /// Returns (exitCode, stdout, stderr).
    static func run(
        _ executable: String,
        _ args: [String] = [],
        in directory: URL? = nil
    ) -> (code: Int32, out: String, err: String) {
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        
        if let dir = directory {
            process.currentDirectoryURL = dir
        }
        
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        
        do {
            try process.run()
        } catch {
            return (-1, "", "Failed to start process: \(error.localizedDescription)")
        }
        
        process.waitUntilExit()
        
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        
        let outStr = String(data: outData, encoding: .utf8) ?? ""
        let errStr = String(data: errData, encoding: .utf8) ?? ""
        
        return (process.terminationStatus, outStr, errStr)
    }
    
    // MARK: - Capture single string output (convenience)
    
    static func readString(
        _ executable: String,
        _ args: [String] = [],
        in directory: URL? = nil
    ) -> String {
        let result = run(executable, args, in: directory)
        return result.out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Run asynchronously (detached)
    
    /// Runs a command in the background without waiting for output.
    /// Useful for operations that don't need to report back.
    @discardableResult
    static func runDetached(
        _ executable: String,
        _ args: [String] = [],
        in directory: URL? = nil
    ) -> Bool {
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        
        if let dir = directory {
            process.currentDirectoryURL = dir
        }
        
        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }
    
    // MARK: - Which
    
    /// Returns the absolute path of a binary (like "which" on macOS/Linux).
    static func which(_ command: String) -> String? {
        let (code, out, _) = run("/usr/bin/which", [command])
        return code == 0 ? out.trimmingCharacters(in: .whitespacesAndNewlines) : nil
    }
}
