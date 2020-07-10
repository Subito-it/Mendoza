//
//  AddressType.swift
//  Mendoza
//
//  Created by Tomas Camin on 30/01/2019.
//

import Foundation

enum AddressType {
    private static var localAddresses: Set<String> = {
        let localExecuter = LocalExecuter()
        let localHostname = try! localExecuter.execute("hostname", currentUrl: nil, progress: nil, rethrow: nil)
        let localAddresses = try! localExecuter.execute(#"ifconfig 2>/dev/null | grep 'inet ' | awk '{print $2}' | grep '\d\{1,3\}\.\d\{1,3\}\.\d\{1,3\}\.\d\{1,3\}'"#, currentUrl: nil, progress: nil, rethrow: nil)

        return Set([localHostname, "localhost"] + localAddresses.components(separatedBy: "\n"))
    }()

    case local
    case remote

    init(node: Node) {
        self = AddressType.localAddresses.contains(node.address) ? .local : .remote
    }

    init(address: String) {
        self = AddressType.localAddresses.contains(address) ? .local : .remote
    }
}
