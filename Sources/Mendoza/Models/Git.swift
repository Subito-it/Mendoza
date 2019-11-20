//
//  Git.swift
//  Mendoza
//
//  Created by Tomas Camin on 10/01/2019.
//

import Foundation

struct Git {
    private let executer: Executer
    
    init(executer: Executer) {
        self.executer = executer
    }
    
    func valid() -> Bool {
        let gitInited = (try? executer.capture("git diff --exit-code"))?.status != 129
        let hasRefs = (try? executer.capture("git show-ref"))?.output.isEmpty == false
        
        return gitInited && hasRefs
    }
    
    func clean() -> Bool {
        return (try? executer.capture("git diff --exit-code"))?.status == 0
    }
    
    func status() throws -> GitStatus {
        return GitStatus(url: try url(), branch: try branchName(), commitMessage: try commitMessage(), commitHash: try commitHash())
    }
    
    private func url() throws -> URL {
        let url = try executer.execute("git rev-parse --show-toplevel")
        return URL(fileURLWithPath: url)
    }
    
    func fetch() throws {
        _ = try executer.execute("git fetch --all")
    }

    func pull() throws {
        _ = try executer.execute("git pull")
    }

    func branchName() throws -> String {
        return try executer.execute(#"git show -s --pretty=%D HEAD | sed -e 's/ -> / /g' | sed -e 's/,//g' | sed -e 's/origin\///g' | awk '{print $2}'"#)
    }

    func commitMessage() throws -> String {
        return try executer.execute("git log -1 --pretty=%B HEAD")
    }

    func commitHash() throws -> String {
        return try executer.execute("git rev-parse HEAD")
    }
}
