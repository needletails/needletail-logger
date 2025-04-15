//
//  NeedleTailLogger.swift
//
//
//  Created by Cole M on 4/12/24.
//
import Foundation
import Logging

public struct NeedleTailLogger: Sendable {
    
    private var logger: Logger

    private let maxLines: Int
    private let maxLineLength: Int
    private var writeToFile: Bool
    
    private let logToFile = LogToFile()
    
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
    
    public mutating func setLogLevel(_ level: Logger.Level) {
        logger.logLevel = level
        logger.info("Log level set to \(level)")
    }
    
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
    
    public func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata? = nil,
        displayIcons: Bool = true
    ) {
        guard level >= logger.logLevel else { return }
        
        let formattedMessage = formatLogMessage(level: level, message: message)
        
        switch level {
        case .trace:
            logger.trace("\(displayIcons ? "🫆 " : "")\(formattedMessage)", metadata: metadata)
        case .debug:
#if DEBUG
            logger.debug("\n-----------------------------------------\n\(displayIcons ? "🪳 " : "")\(formattedMessage)\n-----------------------------------------", metadata: metadata)
#else
            break
#endif
        case .info:
            logger.info("\(displayIcons ? "ℹ️ " : "")\(formattedMessage)", metadata: metadata)
        case .notice:
            logger.notice("\(displayIcons ? "📣 " : "")\(formattedMessage)", metadata: metadata)
        case .warning:
            logger.warning("\(displayIcons ? "⚠️ " : "")\(formattedMessage)", metadata: metadata)
        case .error:
            logger.error("\(displayIcons ? "❌ " : "")\(formattedMessage.uppercased())", metadata: metadata)
        case .critical:
            logger.critical("\(displayIcons ? "🚨 " : "")\(formattedMessage)", metadata: metadata)
        }
        
        if writeToFile {
            logMessage(formattedMessage)
        }
    }
    
    private func formatLogMessage(level: Logger.Level, message: Logger.Message) -> String {
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
}
