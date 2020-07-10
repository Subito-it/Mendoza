//
//  ExecuterLogger.swift
//  Mendoza
//
//  Created by Tomas Camin on 05/02/2019.
//

import Foundation

class ExecuterLogger: Logger, CustomDebugStringConvertible {
    private enum LoggerEvent: CustomDebugStringConvertible {
        case start(command: String)
        case end(output: String, statusCode: Int32)
        case exception(error: String)

        var isStart: Bool {
            switch self {
            case .start:
                return true
            default:
                return false
            }
        }

        var isEnd: Bool {
            switch self {
            case .end:
                return true
            default:
                return false
            }
        }

        var isError: Bool {
            switch self {
            case .start:
                return false
            case let .end(_, statusCode):
                return statusCode != 0
            case .exception:
                return true
            }
        }

        var debugDescription: String {
            switch self {
            case let .start(command):
                return "[START] \(command)"
            case let .end(output, statusCode):
                return "[END] \(output) (-> \(statusCode))"
            case let .exception(error):
                return "[EXC] \(error)"
            }
        }
    }

    let name: String
    let address: String

    var description: String { "\(address) - \(name)" }
    var debugDescription: String { "\(name), \(address), logs: \(logs.count)" }
    var hasErrors: Bool { logs.first(where: { $0.isError }) != nil }
    var filename: String { "\(address)-\(name).html" }
    var isEmpty: Bool { logs.isEmpty }
    var dumpToStandardOutput: Bool = false

    private var logs = [LoggerEvent]()
    private var blackList = [String]()

    init(name: String, address: String) {
        self.name = name
        self.address = address
    }

    func log(command: String) {
        logs.append(.start(command: redact(command)))
        if dumpToStandardOutput { print(redact(command)) }
    }

    func log(output: String, statusCode: Int32) {
        logs.append(.end(output: redact(output), statusCode: statusCode))
    }

    func log(exception: String) {
        logs.append(.exception(error: redact(exception)))
    }

    func addBlackList(_ word: String) {
        blackList.append(word)
    }

    func dump() throws {
        let url = Path.logs.url.appendingPathComponent(filename)
        try write(to: url)
    }

    func redact(_ input: String) -> String {
        var result = input
        for redact in blackList {
            result = result.replacingOccurrences(of: redact, with: "~redacted~")
        }

        return result
    }

    private func write(to: URL) throws {
        guard !logs.isEmpty else { return }

        var pairs = [(start: LoggerEvent, end: LoggerEvent)]()

        var lastLog: LoggerEvent = .end(output: "", statusCode: 0)
        for log in logs {
            defer { lastLog = log }

            switch log {
            case .start:
                guard !lastLog.isStart else { print(logs); assertionFailure("💣 Unexpected order of events, not expecting start event"); return }
            case .end:
                guard lastLog.isStart else { print(logs); assertionFailure("💣 Unexpected order of events, expecting start event"); return }
                pairs.append((start: lastLog, end: log))
            case .exception:
                pairs.append((start: .start(command: "EXCEPTION"), end: log))
            }
        }

        var templateBody = [String]()
        for (index, pair) in pairs.enumerated() {
            var detailCommand: String
            switch pair.start {
            case let .start(command):
                detailCommand = command
            default:
                fatalError()
            }

            let detailStatusCode: Int32
            let detailOutput: String
            let detailError: Bool
            switch pair.end {
            case let .end(output, statusCode):
                detailOutput = output
                detailError = statusCode != 0
                detailStatusCode = statusCode
            case let .exception(error):
                detailOutput = error
                detailError = true
                detailStatusCode = 0
            default:
                fatalError()
            }

            var detailStatusMessage = "<p>\(detailOutput)</p>"
            detailStatusMessage = detailStatusMessage.replacingOccurrences(of: " ", with: "&nbsp;")
            detailStatusMessage = detailStatusMessage.replacingOccurrences(of: "\n", with: "<br />\n")
            detailStatusMessage += detailStatusCode == 0 ? "" : "<p>exit code: \(String(detailStatusCode))</p>"

            var detailsClasses = [String]()
            if index % 2 == 0 {
                detailsClasses.append("even")
            } else {
                detailsClasses.append("odd")
            }
            if detailError {
                detailCommand = "<b>\(detailCommand)</b>"
                detailsClasses.append("error")
            }

            templateBody.append("""
                <details class="\(detailsClasses.joined(separator: " "))">
                    <summary>\(detailCommand)</summary>
                    \(detailStatusMessage)
                </details>
            """)
        }

        let templateTitle = "<h3>\(name) [\(address)]</h3>"

        let logContent = ExecuterLogger.html(title: templateTitle, body: templateBody.joined(separator: "\n"))
        try logContent.data(using: .utf8)?.write(to: to)
    }
}

extension ExecuterLogger: Equatable, Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(address)
        hasher.combine(name)
    }

    static func == (lhs: ExecuterLogger, rhs: ExecuterLogger) -> Bool {
        lhs.address == rhs.address && lhs.name == rhs.name
    }
}

extension ExecuterLogger {
    static func html(title: String, body: String) -> String {
        let titleMarker = "{{ title }}"
        let bodyMarker = "{{ body }}"
        return
            """
            <html>
            <meta charset="UTF-8">
            <head>
                <style>
                    body {
                        font-family: -apple-system, BlinkMacSystemFont, Menlo;
                        font-weight: normal;
                    }
                    details {
                        font-family: Menlo, Courier;
                        color: rgb(30, 30, 30);
                        font-size: 80%;
                        margin-left: -5px;
                        padding-left: 5px;
                        padding-top: 5px;
                        padding-bottom: 5px;
                    }
                    details.even {
                        background-color: rgb(244,245,244);
                    }
                    details.error {
                        background-color: rgb(255,186,186);
                        border: 0.5px solid rgb(255,123,123);
                    }
                    details p {
                        margin-left: 20px;
                        font-weight: lighter;
                    }
                    summary::-webkit-details-marker {
                        display: none;
                    }
                </style>
            </head>
            <body>
            <a href="index.html">home</a>
            \(titleMarker)
            \(bodyMarker)
            </body>
            </html>
            """.replacingOccurrences(of: titleMarker, with: title)
            .replacingOccurrences(of: bodyMarker, with: body)
    }
}
