//
//  SSHAuthentication.swift
//  Mendoza
//
//  Created by Tomas Camin on 10/01/2019.
//

import Foundation

enum SSHAuthentication: Codable, Hashable {
    case credentials(username: String, password: String)
    /// privateKey will default to `~/.ssh/id_rsa` when nil
    case key(username: String, privateKey: String, publicKey: String?, passphrase: String?)
    /// If you've already added the necessary private key to ssh-agent, you can authenticate using the agent:
    case agent(username: String)
    // For localhost connections
    case none(username: String)

    var username: String {
        switch self {
        case let .credentials(username, _):
            return username
        case let .key(username, _, _, _):
            return username
        case let .agent(username):
            return username
        case let .none(username):
            return username
        }
    }
}

extension SSHAuthentication: CustomStringConvertible {
    var description: String {
        switch self {
        case .credentials:
            return "Username and password"
        case .key:
            return "SSH key"
        case .agent:
            return "SSH Agent"
        case .none:
            return "None"
        }
    }
}

extension SSHAuthentication {
    private enum CodingKeys: String, CodingKey {
        case credentialUsername
        case credentialPassword
        case keyUsername
        case keyPrivateKey
        case keyPublicKey
        case keyPassphrase
        case agentUsername
        case noneUsername
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let username = try container.decodeIfPresent(String.self, forKey: .credentialUsername),
            let password = try container.decodeIfPresent(String.self, forKey: .credentialPassword) {
            self = .credentials(username: username, password: password)
        } else if let username = try container.decodeIfPresent(String.self, forKey: .keyUsername) {
            self = .key(username: username,
                        privateKey: try container.decode(String.self, forKey: .keyPrivateKey),
                        publicKey: try container.decodeIfPresent(String.self, forKey: .keyPublicKey),
                        passphrase: try container.decodeIfPresent(String.self, forKey: .keyPassphrase))
        } else if let username = try container.decodeIfPresent(String.self, forKey: .agentUsername) {
            self = .agent(username: username)
        } else if let username = try container.decodeIfPresent(String.self, forKey: .noneUsername) {
            self = .none(username: username)
        } else {
            fatalError()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .credentials(username, password):
            try container.encode(username, forKey: .credentialUsername)
            try container.encode(password, forKey: .credentialPassword)
        case let .key(username, privateKey, publicKey, passphrase):
            try container.encode(username, forKey: .keyUsername)
            try container.encodeIfPresent(privateKey, forKey: .keyPrivateKey)
            try container.encodeIfPresent(publicKey, forKey: .keyPublicKey)
            try container.encodeIfPresent(passphrase, forKey: .keyPassphrase)
        case let .agent(username):
            try container.encode(username, forKey: .agentUsername)
        case let .none(username):
            try container.encode(username, forKey: .noneUsername)
        }
    }
}
