//
//  Executer.swift
//  Mendoza
//
//  Created by Tomas Camin on 12/01/2019.
//

import Foundation
import Shout

protocol Executer {
    var currentDirectoryPath: String? { get set }
    var homePath: String { get }
    var address: String { get }

    var logger: ExecuterLogger? { get set }

    func clone() throws -> Self

    func execute(_ command: String, currentUrl: URL?, progress: ((String) -> Void)?, rethrow: (((status: Int32, output: String), Error) throws -> Void)?) throws -> String
    func capture(_ command: String, currentUrl: URL?, progress: ((String) -> Void)?, rethrow: (((status: Int32, output: String), Error) throws -> Void)?) throws -> (status: Int32, output: String)

    func fileExists(atPath: String) throws -> Bool
    func download(remotePath: String, localUrl: URL) throws
    func upload(localUrl: URL, remotePath: String) throws

    func terminate()
}

extension Executer {
    static func executablePathExport() -> String {
        "export PATH=~/.rbenv/shims:/usr/bin:/usr/local/bin:/usr/sbin:/sbin:/bin;"
    }
}

// MARK: - Default parameters

extension Executer {
    func execute(_ command: String) throws -> String {
        try capture(command, currentUrl: nil, progress: nil, rethrow: nil).output
    }

    func capture(_ command: String) throws -> (status: Int32, output: String) {
        try capture(command, currentUrl: nil, progress: nil, rethrow: nil)
    }
}

// MARK: - Default parameters

extension Executer {
    func execute(_ command: String, progress: ((String) -> Void)?) throws -> String {
        try capture(command, currentUrl: nil, progress: progress, rethrow: nil).output
    }

    func capture(_ command: String, progress: ((String) -> Void)?) throws -> (status: Int32, output: String) {
        try capture(command, currentUrl: nil, progress: progress, rethrow: nil)
    }
}

// MARK: - Default parameters

extension Executer {
    func execute(_ command: String, progress: ((String) -> Void)?, rethrow: @escaping ((status: Int32, output: String), Error) throws -> Void) throws -> String {
        try capture(command, currentUrl: nil, progress: progress, rethrow: rethrow).output
    }

    func capture(_ command: String, progress: ((String) -> Void)?, rethrow: @escaping ((status: Int32, output: String), Error) throws -> Void) throws -> (status: Int32, output: String) {
        try capture(command, currentUrl: nil, progress: progress, rethrow: rethrow)
    }
}

// MARK: - Default parameters

extension Executer {
    func execute(_ command: String, rethrow: @escaping ((status: Int32, output: String), Error) throws -> Void) throws -> String {
        try capture(command, currentUrl: nil, progress: nil, rethrow: rethrow).output
    }

    func capture(_ command: String, rethrow: @escaping ((status: Int32, output: String), Error) throws -> Void) throws -> (status: Int32, output: String) {
        try capture(command, currentUrl: nil, progress: nil, rethrow: rethrow)
    }
}

// MARK: - Default parameters

extension Executer {
    func execute(_ command: String, currentUrl: URL) throws -> String {
        try capture(command, currentUrl: currentUrl, progress: nil, rethrow: nil).output
    }

    func capture(_ command: String, currentUrl: URL) throws -> (status: Int32, output: String) {
        try capture(command, currentUrl: currentUrl, progress: nil, rethrow: nil)
    }
}

// MARK: - Default parameters

extension Executer {
    func execute(_ command: String, currentUrl: URL, rethrow: @escaping ((status: Int32, output: String), Error) throws -> Void) throws -> String {
        try capture(command, currentUrl: currentUrl, progress: nil, rethrow: rethrow).output
    }

    func capture(_ command: String, currentUrl: URL, rethrow: @escaping ((status: Int32, output: String), Error) throws -> Void) throws -> (status: Int32, output: String) {
        try capture(command, currentUrl: currentUrl, progress: nil, rethrow: rethrow)
    }
}
