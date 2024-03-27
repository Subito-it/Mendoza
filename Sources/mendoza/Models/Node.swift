//
//  Node.swift
//  Mendoza
//
//  Created by Tomas Camin on 10/01/2019.
//

import Foundation
import KeychainAccess

struct Node: Codable, Equatable, Hashable {
    enum ConcurrentTestRunners: Codable, Hashable {
        case manual(count: UInt)
        case autodetect
    }

    let name: String
    let address: String
    let authentication: SSHAuthentication?
    let concurrentTestRunners: ConcurrentTestRunners

    static func == (lhs: Node, rhs: Node) -> Bool {
        lhs.address == rhs.address
    }
}

// MARK: - CustomStringConvertible

extension Node: CustomStringConvertible {
    var description: String {
        var ret = ["name: \(name)", "address: \(address)"]
        if let authentication = authentication {
            ret += ["authentication: \(authentication)"]
        }

        return ret.joined(separator: "\n")
    }
}

// MARK: - Codable

extension Node {
    private struct Authentication: Codable {
        let ssh: SSHAuthentication
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case address
        case concurrentTestRunners
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        name = try container.decode(String.self, forKey: .name)
        address = try container.decode(String.self, forKey: .address)
        concurrentTestRunners = try container.decode(ConcurrentTestRunners.self, forKey: .concurrentTestRunners)

        let keychain = KeychainAccess.Keychain(service: Environment.bundle)

        if let authenticationData = try keychain.getData("\(name)_authentication") {
            let keychainAuthentication = try JSONDecoder().decode(Authentication.self, from: authenticationData)
            authentication = keychainAuthentication.ssh
        } else {
            authentication = nil
        }
    }

    static func localhost() -> Node {
        Node(name: "localhost", address: "localhost", authentication: .none, concurrentTestRunners: .autodetect)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(name, forKey: .name)
        try container.encode(address, forKey: .address)
        try container.encode(concurrentTestRunners, forKey: .concurrentTestRunners)

        if let authentication = authentication {
            let keychain = KeychainAccess.Keychain(service: Environment.bundle)
            let keychainAuthentication = Authentication(ssh: authentication) // swiftlint:disable:this redundant_nil_coalescing
            try keychain.set(JSONEncoder().encode(keychainAuthentication), key: "\(name)_authentication")
        }
    }
}

extension Node.ConcurrentTestRunners {
    private enum CodingKeys: String, CodingKey {
        case manualCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let count = try container.decodeIfPresent(UInt.self, forKey: .manualCount) {
            self = .manual(count: count)
        } else {
            self = .autodetect
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .manual(count):
            try container.encode(count, forKey: .manualCount)
        case .autodetect:
            break
        }
    }
}
