//
//  ConnectionPool.swift
//  Mendoza
//
//  Created by Tomas Camin on 27/01/2019.
//

import Foundation
import Shout

class ConnectionPool<SourceValue> {
    struct Source<Value> {
        let node: Node
        let value: Value
        let environment: [String: String]
        let logger: ExecuterLogger?
    }
    
    var startIntervals = [String: TimeInterval]()
    var endIntervals = [String: TimeInterval]()

    private let sources: [Source<SourceValue>]
    private let syncQueue = DispatchQueue(label: String(describing: ConnectionPool.self))
    private var executers = [Executer]()
    private let operationQueue = ThreadQueue()

    init(sources: [Source<SourceValue>]) {
        self.sources = sources
    }

    func execute(block: @escaping (_ executer: Executer, _ source: Source<SourceValue>) throws -> Void) throws {
        var errors = [Swift.Error]()

        for source in sources {
            operationQueue.addOperation { [weak self] in
                guard let self = self else { return }
                
                self.syncQueue.sync { [unowned self] in self.startIntervals[source.node.address] = CFAbsoluteTimeGetCurrent() }
                defer { self.syncQueue.sync { [unowned self] in self.endIntervals[source.node.address] = CFAbsoluteTimeGetCurrent() } }

                do {
                    let executer = try source.node.makeExecuter(logger: source.logger, environment: source.environment)
                    self.syncQueue.sync { [unowned self] in self.executers.append(executer) }

                    try block(executer, source)
                } catch {
                    self.syncQueue.sync { errors.append(error) }
                }
            }
        }

        operationQueue.waitUntilAllOperationsAreFinished()

        for error in errors {
            throw error
        }
    }

    func terminate() {
        executers.forEach { $0.terminate() }
    }
}

extension ConnectionPool.Source where Value == Void {
    init(node: Node, logger: ExecuterLogger?, environment: [String: String]) {
        self.node = node
        value = ()
        self.logger = logger
        self.environment = environment
    }
}
