//
//  NeedleTailLogger.swift
//
//
//  Created by Cole M on 4/12/24.
//
import Foundation
#if os(Android)
import Android
import AndroidNDK
import AndroidLogging
#else
@_exported import Logging
#endif

public struct NeedleTailLogger: Sendable {
    
    private var subsystem: String = ""
    private var category: String = ""
    private let maxLines: Int
    private let maxLineLength: Int
    
    private let logToFile = LogToFile()
    private var writeToFile = false
#if !os(Android)
    private var logger: Logger
#endif

    private class LogToFile: @unchecked Sendable {
        private var logFileURL: URL?
        private var lineCount = 0
        private var mutex = pthread_mutex_t()
        
        init() {
            pthread_mutex_init(&mutex, nil)
        }
        
        deinit {
            pthread_mutex_destroy(&mutex)
        }
        
        func setLogFileURL(_ url: URL, initialLineCount: Int = 0) {
            pthread_mutex_lock(&mutex)
            defer {
                pthread_mutex_unlock(&mutex)
            }
            self.logFileURL = url
            self.lineCount = initialLineCount
        }
        
        func getLogFileURL() -> URL? {
            pthread_mutex_lock(&mutex)
            defer {
                pthread_mutex_unlock(&mutex)
            }
            let url = self.logFileURL
            return url
        }

        func appendLine(_ line: String, maxLines: Int) {
            pthread_mutex_lock(&mutex)
            defer {
                pthread_mutex_unlock(&mutex)
            }

            guard let logFileURL else { return }

            if lineCount >= maxLines {
                // Full: set it aside under its own name and the time, and start it again.
                // The file asked for always holds the newest lines. If the move fails the
                // line still goes into the full file, and the next line tries again.
                let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
                let name = logFileURL.deletingPathExtension().lastPathComponent
                let type = logFileURL.pathExtension.isEmpty ? "" : "." + logFileURL.pathExtension
                let setAside = logFileURL.deletingLastPathComponent().appendingPathComponent("\(name)_\(stamp)\(type)")
                if (try? FileManager.default.moveItem(at: logFileURL, to: setAside)) != nil {
                    lineCount = 0
                }
            }

            do {
                if !FileManager.default.fileExists(atPath: logFileURL.path) {
                    FileManager.default.createFile(atPath: logFileURL.path, contents: nil, attributes: nil)
                    lineCount = 0
                }

                let fileHandle = try FileHandle(forWritingTo: logFileURL)
                defer { try? fileHandle.close() }
                // The throwing calls: the older ones end the process when the system
                // refuses a write, on a full disk for one.
                try fileHandle.seekToEnd()
                try fileHandle.write(contentsOf: Data((line + "\n").utf8))
                lineCount += 1
            } catch {
                // File logging is best-effort; backend logger handles surfacing errors.
            }
        }
    }
    
    
    public init(
        _ label: String = "[NeedleTailLogging]",
        subsystem: String = "NeedleTailLogger", //Only Android Opt
        level: Level = .debug,
        maxLines: Int = 1000,
        maxLineLength: Int = 80,
        writeToFile: Bool = false,
        logFileURL: URL? = nil
    ) {
#if os(Android)
        self.subsystem = subsystem
        self.category = label
        self.logLevel = level
        self.maxLines = maxLines
        self.maxLineLength = maxLineLength
        startFileLogging(label: label, writeToFile: writeToFile, logFileURL: logFileURL)
#else
        self.init(
            Logger(label: label),
            level: Logger.Level(rawValue: level.rawValue) ?? .debug,
            maxLines: maxLines,
            maxLineLength: maxLineLength,
            writeToFile: writeToFile,
            logFileURL: logFileURL)
#endif
    }
    
    /// Resolved on-disk log file when file logging is enabled; `nil` otherwise.
    public var activeLogFileURL: URL? {
        logToFile.getLogFileURL()
    }

#if !os(Android)
    public init(
        _ logger: Logger = Logger(label: "[NeedleTailLogging]"),
        level: Logger.Level = .debug,
        maxLines: Int = 1000,
        maxLineLength: Int = 80,
        writeToFile: Bool = false,
        logFileURL: URL? = nil
    ) {
        var logger = logger
        logger.logLevel = level
        self.logger = logger
        self.maxLines = maxLines
        self.maxLineLength = maxLineLength
        self.logLevel = Level(rawValue: level.rawValue) ?? .debug
        startFileLogging(label: logger.label, writeToFile: writeToFile, logFileURL: logFileURL)
    }
#endif

    /// The folder a logger with this label keeps `logs.txt` in when it is given no file of
    /// its own.
    public static func defaultLogDirectory(label: String) -> URL? {
        let directory: FileManager.SearchPathDirectory
#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
        directory = .libraryDirectory
#elseif os(Android)
        // The app's private files folder: Android has no Library folder.
        directory = .applicationSupportDirectory
#else
        directory = .documentDirectory // Use document directory for Linux
#endif
        return FileManager.default.urls(for: directory, in: .userDomainMask).first?
            .appendingPathComponent("Logs/NeedleTailLogger/\(label)")
    }

    /// Opens the log file when one was asked for. File logging is best effort: when its
    /// folder cannot be found the logger keeps writing to its backend only.
    private mutating func startFileLogging(label: String, writeToFile: Bool, logFileURL: URL?) {
        guard writeToFile || logFileURL != nil else { return }
        guard let fileURL = logFileURL
                ?? Self.defaultLogDirectory(label: label)?.appendingPathComponent("logs.txt") else {
            backend(.error, "Unable to access base directory; file logging disabled")
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil)
        } catch {
            backend(.error, "Error creating logs directory - Error: \(error)")
        }

        self.writeToFile = true
        let initialLineCount = prepareLogFileIfNeeded(at: fileURL)
        logToFile.setLogFileURL(fileURL, initialLineCount: initialLineCount)

        log(
            level: .debug,
            message: "NeedleTailLogger.fileLog=\(fileURL.path)",
            displayIcons: false)
    }
    
    var logLevel: Level = .debug {
        didSet {
#if !os(Android)
            switch logLevel {
            case .debug:
                logger.logLevel = .debug
            case .info:
                logger.logLevel = .info
            case .warning:
                logger.logLevel = .warning
            case .error:
                logger.logLevel = .error
            case .trace:
                logger.logLevel = .trace
            case .notice:
                logger.logLevel = .notice
            case .critical:
                logger.logLevel = .critical
            }
#endif
        }
    }

    public mutating func setLogLevel(_ level: Level) {
        // Keep internal filtering (`logLevel`) and backend filtering (`logger.logLevel`) in sync.
        logLevel = level
        backend(.info, "Log level set to \(level)")
    }

    
    public func deleteLogFiles() {
        guard let logFileURL = logToFile.getLogFileURL() else { return }
        let logsDirectory = logFileURL.deletingLastPathComponent()
        
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: logsDirectory, includingPropertiesForKeys: nil)
            for fileURL in fileURLs {
                try FileManager.default.removeItem(at: fileURL)
                backend(.info, "Deleted log file: \(fileURL.lastPathComponent)")
            }
            backend(.info, "All log files deleted successfully.")
        } catch {
            backend(.error, "Failed to delete log files: \(error.localizedDescription)")
        }
    }
    
    public func log(
        level: Level,
        message: Message,
        metadata: Metadata? = nil,
        displayIcons: Bool = true
    ) {
        guard level >= logLevel else { return }

        let formattedMessage = formatLogMessage(level: level, message: message)
        let icon: String = {
            switch level {
            case .trace:    return displayIcons ? "🫆 " : ""
            case .debug:    return displayIcons ? "🐛 " : ""
            case .info:     return displayIcons ? "ℹ️ " : ""
            case .notice:   return displayIcons ? "📣 " : ""
            case .warning:  return displayIcons ? "⚠️ " : ""
            case .error:    return displayIcons ? "❌ " : ""
            case .critical: return displayIcons ? "🚨 " : ""
            }
        }()
        let line = "\(icon)\(formattedMessage)"

        backend(level, line, metadata: metadata)
        if writeToFile {
            logMessage(formattedMessage)
        }
    }

    /// The platform's own log: swift-log, or the Android system log.
    private func backend(_ level: Level, _ line: String, metadata: Metadata? = nil) {
#if os(Android)
        let priority: android_LogPriority = {
            switch level {
            case .trace:    return ANDROID_LOG_VERBOSE
            case .debug:    return ANDROID_LOG_DEBUG
            case .info:     return ANDROID_LOG_INFO
            case .notice:   return ANDROID_LOG_INFO
            case .warning:  return ANDROID_LOG_WARN
            case .error:    return ANDROID_LOG_ERROR
            case .critical: return ANDROID_LOG_ERROR
            }
        }()
        androidLog(priority: priority, message: line)
#else
        let meta = Logger.Metadata(metadata ?? [:])
        // Already filtered by `logLevel`. Same line shape for every level:
        // no banners and no case-mangling (preserves identifiers / error text).
        switch level {
        case .trace:
            logger.trace("\(line)", metadata: meta)
        case .debug:
            logger.debug("\(line)", metadata: meta)
        case .info:
            logger.info("\(line)", metadata: meta)
        case .notice:
            logger.notice("\(line)", metadata: meta)
        case .warning:
            logger.warning("\(line)", metadata: meta)
        case .error:
            logger.error("\(line)", metadata: meta)
        case .critical:
            logger.critical("\(line)", metadata: meta)
        }
#endif
    }

    
    private func formatLogMessage(level: Level, message: Message) -> String {
        // Create the base log message
        let formattedMessage = "\(message)"
        
        // Handle pagination by breaking long messages into multiple lines
        return paginateMessage(formattedMessage)
    }
    
    private func paginateMessage(_ message: String) -> String {
        var paginatedMessage = ""
        var currentLine = ""
        
        // Split the message into words
        let words = message.split(separator: " ")
        
        for word in words {
            // Check if adding the next word exceeds the max line length
            if currentLine.count + word.count + 1 > maxLineLength {
                // If it does, add the current line to the paginated message and start a new line
                paginatedMessage += currentLine + "\n"
                currentLine = ""
            }
            // Add the word to the current line
            if currentLine.isEmpty {
                currentLine += String(word)
            } else {
                currentLine += " " + String(word)
            }
        }
        
        // Add any remaining text in the current line
        if !currentLine.isEmpty {
            paginatedMessage += currentLine
        }
        
        return paginatedMessage
    }
    
    @discardableResult
    private func prepareLogFileIfNeeded(at logFileURL: URL) -> Int {
        if FileManager.default.fileExists(atPath: logFileURL.path) {
            if let attributes = try? FileManager.default.attributesOfItem(atPath: logFileURL.path),
               let size = attributes[.size] as? NSNumber,
               size.intValue == 0 {
                return 0
            }

            if let fileContents = try? String(contentsOf: logFileURL, encoding: .utf8) {
                return fileContents.components(separatedBy: .newlines).filter { !$0.isEmpty }.count
            }
            return 0
        }

        FileManager.default.createFile(atPath: logFileURL.path, contents: nil, attributes: nil)
        return 0
    }

    private func logMessage(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)"
        logToFile.appendLine(line, maxLines: maxLines)
    }
    
#if os(Android)
    
    private var logTag: String {
        subsystem.isEmpty && category.isEmpty ? "" : (subsystem + "/" + category)
    }
    
    private func androidLog(priority: android_LogPriority, message: AndroidLogging.OSLogMessage) {
        //swift_android_log(priority, logTag, messagePtr)
        __android_log_write(Int32(priority.rawValue), logTag, message)
    }
#endif
}

public enum Level: String, Sendable, Equatable {
    /// Appropriate for messages that contain information normally of use only when
    /// tracing the execution of a program.
    case trace
    
    /// Appropriate for messages that contain information normally of use only when
    /// debugging a program.
    case debug
    
    /// Appropriate for informational messages.
    case info
    
    /// Appropriate for conditions that are not error conditions, but that may require
    /// special handling.
    case notice
    
    /// Appropriate for messages that are not error conditions, but more severe than
    /// `.notice`.
    case warning
    
    /// Appropriate for error conditions.
    case error
    
    /// Appropriate for critical error conditions that usually require immediate
    /// attention.
    ///
    /// When a `critical` message is logged, the logging backend (`LogHandler`) is free to perform
    /// more heavy-weight operations to capture system state (such as capturing stack traces) to facilitate
    /// debugging.
    case critical
}

extension Level {
    internal var naturalIntegralValue: Int {
        switch self {
        case .trace:
            return 0
        case .debug:
            return 1
        case .info:
            return 2
        case .notice:
            return 3
        case .warning:
            return 4
        case .error:
            return 5
        case .critical:
            return 6
        }
    }
}

extension Level: Comparable {
    public static func < (lhs: Level, rhs: Level) -> Bool {
        return lhs.naturalIntegralValue < rhs.naturalIntegralValue
    }
}

public typealias Metadata = [String: MetadataValue]

public enum MetadataValue {
    case string(String)
    case stringConvertible(any CustomStringConvertible & Sendable)
    case dictionary(Metadata)
    case array([Metadata.Value])
}

#if !os(Android)
extension Logger.MetadataValue {
    init(_ v: MetadataValue) {
        switch v {
        case .string(let s):
            self = .string(s)
        case .stringConvertible(let sc):
            self = .stringConvertible(sc)
        case .dictionary(let dict):
            var out: Logger.Metadata = [:]
            for (k, vv) in dict {
                out[k] = Logger.MetadataValue(vv)
            }
            self = .dictionary(out)
        case .array(let arr):
            self = .array(arr.map { Logger.MetadataValue($0) })
        }
    }
}

extension Logger.Metadata {
    init(_ m: Metadata) {
        var out: Logger.Metadata = [:]
        for (k, v) in m {
            out[k] = Logger.MetadataValue(v)
        }
        self = out
    }
}
#endif

extension MetadataValue: ExpressibleByStringLiteral {
    public typealias StringLiteralType = String

    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

extension MetadataValue: CustomStringConvertible {
    public var description: String {
        switch self {
        case .dictionary(let dict):
            return dict.mapValues { $0.description }.description
        case .array(let list):
            return list.map { $0.description }.description
        case .string(let str):
            return str
        case .stringConvertible(let repr):
            return repr.description
        }
    }
}

extension MetadataValue: ExpressibleByStringInterpolation {}
extension MetadataValue: ExpressibleByDictionaryLiteral {
    public typealias Key = String
    public typealias Value = Metadata.Value

    public init(dictionaryLiteral elements: (String, Metadata.Value)...) {
        self = .dictionary(.init(uniqueKeysWithValues: elements))
    }
}

public struct Message: ExpressibleByStringLiteral, Equatable, CustomStringConvertible, ExpressibleByStringInterpolation, Sendable {
    public typealias StringLiteralType = String
    
    private var value: String
    
    public init(stringLiteral value: String) {
        self.value = value
    }
    
    public var description: String {
        return self.value
    }
}
