//
//  InitialSetupOperation.swift
//  Mendoza
//
//  Created by Tomas Camin on 17/01/2019.
//

import Foundation

class InitialSetupOperation: BaseOperation<[String: [String: String]]?> {
    private let nodes: [Node]
    private lazy var pool: ConnectionPool = makeConnectionPool(sources: nodes)

    private let syncQueue = DispatchQueue(label: String(describing: InitialSetupOperation.self))
    private let xcodeBuildNumber: String?
    private let configuration: Configuration

    init(configuration: Configuration, nodes: [Node], xcodeBuildNumber: String?) {
        self.configuration = configuration
        self.nodes = nodes
        self.xcodeBuildNumber = xcodeBuildNumber
    }

    override func main() {
        guard !isCancelled else { return }

        do {
            didStart?()

            var nodesEnvironment = [String: [String: String]]()

            let extractDeveloperDirEnvironmentalVariable: (String, Executer) throws -> Void = { [weak self] address, executer in
                if let xcodeBuildNumber = self?.xcodeBuildNumber {
                    let xcversion = XcodeVersion(executer: executer)
                    if let path = try? xcversion.path(buildNumber: xcodeBuildNumber) {
                        self?.syncQueue.sync { nodesEnvironment[address]?["DEVELOPER_DIR"] = "\(path)/Contents/Developer" }
                    } else {
                        throw Error("Xcode with build number \(xcodeBuildNumber) not found on \(executer.address)!", logger: executer.logger)
                    }
                }
            }

            let extractEnvironmentalVariables: (String, Executer) throws -> Void = { [weak self] address, executer in
                guard let rawLines = try? executer.execute("env").components(separatedBy: "\n") else { return }

                var currentEnvironment = [String: String]()
                for line in rawLines {
                    if let groups = try? line.capturedGroups(withRegexString: "(.+)=(.+)"), groups.count == 2 {
                        currentEnvironment[groups[0]] = groups[1]
                    }
                }
                self?.syncQueue.sync { nodesEnvironment[address] = currentEnvironment }

                try extractDeveloperDirEnvironmentalVariable(address, executer)
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

                try extractEnvironmentalVariables(source.node.address, executer)
            }

            let executer = LocalExecuter()
            try extractEnvironmentalVariables(executer.address, executer)

            let destinationNode = configuration.resultDestination.node
            let logger = ExecuterLogger(name: "\(type(of: self))", address: destinationNode.address)
            if let executer = try? destinationNode.makeExecuter(logger: logger, environment: nodesEnvironment[destinationNode.address] ?? [:]) {
                try extractEnvironmentalVariables(destinationNode.address, executer)
            }

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
