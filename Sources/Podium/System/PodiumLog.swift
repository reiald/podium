import Foundation
import os

private let logger = Logger(subsystem: "dev.podium.Podium", category: "general")

/// A printf-style message to the unified log (`log show --predicate 'subsystem ==
/// "dev.podium.Podium"'`), public so it is readable there. NSLog's output never reaches it.
func podiumLog(_ format: String, _ args: CVarArg...) {
    let message = String(format: format, arguments: args)
    logger.log("\(message, privacy: .public)")
}
