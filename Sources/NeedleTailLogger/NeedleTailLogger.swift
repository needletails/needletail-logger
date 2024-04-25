//
//  NeedleTailLogger.swift
//
//
//  Created by Cole M on 4/12/24.
//

import Foundation
import Logging

public struct NeedleTailLogger {
    
    private let logger: Logger
    private let redColor = "\u{001B}[0;31m"  // Red color
    private let resetColor = "\u{001B}[0m" // Reset color to default
    
    public init(_ logger: Logger = Logger(label: "[ NeedleTailLogging ]"), level: Logger.Level = .debug) {
        var logger = logger
        logger.logLevel = level
        self.logger = logger
    }
    
    public func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata? = nil
    ) {
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
        
        
        guard var url = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            return
        }
        
        url.appendPathComponent("logs.txt")
        
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(
                atPath: url.path,
                contents: nil,
                attributes: nil
            )
        }
        
        do {
            let handle = try FileHandle(forWritingTo: url)
            defer { handle.closeFile() }
            handle.seekToEndOfFile()
            handle.write(message.description.data(using: .utf8)!)
        } catch {
            NeedleTailLogger(.init(label: "[ File-Logger ]")).log(level: .error, message: "\(error)")
        }
    }
}
