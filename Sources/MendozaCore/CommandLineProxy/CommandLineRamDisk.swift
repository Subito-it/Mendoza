//
//  CommandLineRamDisk.swift
//  Mendoza
//
//  Created by Tomas Camin on 04/02/2019.
//

import Foundation

extension CommandLineProxy {
    struct RamDisk {
        private let executer: Executer

        init(executer: Executer) {
            self.executer = executer
        }

        func create(name: String, sizeMB: UInt, path: String = Path.base.rawValue) throws {
            guard try executer.fileExists(atPath: path) else { throw Error("Ram disk path does not exists", logger: executer.logger) }

            let listStatus = try executer.execute("diskutil list")
            guard try listStatus.capturedGroups(withRegexString: "(\(name))").isEmpty else { return }

            let ramDiskSize = sizeMB * 2048
            let ramDiskPath = try executer.execute("hdid -nomount ram://\(ramDiskSize)")
            guard let diskId = try ramDiskPath.capturedGroups(withRegexString: #"/dev/disk(\d+)"#).compactMap(UInt.init).first else {
                throw Error("Failed extracting ram disk identifier", logger: executer.logger)
            }

            do {
                _ = try executer.execute("newfs_hfs -v '\(name)' /dev/rdisk\(diskId)")
                _ = try executer.execute("diskutil mount -mountPoint '\(path)' /dev/disk\(diskId)")
            } catch {
                _ = try executer.execute("diskutil eject /dev/disk\(diskId) || true")

                throw error
            }
        }

        func eject(name: String, throwOnError: Bool) throws {
            guard let listStatus = try? executer.execute("diskutil info \(name) || true") else { return }
            guard let diskId = try? listStatus.capturedGroups(withRegexString: #"Device Identifier:.*disk(\d+)"#).compactMap(UInt.init).first else {
                if throwOnError {
                    throw Error("Failed finding disk identifier to eject", logger: executer.logger)
                } else {
                    return
                }
            }
            guard diskId != 0 else { return }

            let unmount = try executer.execute("diskutil unmount /dev/disk\(diskId) &>/dev/null || true")
            let eject = try executer.execute("diskutil eject /dev/disk\(diskId) &>/dev/null || true")

            #if DEBUG
                print("unmount \(unmount)")
                print("eject \(eject)")
            #endif
        }
    }
}
