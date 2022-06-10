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
    
    func addOperation(block: @escaping () -> Void) {
        group.enter()
        Thread.detachNewThread { [weak self] in
            block()
            self?.group.leave()
        }
    }
    
    func waitUntilAllOperationsAreFinished() {
        group.wait()
    }
}
