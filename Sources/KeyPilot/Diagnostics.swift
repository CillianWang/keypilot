import Foundation

/// Counts, durations and modes only. Never writes control text, titles, URLs or typed characters.
final class Diagnostics {
    static let shared=Diagnostics()
    private let queue=DispatchQueue(label:"dev.pingy.keypilot.diagnostics",qos:.utility)
    private let directory=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/KeyPilot",isDirectory:true)
    func record(_ name:String, _ fields:[String:Any]=[:]) {
        let uptime=ProcessInfo.processInfo.systemUptime
        queue.async {
            try? FileManager.default.createDirectory(at:self.directory,withIntermediateDirectories:true)
            let file=self.directory.appendingPathComponent("metrics.jsonl")
            if let attrs=try? FileManager.default.attributesOfItem(atPath:file.path), let size=attrs[.size] as? UInt64, size > 2_000_000 { try? FileManager.default.removeItem(at:file) }
            var row=fields; row["event"]=name; row["uptime"]=uptime
            guard let data=try? JSONSerialization.data(withJSONObject:row,options:.sortedKeys) else { return }
            if !FileManager.default.fileExists(atPath:file.path) { FileManager.default.createFile(atPath:file.path,contents:nil) }
            if let handle=try? FileHandle(forWritingTo:file) { defer { try? handle.close() }; _=try? handle.seekToEnd(); try? handle.write(contentsOf:data+Data([10])) }
        }
    }
    func ready(trusted:Bool, enabled:Bool, hotkeys:Bool,glassStyle:String,foldRowActions:Bool) {
        let data:[String:Any]=["pid":ProcessInfo.processInfo.processIdentifier,"trusted":trusted,"enabled":enabled,"hotkeys":hotkeys,"glass_style":glassStyle,"fold_row_actions":foldRowActions,"version":Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "development","build":Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "0"]
        queue.async {
            let path=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/KeyPilot/ready.json")
            try? FileManager.default.createDirectory(at:path.deletingLastPathComponent(),withIntermediateDirectories:true)
            if let bytes=try? JSONSerialization.data(withJSONObject:data,options:.sortedKeys) { try? bytes.write(to:path,options:.atomic) }
        }
    }
}

final class Cancellation {
    private let lock=NSLock()
    private var value=false
    func cancel() { lock.lock(); value=true; lock.unlock() }
    var cancelled:Bool { lock.lock(); defer {lock.unlock()}; return value }
}
