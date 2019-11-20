//
//  BaseOperation.swift
//  Mendoza
//
//  Created by Tomas Camin on 17/01/2019.
//

import Foundation

protocol Starting: Operation {
    var didStart: (() -> Void)? { get set }
}

protocol Ending: Operation {
    associatedtype OutputType
    var didEnd: ((OutputType) -> Void)? { get set }
}

protocol Throwing: Operation {
    var didThrow: ((Swift.Error) -> Void)? { get set }
}

protocol LoggedOperation {
    var logger: ExecuterLogger { get }
    var loggers: Set<ExecuterLogger> { get set }
}

class BaseOperation<Output: Any>: Operation, Starting, Ending, Throwing, LoggedOperation {
    typealias OutputType = Output
    
    var didStart: (() -> Void)?
    var didEnd: ((Output) -> Void)?
    var didThrow: ((Swift.Error) -> Void)?
    
    lazy var logger = ExecuterLogger(name: "\(type(of: self))", address: "operation")
    var loggers = Set<ExecuterLogger>()
    
    var startTimeInterval: TimeInterval = 0.0
    
    private var isExecutingObserver: NSKeyValueObservation?
    
    override init() {
        super.init()
        
        isExecutingObserver = observe(\BaseOperation.isExecuting) { [unowned self] (op, _) in
            guard !op.isCancelled else { return }
            
            if op.isExecuting {
                self.startTimeInterval = CFAbsoluteTimeGetCurrent()
                print("🏃‍♀️ `\(op.className.components(separatedBy: ".").last ?? op.className)` did start".bold)
            } else {
                let delta = CFAbsoluteTimeGetCurrent() - self.startTimeInterval
                print("🏁 `\(op.className.components(separatedBy: ".").last ?? op.className)` did complete in \(delta)s".bold)
            }
        }
        loggers.insert(logger)
    }
    
    deinit {
        isExecutingObserver = nil
    }
    
    func makeConnectionPool<T>(sources: [(node: Node, value: T)]) -> ConnectionPool<T> {
        var usedLoggerAddress = [String]()
        let logger: (Node) -> ExecuterLogger = { node in
            let addressCount = usedLoggerAddress.filter { $0 == node.address }.count
            usedLoggerAddress.append(node.address)
            
            var loggerName = "\(type(of: self))"
            if addressCount > 0 { loggerName += "-\(addressCount + 1)" }
            
            return ExecuterLogger(name: loggerName, address: node.address)
        }
        
        let poolSources = sources.map { ConnectionPool<T>.Source(node: $0.node, value: $0.value, logger: logger($0.node)) }
        let pool = ConnectionPool(sources: poolSources)
        
        let poolLoggers = Set(poolSources.compactMap { $0.logger })
        loggers = loggers.union(poolLoggers)
        
        return pool
    }
    
    func makeConnectionPool(sources: [Node]) -> ConnectionPool<Void> {
        return makeConnectionPool(sources: sources.map { (node: $0, value: ()) })
    }
        
    func makeLocalExecuter(currentDirectoryPath: String? = nil) -> LocalExecuter {
        let address = "localhost"
        var loggerName = "\(type(of: self))"
        let addressCount = loggers.filter { $0.name == loggerName && $0.address == address }.count
        
        if addressCount > 0 { loggerName += "-\(addressCount + 1)" }
        
        let logger = ExecuterLogger(name: loggerName, address: address)
        let executerLogger = loggers.update(with: logger)
        return LocalExecuter(currentDirectoryPath: currentDirectoryPath, logger: executerLogger ?? logger)
    }
    
    func makeRemoteExecuter(node: Node, currentDirectoryPath: String? = nil) -> RemoteExecuter {
        let address = node.address
        let addressCount = loggers.filter { $0.address == address }.count
        
        var loggerName = "\(type(of: self))"
        if addressCount > 0 { loggerName += "-\(addressCount + 1)" }

        let logger = ExecuterLogger(name: loggerName, address: address)
        let executerLogger = loggers.update(with: logger)
        return RemoteExecuter(node: node, currentDirectoryPath: currentDirectoryPath, logger: executerLogger ?? logger)
    }
}

enum Path: String, CaseIterable {
    case base, build, testBundle, logs, results, temp

    var rawValue: String {
        switch self {
        case .base: return Environment.temporaryBasePath
        case .build: return Path.base.rawValue.appending("/build")
        case .testBundle: return Path.build.rawValue.appending("/Build/Products")
        case .logs: return Path.base.rawValue.appending("/logs")
        case .results: return Path.base.rawValue.appending("/results")
        case .temp: return Path.base.rawValue.appending("/tmp")
        }
    }
    
    var url: URL {
        return URL(fileURLWithPath: self.rawValue)
    }
}
