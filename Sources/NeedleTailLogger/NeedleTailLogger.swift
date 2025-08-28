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
import Logging
#endif

public struct NeedleTailLogger: Sendable {
    
    private var subsystem: String = ""
    private var category: String = ""
    private let maxLines: Int
    private let maxLineLength: Int
    
#if !os(Android)
    private let logToFile = LogToFile()
    private var logger: Logger
    private var writeToFile: Bool
    
    private class LogToFile: @unchecked Sendable {
        private var logFileURL: URL?
        private var mutex = pthread_mutex_t()
        
        init() {
            pthread_mutex_init(&mutex, nil)
        }
        
        deinit {
            pthread_mutex_destroy(&mutex)
        }
        
        func setLogFileURL(_ url: URL) {
            pthread_mutex_lock(&mutex)
            defer {
                pthread_mutex_unlock(&mutex)
            }
            self.logFileURL = url
        }
        
        func getLogFileURL() -> URL? {
            pthread_mutex_lock(&mutex)
            defer {
                pthread_mutex_unlock(&mutex)
            }
            let url = self.logFileURL
            return url
        }
    }
#endif
    
    
    public init(
        _ label: String = "[NeedleTailLogging]",
        subsystem: String = "NeedleTailLogger", //Only Android Opt
        level: Level = .debug,
        maxLines: Int = 1000,
        maxLineLength: Int = 80,
        writeToFile: Bool = false
    ) {
#if os(Android)
        self.init(subsystem: subsystem, category: label, level: level)
#else
        self.init(
            Logger(label: label),
            level: Logger.Level(rawValue: level.rawValue) ?? .debug,
            maxLines: maxLines,
            maxLineLength: maxLineLength,
            writeToFile: writeToFile)
#endif
    }
    
#if os(Android)
    private init(
        subsystem: String,
        category: String,
        level: Level = .debug,
        maxLines: Int = 1000,
        maxLineLength: Int = 80
    ) {
        self.subsystem = subsystem
        self.category = category
        logLevel = level
        self.maxLines = maxLines
        self.maxLineLength = maxLineLength
    }
#endif
    
#if !os(Android)
    public init(
        _ logger: Logger = Logger(label: "[NeedleTailLogging]"),
        level: Logger.Level = .debug,
        maxLines: Int = 1000,
        maxLineLength: Int = 80,
        writeToFile: Bool = false
    ) {
        var logger = logger
        logger.logLevel = level
        self.logger = logger
        self.maxLines = maxLines
        self.maxLineLength = maxLineLength
        self.writeToFile = writeToFile
        
        
        if writeToFile {
            let directory: FileManager.SearchPathDirectory
#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
            directory = .libraryDirectory
#else
            directory = .documentDirectory // Use document directory for Linux
#endif
            
            guard let baseDirectory = FileManager.default.urls(for: directory, in: .userDomainMask).first else {
                fatalError("Unable to access base directory.")
            }
            
            let logsDirectory = baseDirectory.appendingPathComponent("Logs/NeedleTailLogger/\(logger.label)")
            do {
                try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true, attributes: nil)
            } catch {
                logger.error("Error creating logs directory - Error: \(error)")
            }
            
            logToFile.setLogFileURL(logsDirectory.appendingPathComponent("logs.txt"))
            
            guard let logFileURL = logToFile.getLogFileURL() else { return }
            
            func fileCreation(lineCount: Int) {
                if FileManager.default.fileExists(atPath: logFileURL.path), lineCount >= maxLines {
                    self.createNewLogFile()
                } else if !FileManager.default.fileExists(atPath: logFileURL.path) {
                    FileManager.default.createFile(atPath: logFileURL.path, contents: nil, attributes: nil)
                }
            }
            
            do {
                let fileContents = try String(contentsOf: logFileURL, encoding: .utf8)
                let lineCount = fileContents.components(separatedBy: .newlines).count
                fileCreation(lineCount: lineCount)
            } catch {
                fileCreation(lineCount: 0)
            }
        }
    }
#endif
    
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
    
#if os(Android)
    public mutating func setLogLevel(_ level: Level) {
        logLevel = level
        androidLog(priority: ANDROID_LOG_INFO, message: "Log level set to \(level)")
    }
#else
    public mutating func setLogLevel(_ level: Logging.Logger.Level) {
        logger.logLevel = level
        logger.info("Log level set to \(level)")
    }
#endif
    
#if !os(Android)
    public func deleteLogFiles() {
        guard let logFileURL = logToFile.getLogFileURL() else { return }
        let logsDirectory = logFileURL.deletingLastPathComponent()
        
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: logsDirectory, includingPropertiesForKeys: nil)
            for fileURL in fileURLs {
                try FileManager.default.removeItem(at: fileURL)
                logger.info("Deleted log file: \(fileURL.lastPathComponent)")
            }
            logger.info("All log files deleted successfully.")
        } catch {
            logger.error("Failed to delete log files: \(error.localizedDescription)")
        }
    }
#endif
    
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
            case .debug:    return displayIcons ? "🪳 " : ""
            case .info:     return displayIcons ? "ℹ️ " : ""
            case .notice:   return displayIcons ? "📣 " : ""
            case .warning:  return displayIcons ? "⚠️ " : ""
            case .error:    return displayIcons ? "❌ " : ""
            case .critical: return displayIcons ? "🚨 " : ""
            }
        }()

    #if os(Android)
        // Android priority mapping
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

        let androidMessage: String = {
            switch level {
            case .debug:
                #if DEBUG
                return "\n-----------------------------------------\n\(icon)\(formattedMessage)\n-----------------------------------------"
                #else
                return "" // debug suppressed in Release
                #endif
            case .error:
                return "\(icon)\(formattedMessage.uppercased())"
            default:
                return "\(icon)\(formattedMessage)"
            }
        }()

        // Only log if non-empty (ensures debug is suppressed in Release)
        if !androidMessage.isEmpty { androidLog(priority: priority, message: androidMessage) }

    #else
        let meta = Logger.Metadata(metadata ?? [:])
        // Non-Android: use logger methods
        switch level {
        case .trace:
            logger.trace("\(icon)\(formattedMessage)", metadata: meta)
        case .debug:
            #if DEBUG
            logger.debug("\n-----------------------------------------\n\(icon)\(formattedMessage)\n-----------------------------------------", metadata: meta)
            #endif
        case .info:
            logger.info("\(icon)\(formattedMessage)", metadata: meta)
        case .notice:
            logger.notice("\(icon)\(formattedMessage)", metadata: meta)
        case .warning:
            logger.warning("\(icon)\(formattedMessage)", metadata: meta)
        case .error:
            logger.error("\(icon)\(formattedMessage.uppercased())", metadata: meta)
        case .critical:
            logger.critical("\(icon)\(formattedMessage)", metadata: meta)
        }

        if writeToFile {
            logMessage(formattedMessage)
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
    
#if !os(Android)
    private func logMessage(_ message: String) {
        do {
            guard let logFileURL = logToFile.getLogFileURL() else { return }
            let fileContents = try String(contentsOf: logFileURL, encoding: .utf8)
            let lineCount = fileContents.components(separatedBy: .newlines).count
            
            if lineCount >= maxLines {
                createNewLogFile()
            }
            
            let fileHandle = try FileHandle(forWritingTo: logFileURL)
            defer { fileHandle.closeFile() }
            
            fileHandle.seekToEndOfFile()
            if let data = (message + "\n").data(using: .utf8) {
                fileHandle.write(data)
            }
        } catch {
            logger.error("Failed to write to log file: \(error.localizedDescription)")
        }
    }
    
    private func createNewLogFile() {
        guard let logFileURL = logToFile.getLogFileURL() else { return }
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let newLogFileName = "logs_\(timestamp).txt".replacingOccurrences(of: ":", with: "-")
        let newLogFileURL = logFileURL.deletingLastPathComponent().appendingPathComponent(newLogFileName)
        
        if !FileManager.default.fileExists(atPath: newLogFileURL.path) {
            FileManager.default.createFile(atPath: newLogFileURL.path, contents: nil, attributes: nil)
            logger.info("Created new log file: \(newLogFileName)")
        }
        
        do {
            let handle = try FileHandle(forWritingTo: newLogFileURL)
            defer { handle.closeFile() }
            let creationMessage = "New log file created on \(Date())\n"
            if let data = creationMessage.data(using: .utf8) {
                handle.write(data)
            }
        } catch {
            logger.error("Failed to write to new log file: \(error.localizedDescription)")
        }
        logToFile.setLogFileURL(newLogFileURL)
    }
#endif
    
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
#endif

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
