import Testing
@testable import NeedleTailLogger

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
}
