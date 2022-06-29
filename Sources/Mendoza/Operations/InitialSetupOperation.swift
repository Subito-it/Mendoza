//
//  InitialSetupOperation.swift
//  Mendoza
//
//  Created by Tomas Camin on 17/01/2019.
//

import Foundation

class InitialSetupOperation: BaseOperation<[String: [String: String]]?> {
    private let nodes: [Node]
    private lazy var pool: ConnectionPool = {
        makeConnectionPool(sources: nodes)
    }()
    private let syncQueue = DispatchQueue(label: String(describing: InitialSetupOperation.self))
    private let xcodeBuildNumber: String?

    init(nodes: [Node], xcodeBuildNumber: String?) {
        self.nodes = nodes
        self.xcodeBuildNumber = xcodeBuildNumber
    }

    override func main() {
        guard !isCancelled else { return }

        do {
            didStart?()
            
            var nodesEnvironment = [String: [String: String]]()

            let extractDeveloperDirEnvironmentalVariable: (String, Executer) -> Void = { [weak self] address, executer in
                if let xcodeBuildNumber = self?.xcodeBuildNumber {
                    let xcversion = XcodeVersion(executer: executer)
                    if let path = try? xcversion.path(buildNumber: xcodeBuildNumber) {
                        self?.syncQueue.sync { nodesEnvironment[address] = ["DEVELOPER_DIR": "\(path)/Contents/Developer"] }
                    }
                }
            }
            
            try pool.execute { executer, source in
                guard let maxUidProcessCountRaw = try executer.execute("sysctl kern.maxprocperuid").components(separatedBy: " ").last,
                      let maxUidProcessCount = Double(maxUidProcessCountRaw)
                else {
                    throw Error("Invalid maxprocperuid!")
                }

                let currentUidProcessCountRaw = try executer.execute("ps -u $(whoami) | awk 'END {print NR}'")
                guard let currentUidProcessCount = Double(currentUidProcessCountRaw) else {
                    throw Error("Invalid current procperuid!")
                }

                if currentUidProcessCount > maxUidProcessCount * 0.8 {
                    print("🚨 High number of processes detected, trying to mitigate by shutting down simulator")
                    try CommandLineProxy.Simulators(executer: executer, verbose: false).reset()
                }

                extractDeveloperDirEnvironmentalVariable(source.node.address, executer)
            }

            let executer = LocalExecuter()
            extractDeveloperDirEnvironmentalVariable(executer.address, executer)

            didEnd?(nodesEnvironment.count > 0 ? nodesEnvironment : nil)
        } catch {
            didThrow?(error)
        }
    }

    override func cancel() {
        if isExecuting {
            pool.terminate()
        }
        super.cancel()
    }
}
