//
//  ProcessKillerOperation.swift
//  Mendoza
//
//  Created by Tomas Camin on 07/10/2023.
//

import Foundation

// Ported from https://github.com/biscuitehh/yeetd

class ProcessKillerOperation: BaseOperation<Void> {
    private let nodes: [Node]
    private lazy var pool: ConnectionPool = makeConnectionPool(sources: nodes)
    
    private let processes = [
        "AegirPoster",
        "InfographPoster",
        "CollectionsPoster",
        "ExtragalacticPoster",
        "KaleidoscopePoster",
        "EmojiPosterExtension",
        "AmbientPhotoFramePosterProvider",
        "PhotosPosterProvider",
        "AvatarPosterExtension",
        "GradientPosterExtension",
        "MonogramPosterExtension",
        "UnityPosterExtension",
        "PridePosterExtension",
        "healthappd" // https://github.com/biscuitehh/yeetd/pull/4
    ]
    
    private let killPeriodSeconds = 5.0

    init(nodes: [Node]) {
        self.nodes = nodes
    }

    override func main() {
        guard !isCancelled else { return }

        do {
            didStart?()

            try pool.execute { [unowned self] executer, source in
                while !isCancelled {
                    _ = try? executer.execute("pkill \(processes.joined(separator: " "))")
                    Thread.sleep(forTimeInterval: killPeriodSeconds)
                }
            }

            didEnd?(())
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
