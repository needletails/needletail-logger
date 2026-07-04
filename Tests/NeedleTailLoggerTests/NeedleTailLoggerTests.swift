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
                    messages.append("\(message.uppercased())")

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
