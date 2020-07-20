//
//  Coverage.swift
//  Mendoza
//
//  Created by Tomas Camin on 26/02/2019.
//
// https://github.com/llvm-mirror/llvm/blob/master/tools/llvm-cov/CoverageExporterJson.cpp

import Foundation

struct Coverage: Codable {
    let version: String
    let type: String
    let data: [Data]
}

extension Coverage {
    struct Data: Codable {
        let files: [File]
        let functions: [Function]
        let totals: Stats
    }
}

extension Coverage.Data {
    struct File: Codable {
        let filename: String
        let segments: [[Int]]?
        let expansions: [Expansion]?
        let summary: Stats?
    }

    struct Function: Codable {
        let name: String?
        let count: Int?
        let regions: [[Int]]?
        let filenames: [String]?
    }

    struct Stats: Codable {
        struct Item: Codable {
            let count: Int?
            let covered: Int?
            let notcovered: Int?
            let percent: Int?
        }

        let lines: Item?
        let functions: Item?
        let instantiations: Item?
        let regions: Item?
    }
}

extension Coverage.Data.File {
    struct Expansion: Codable {
        let sourceRegion: [Int]?
        let targetRegions: [[Int]]?
        let filenames: [String]?

        enum CodingKeys: String, CodingKey {
            case sourceRegion = "source_region"
            case targetRegions = "target_regions"
            case filenames
        }
    }
}
