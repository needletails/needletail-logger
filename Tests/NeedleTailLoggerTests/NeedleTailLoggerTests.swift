import Testing
@testable import NeedleTailLogger
import Foundation
#if !os(Android)
import Logging
#endif

/// Same pattern as `AndroidLoggingTests` in swift-android-native: one test suite calls the
/// public logging API on every platform; implementation differences stay inside the library.
struct NeedleTailLoggerAPITests {
    @Test
    func loggerExercisesAllLevels() {
        var logger = NeedleTailLogger(
            "api",
            subsystem: "NeedleTailLoggerTests",
            level: Level.trace
        )

        logger.log(level: Level.trace, message: "trace")
        logger.log(level: Level.debug, message: "debug")
        logger.log(level: Level.info, message: "info")
        logger.log(level: Level.notice, message: "notice")
        logger.log(level: Level.warning, message: "warning")
        logger.log(level: Level.error, message: "error")
        logger.log(level: Level.critical, message: "critical")

        logger.setLogLevel(Level.warning)
        logger.log(level: Level.info, message: "filtered")
        logger.log(level: Level.error, message: "kept")

        #expect(logger.logLevel == Level.warning)
    }
}

/// File logging is the same on every platform, Android included: nothing here sits behind a
/// platform check, and nothing here needs swift-log.
struct NeedleTailLoggerFileTests {
    private func temporaryLogFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("NeedleTailLoggerTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("logs.txt")
    }

    private func lines(of file: URL) throws -> [String] {
        try String(contentsOf: file, encoding: .utf8).split(separator: "\n").map { String($0) }
    }

    @Test
    func writesEveryLoggedLineToItsFile() throws {
        let logFile = temporaryLogFile()
        defer { try? FileManager.default.removeItem(at: logFile.deletingLastPathComponent()) }

        let logger = NeedleTailLogger("[FileTest]", maxLineLength: 512, logFileURL: logFile)
        #expect(logger.activeLogFileURL == logFile)
        logger.log(level: .info, message: "first line with sharedId=ABC", displayIcons: false)
        logger.log(level: .warning, message: "second line", displayIcons: false)

        let written = try lines(of: logFile)
        #expect(written.count == 3)
        #expect(written.allSatisfy { $0.hasPrefix("[20") })
        #expect(written[0].hasSuffix("] NeedleTailLogger.fileLog=\(logFile.path)"))
        #expect(written[1].hasSuffix("] first line with sharedId=ABC"))
        #expect(written[2].hasSuffix("] second line"))
    }

    @Test
    func aLoggerNotAskedForAFileHasNone() {
        #expect(NeedleTailLogger("[NoFile]").activeLogFileURL == nil)
    }

    @Test
    func setsAFullFileAsideAndStartsItAgain() throws {
        let logFile = temporaryLogFile()
        let folder = logFile.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: folder) }

        let logger = NeedleTailLogger("[Rotate]", level: .info, maxLines: 3, maxLineLength: 512, logFileURL: logFile)
        for index in 0..<5 {
            logger.log(level: .info, message: "line \(index)", displayIcons: false)
        }

        // The file asked for always holds the newest lines; the full one was set aside whole.
        #expect(logger.activeLogFileURL == logFile)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        #expect(names.count == 2)
        let closedName = try #require(names.first { $0 != "logs.txt" })
        #expect(closedName.hasPrefix("logs_") && closedName.hasSuffix(".txt"))
        let closed = try lines(of: folder.appendingPathComponent(closedName))
        #expect(closed.count == 3)
        for index in 0..<3 {
            #expect(closed[index].hasSuffix("] line \(index)"))
        }
        let current = try lines(of: logFile)
        #expect(current.count == 2)
        #expect(current.first?.hasSuffix("] line 3") == true)
        #expect(current.last?.hasSuffix("] line 4") == true)
    }

    /// A logger opened on a file that is already full must not add to it. The check at
    /// start-up used to do nothing, so each new process added up to `maxLines` more lines to
    /// the same file: one phone's `logs.txt` reached 29,521 lines against a limit of 5,000.
    @Test
    func aFullFileIsSetAsideByTheNextProcess() throws {
        let logFile = temporaryLogFile()
        let folder = logFile.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: folder) }

        // One process fills the file to its limit and ends.
        let first = NeedleTailLogger("[Full]", level: .info, maxLines: 3, maxLineLength: 512, logFileURL: logFile)
        for index in 0..<3 {
            first.log(level: .info, message: "first \(index)", displayIcons: false)
        }
        #expect(try lines(of: logFile).count == 3)

        // The next process opens the same file.
        let second = NeedleTailLogger("[Full]", level: .info, maxLines: 3, maxLineLength: 512, logFileURL: logFile)
        second.log(level: .info, message: "second 0", displayIcons: false)

        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        #expect(names.count == 2)
        let current = try lines(of: logFile)
        #expect(current.count == 1)
        #expect(current.first?.hasSuffix("] second 0") == true)
        let closedName = try #require(names.first { $0 != "logs.txt" })
        let closed = try lines(of: folder.appendingPathComponent(closedName))
        #expect(closed.count == 3)
        #expect(closed.last?.hasSuffix("] first 2") == true)
    }

    /// Two loggers can share a folder (the notification extension's two logs do), so a file
    /// set aside carries the name of the file it came from.
    @Test
    func aFileSetAsideKeepsItsOwnName() throws {
        let logFile = temporaryLogFile().deletingLastPathComponent().appendingPathComponent("connection.txt")
        let folder = logFile.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: folder) }

        let logger = NeedleTailLogger("[Named]", level: .info, maxLines: 1, maxLineLength: 512, logFileURL: logFile)
        logger.log(level: .info, message: "one", displayIcons: false)
        logger.log(level: .info, message: "two", displayIcons: false)

        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        #expect(names.count == 2)
        #expect(names.contains("connection.txt"))
        #expect(names.contains { $0.hasPrefix("connection_") && $0.hasSuffix(".txt") })
    }

    /// Two rotations in the same second ask for the same set-aside name. The second must not
    /// replace the first: its line goes into the file as it is, and a later line tries again.
    @Test
    func rotationsInTheSameSecondKeepEveryLine() throws {
        let logFile = temporaryLogFile()
        let folder = logFile.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: folder) }

        let logger = NeedleTailLogger("[Burst]", level: .info, maxLines: 1, maxLineLength: 512, logFileURL: logFile)
        for index in 0..<4 {
            logger.log(level: .info, message: "line \(index)", displayIcons: false)
        }

        let kept = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .flatMap { try lines(of: folder.appendingPathComponent($0)) }
        #expect(kept.count == 4)
        for index in 0..<4 {
            #expect(kept.filter { $0.hasSuffix("] line \(index)") }.count == 1)
        }
    }

    @Test
    func theDefaultFolderIsNamedForTheLabel() throws {
        let folder = try #require(NeedleTailLogger.defaultLogDirectory(label: "[Connection]"))
        #expect(folder.path.hasSuffix("/Logs/NeedleTailLogger/[Connection]"))
#if os(macOS) || os(iOS)
        #expect(folder.path.contains("/Library/Logs/"))
#endif
    }
}

// Exit tests need Swift 6.2, and Swift Testing has none on Android. The lines under test are
// the same code on every platform.
#if compiler(>=6.2) && (os(macOS) || os(Linux))
struct NeedleTailLoggerRefusedWriteTests {
    /// A write the system refuses (a full disk) drops the line; it must not end the process.
    /// Runs in a child process: the size limit that makes every write fail is process-wide.
    @Test
    func aRefusedWriteDropsTheLine() async {
        await #expect(processExitsWith: .success) {
            let logFile = FileManager.default.temporaryDirectory
                .appendingPathComponent("NeedleTailLoggerTests-\(UUID().uuidString)", isDirectory: true)
                .appendingPathComponent("logs.txt")
            defer { try? FileManager.default.removeItem(at: logFile.deletingLastPathComponent()) }
            let logger = NeedleTailLogger("[Refused]", logFileURL: logFile)

            // From here no file in this process may grow, so the next append is refused.
            signal(SIGXFSZ, SIG_IGN)
            var none = rlimit(rlim_cur: 0, rlim_max: 0)
            setrlimit(RLIMIT_FSIZE, &none)
            logger.log(level: .info, message: "dropped")
        }
    }
}
#endif

actor LoggerTests {

    var logMessages: [Message] = []


    @Test
    func testLogLevels() async {
        let logger = NeedleTailLogger()
        let logCount = 3000

        var allMessages: [[Message]] = Array(repeating: [], count: logCount)

        await withTaskGroup(of: (Int, [Message]).self) { group in
            for i in 0..<logCount {
                group.addTask {
                    let message = "LOG MESSAGE \(i)"
                    var messages: [Message] = []

                    logger.log(level: .trace, message: "\(message)")
                    messages.append("\(message)")

                    logger.log(level: .debug, message: "\(message)")
                    messages.append("\(message)")

                    logger.log(level: .info, message: "\(message)")
                    messages.append("\(message)")

                    logger.log(level: .notice, message: "\(message)")
                    messages.append("\(message)")

                    logger.log(level: .warning, message:"\(message)")
                    messages.append("\(message)")

                    logger.log(level: .error, message: "\(message)")
                    messages.append("\(message)")

                    logger.log(level: .critical, message: "\(message)")
                    messages.append("\(message)")

                    logger.log(level: .error, message: "Failed to encode DirectMessage", metadata: [
                        "messageType": "Test",
                        "error": "Error"
                    ])

                    return (i, messages)
                }
            }

            for await (i, messages) in group {
                allMessages[i] = messages
            }
        }

        // Flatten all collected messages
        self.logMessages = allMessages.flatMap { $0 }

        for i in 0..<logCount {
            #expect(logMessages[i * 7 + 0] == "LOG MESSAGE \(i)")
            #expect(logMessages[i * 7 + 1] == "LOG MESSAGE \(i)")
            #expect(logMessages[i * 7 + 2] == "LOG MESSAGE \(i)")
            #expect(logMessages[i * 7 + 3] == "LOG MESSAGE \(i)")
            #expect(logMessages[i * 7 + 4] == "LOG MESSAGE \(i)")
            #expect(logMessages[i * 7 + 5] == "LOG MESSAGE \(i)")
            #expect(logMessages[i * 7 + 6] == "LOG MESSAGE \(i)")
        }

        #expect(logMessages.count / 7 == logCount)
    }

    #if !os(Android)
    @Test
    func testSetLogLevelFiltersOutput() async {
        final class LogStore: @unchecked Sendable {
            private let lock = NSLock()
            private var _messages: [String] = []

            func append(_ message: String) {
                lock.lock()
                _messages.append(message)
                lock.unlock()
            }

            func all() -> [String] {
                lock.lock()
                let out = _messages
                lock.unlock()
                return out
            }
        }

        struct CapturingLogHandler: LogHandler {
            var metadata: Logger.Metadata = [:]
            var logLevel: Logger.Level = .trace

            private let store: LogStore

            init(store: LogStore) {
                self.store = store
            }

            subscript(metadataKey key: String) -> Logger.MetadataValue? {
                get { metadata[key] }
                set { metadata[key] = newValue }
            }

            func log(
                level: Logger.Level,
                message: Logger.Message,
                metadata: Logger.Metadata?,
                source: String,
                file: String,
                function: String,
                line: UInt
            ) {
                store.append(message.description)
            }
        }

        let store = LogStore()
        let baseLogger = Logger(label: "NeedleTailLoggerTests") { _ in
            CapturingLogHandler(store: store)
        }

        var logger = NeedleTailLogger(baseLogger, level: .trace)

        logger.setLogLevel(.error)
        logger.log(level: .info, message: "should-not-log")
        logger.log(level: .error, message: "should-log")

        let captured = store.all().joined(separator: "\n").uppercased()
        #expect(!captured.contains("SHOULD-NOT-LOG"))
        #expect(captured.contains("SHOULD-LOG"))
    }

    @Test
    func testCustomLogFileURLWritesMessages() throws {
        let logFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeedleTailLoggerTests-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: logFile) }

        let logger = NeedleTailLogger("[CustomLogFile]", logFileURL: logFile)

        #expect(logger.activeLogFileURL == logFile)
        logger.log(level: .info, message: "persisted-to-custom-file")

        let contents = try String(contentsOf: logFile, encoding: .utf8)
        #expect(contents.contains("NeedleTailLogger.fileLog=\(logFile.path)"))
        #expect(contents.contains("persisted-to-custom-file"))
    }

    @Test
    func testCustomLogFileURLAnnouncesPathAtDebug() throws {
        final class LogStore: @unchecked Sendable {
            private let lock = NSLock()
            private var _messages: [String] = []

            func append(_ message: String) {
                lock.lock()
                _messages.append(message)
                lock.unlock()
            }

            func all() -> [String] {
                lock.lock()
                let out = _messages
                lock.unlock()
                return out
            }
        }

        struct CapturingLogHandler: LogHandler {
            var metadata: Logger.Metadata = [:]
            var logLevel: Logger.Level = .trace

            private let store: LogStore

            init(store: LogStore) {
                self.store = store
            }

            subscript(metadataKey key: String) -> Logger.MetadataValue? {
                get { metadata[key] }
                set { metadata[key] = newValue }
            }

            func log(
                level: Logger.Level,
                message: Logger.Message,
                metadata: Logger.Metadata?,
                source: String,
                file: String,
                function: String,
                line: UInt
            ) {
                store.append(message.description)
            }
        }

        let logFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeedleTailLoggerTests-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: logFile) }

        let store = LogStore()
        let baseLogger = Logger(label: "NeedleTailLoggerTests.customFile") { _ in
            CapturingLogHandler(store: store)
        }

        let logger = NeedleTailLogger(baseLogger, level: .debug, logFileURL: logFile)
        let captured = store.all().joined(separator: "\n")

        #expect(captured.contains("NeedleTailLogger.fileLog=\(logFile.path)"))
    }
    #endif
}
