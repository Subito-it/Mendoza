//
//  LoggerCoordinator.swift
//  Mendoza
//
//  Created by Tomas Camin on 04/02/2019.
//

import Foundation

class LoggerCoordinator<T: Logger> {
    private let loggers: [T]

    init(loggers: [T]) {
        self.loggers = loggers
    }

    func dump() throws {
        try writeIndex()

        try loggers.forEach { try $0.dump() }
    }

    private func writeIndex() throws {
        let removeExtension: (String) -> String = {
            $0.replacingOccurrences(of: ".html", with: "")
        }

        var content = ""

        let failingLogFilenames = loggers.filter { $0.hasErrors }.map { $0.filename }.sorted()
        if !failingLogFilenames.isEmpty {
            content = "<h2>Failures</h2>\n"

            content += failingLogFilenames
                .map { "<a href='\($0)'>\(removeExtension($0))</a>" }
                .joined(separator: "<br />\n")
            content += "<br />\n"
        }

        content += "<h2>Logs</h2>\n"
        let allFilenames = loggers.filter { !$0.isEmpty }.map { $0.filename }.sorted()

        content += allFilenames
            .map { "<a href='\($0)'>\(removeExtension($0))</a>" }
            .joined(separator: "<br />\n")

        let url = Path.logs.url.appendingPathComponent("index.html")
        try LoggerCoordinator.html(content: content)
            .data(using: .utf8)?
            .write(to: url)
    }
}

extension LoggerCoordinator {
    static func html(content: String) -> String {
        let contentMarker = "{{ content }}"
        return """
        <html>
        <meta charset="UTF-8">
        <head>
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, Menlo;
                    font-weight: normal;
                }
                a, a:visited, a:hover, a:active {
                    color: inherit;
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
        \(contentMarker)
        </body>
        </html>
        """.replacingOccurrences(of: contentMarker, with: content)
    }
}

extension LoggerCoordinator where T == ExecuterLogger {
    convenience init(operations: [LoggedOperation]) {
        let loggers = operations.reduce([ExecuterLogger]()) { $0 + $1.loggers }
        self.init(loggers: loggers)
    }
}
