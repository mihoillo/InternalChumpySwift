import Foundation

/// A small in-memory ring buffer of tunnel log lines, mirrored into the
/// shared UserDefaults so the app can display the core log on the Stats tab.
///
/// The tunnel extension and the app run in separate processes, so the mirror
/// is the transport: every appended line is persisted (batched writes keep it
/// cheap). The last `capacity` lines are kept.
public final class ChumpyLog: @unchecked Sendable {

    public static let shared = ChumpyLog()

    private let lock = NSLock()
    private var lines: [String] = []
    private var dirtyCount = 0
    private let capacity: Int
    private let flushEvery: Int

    public init(capacity: Int = 400, flushEvery: Int = 8) {
        self.capacity = capacity
        self.flushEvery = flushEvery
        lines = ChumpyConstant.sharedDefaults.stringArray(forKey: Self.storageKey) ?? []
    }

    private static let storageKey = "chumpy.tunnel.logBuffer"

    /// Appends a line (timestamped) and periodically mirrors to shared defaults.
    public func append(_ line: String) {
        let trimmed = line.count > 2000 ? String(line.prefix(2000)) : line
        let stamp = Self.timeFormatter.string(from: Date())
        lock.lock()
        lines.append("\(stamp) \(trimmed)")
        if lines.count > capacity {
            lines.removeFirst(lines.count - capacity)
        }
        dirtyCount += 1
        let shouldFlush = dirtyCount >= flushEvery
        let snapshot = shouldFlush ? lines : nil
        if shouldFlush { dirtyCount = 0 }
        lock.unlock()

        if let snapshot {
            ChumpyConstant.sharedDefaults.set(snapshot, forKey: Self.storageKey)
        }
    }

    /// All currently buffered lines (newest last).
    public var all: [String] {
        lock.lock()
        defer { lock.unlock() }
        return lines
    }

    public func clear() {
        lock.lock()
        lines.removeAll()
        lock.unlock()
        ChumpyConstant.sharedDefaults.removeObject(forKey: Self.storageKey)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
