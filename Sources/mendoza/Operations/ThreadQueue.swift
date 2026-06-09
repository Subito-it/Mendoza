//
//  ThreadQueue.swift
//  Mendoza
//
//  Created by tomas.camin on 08/06/22.
//

import Foundation

// This class mimicks the OperationQueue API overcoming the 64 thread limit

class ThreadQueue {
    private let group = DispatchGroup()
    private let concurrencySemaphore: DispatchSemaphore?

    /// - Parameter maxConcurrentOperations: when set, caps how many operations run
    ///   concurrently. `addOperation` blocks the caller once the cap is reached,
    ///   applying backpressure to the producer. When nil (default) operations run
    ///   unbounded, preserving the original behavior.
    init(maxConcurrentOperations: Int? = nil) {
        concurrencySemaphore = maxConcurrentOperations.map { DispatchSemaphore(value: $0) }
    }

    func addOperation(block: @escaping () -> Void) {
        group.enter()
        concurrencySemaphore?.wait()
        Thread.detachNewThread { [weak self] in
            block()
            self?.concurrencySemaphore?.signal()
            self?.group.leave()
        }
    }

    func waitUntilAllOperationsAreFinished() {
        group.wait()
    }
}
