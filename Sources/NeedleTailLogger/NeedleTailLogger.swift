//
//  NeedleTailLogger.swift
//
//
//  Created by Cole M on 4/12/24.
//

import Foundation
import Logging

public actor NeedleTailLogger {
    
    private var logger: Logger
    private var logFileURL: URL
    private let maxLines: Int
    private var writeToFile: Bool
    
    public init(_
                logger: Logger = Logger(label: "[NeedleTailLogging]"),
                level: Logger.Level = .debug,
                maxLines: Int = 1000,
                writeToFile: Bool = false
    ) {
        var logger = logger
        logger.logLevel = level
        self.logger = logger
        self.maxLines = maxLines
        self.writeToFile = writeToFile
        
        // Set the log file URL
        guard let url = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?.appendingPathComponent("logs.txt") else {
            fatalError("Unable to access log file directory.")
        }
        self.logFileURL = url
        
        // Create a new log file if it already exists
        if FileManager.default.fileExists(atPath: logFileURL.path) {
            Task { [weak self] in
                guard let self else { return }
                await self.createNewLogFile()
            }
        } else {
            // Create the log file if it doesn't exist
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil, attributes: nil)
        }
    }
    
    public func setLogLevel(_ level: Logger.Level) {
        logger.logLevel = level
        logger.info("Log level set to \(level)")
    }
    
    public func setWriteToFile(_ shouldWrite: Bool) {
        writeToFile = shouldWrite
    }
    
    public func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata? = nil
    ) async {
        guard level >= logger.logLevel else { return } // Only log if the level is greater than or equal to the current log level
        
        switch level {
        case .trace:
            logger.trace(message, metadata: metadata)
        case .debug:
#if DEBUG
            logger.debug("\n--------------------\n \(message)\n--------------------", metadata: metadata)
#else
            break
#endif
        case .info:
            logger.info(message, metadata: metadata)
        case .notice:
            logger.notice(message, metadata: metadata)
        case .warning:
            logger.warning(message, metadata: metadata)
        case .error:
            logger.error("\(message.description.uppercased())", metadata: metadata)
        case .critical:
            logger.critical(message, metadata: metadata)
        }
        
        if writeToFile {
            await logMessage(message.description)
        }
    }
    
    private func logMessage(_ message: String) async {
        do {
            // Read the current contents of the log file to check the line count
            let fileContents = try String(contentsOf: logFileURL, encoding: .utf8)
            let lineCount = fileContents.components(separatedBy: .newlines).count
            
            // If current file exceeds maxLines, create a new file
            if lineCount >= maxLines {
                createNewLogFile()
            }
            
            // Write the log message to the current log file
            let fileHandle = try FileHandle(forWritingTo: logFileURL)
            defer { fileHandle.closeFile() }
            
            // Move to the end of the file and write the message
            fileHandle.seekToEndOfFile()
            if let data = (message + "\n").data(using: .utf8) {
                fileHandle.write(data)
            }
        } catch {
            logger.error("Failed to write to log file: \(error.localizedDescription)")
        }
    }
    
    private func createNewLogFile() {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let newLogFileName = "logs_\(timestamp).txt".replacingOccurrences(of: ":", with: "-") // Replace colons for filename safety
        let newLogFileURL = logFileURL.deletingLastPathComponent().appendingPathComponent(newLogFileName)
        
        // Create the new log file
        if !FileManager.default.fileExists(atPath: newLogFileURL.path) {
            FileManager.default.createFile(atPath: newLogFileURL.path, contents: nil, attributes: nil)
            logger.info("Created new log file: \(newLogFileName)")
        }
        
        // Optionally, write a message to the new log file indicating that a new log file has been created
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
        
        // Update the logFileURL to point to the new log file
        self.logFileURL = newLogFileURL
    }
}
