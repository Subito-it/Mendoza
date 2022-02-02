//
//  Shell.swift
//  Mendoza
//
//  Created by Tomas Camin on 02/02/2022.
//

import Foundation

enum Shell: String, CaseIterable {
    case bash = "/bin/bash"
    case zsh = "/bin/zsh"

    var source: String {
        switch self {
        case .bash:
            return "source ~/.bash_profile; shopt -s huponexit;"
        case .zsh:
            return "source ~/.zshrc; setopt hup;"
        }
    }

    var url: URL {
        return URL(fileURLWithPath: rawValue)
    }

    static func current() -> Shell {
        let fm = FileManager.default
        let homeUrl = URL(fileURLWithPath: NSHomeDirectory())


        for shell in Shell.allCases {
            if shell == .bash, fm.fileExists(atPath: homeUrl.appendingPathComponent(".bash_profile").path) {
                return shell
            } else if shell == .zsh, fm.fileExists(atPath: homeUrl.appendingPathComponent(".zshrc").path) {
                return shell
            }
        }

        fatalError("No known shell found!")
    }
}
