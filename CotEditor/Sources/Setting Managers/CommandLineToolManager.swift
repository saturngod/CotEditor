//
//  CommandLineToolManager.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2020-08-22.
//
//  ---------------------------------------------------------------------------
//
//  © 2020-2025 1024jp
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation
import UniformTypeIdentifiers
import URLUtils

final class CommandLineToolManager: Sendable {

    /// The name of the command installed in `/usr/local/bin`.
    static let commandName = "yayeditor"


    struct InstallationError: LocalizedError {

        var errorDescription: String?
    }

    enum Status {
        
        case none
        case validTarget
        case differentTarget
        case invalidTarget
        
        var installed: Bool { self != .none }
    }
    
    
    // MARK: Public Properties
    
    let linkURL: URL
    
    private let bundledCommandURL: URL
    private let preferredLinkURL: URL
    private let preferredApplicationURL: URL  // path to .app in /Applications directory
    
    
    // MARK: Public Methods
    
    init(bundle: Bundle = .main) {
        
        self.bundledCommandURL = bundle.cotURL!
        self.preferredLinkURL = URL(filePath: "/usr/local/bin/").appending(component: Self.commandName)
        self.preferredApplicationURL = URL.applicationDirectory
            .appendingPathComponent(bundle.bundleName, conformingTo: .application)
        
        // check only preferred link location
        self.linkURL = self.preferredLinkURL
    }
    
    
    /// Checks the destination of symlink and return whether `cot` command is exists at '/usr/local/bin/'.
    ///
    /// - Returns: The result status.
    func validateSymlink() -> Status {
        
        if !self.linkURL.isReachable { return .none }
        
        let url = self.linkURL.resolvingSymlinksInPath()
        
        guard url.isReachable else { return .invalidTarget }
        
        if url == self.linkURL ||
           url == self.bundledCommandURL ||
           url == Bundle(url: self.preferredApplicationURL)?.cotURL
        { return .validTarget }
        
        return .differentTarget
    }


    /// Creates (or replaces) the symbolic link to the bundled command-line tool.
    ///
    /// Asks for administrator privileges if the link location isn't writable for the current user.
    @MainActor func install() throws {

        let source = self.bundledCommandURL.path(percentEncoded: false)
        let destination = self.linkURL.path(percentEncoded: false)
        let directory = self.linkURL.deletingLastPathComponent().path(percentEncoded: false)

        // try without privileges first
        do {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: destination)) != nil || FileManager.default.fileExists(atPath: destination) {
                try FileManager.default.removeItem(atPath: destination)
            }
            try FileManager.default.createSymbolicLink(atPath: destination, withDestinationPath: source)
            return
        } catch {
            // fall back to the administrator privileges
        }

        try Self.runPrivileged("mkdir -p \(directory.shellQuoted) && ln -sfn \(source.shellQuoted) \(destination.shellQuoted)")
    }


    /// Removes the installed symbolic link.
    ///
    /// Asks for administrator privileges if the link location isn't writable for the current user.
    @MainActor func uninstall() throws {

        let destination = self.linkURL.path(percentEncoded: false)

        // remove only symbolic links to avoid deleting an unrelated file
        guard (try? FileManager.default.destinationOfSymbolicLink(atPath: destination)) != nil else { return }

        do {
            try FileManager.default.removeItem(atPath: destination)
        } catch {
            try Self.runPrivileged("rm -f \(destination.shellQuoted)")
        }
    }


    // MARK: Private Methods

    /// Runs a shell command with administrator privileges via AppleScript.
    ///
    /// - Parameter command: The shell command to run.
    @MainActor private static func runPrivileged(_ command: String) throws {

        let escaped = command
            .replacing("\\", with: "\\\\")
            .replacing("\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"

        var errorInfo: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)

        if let errorInfo {
            // -128: user canceled
            if errorInfo[NSAppleScript.errorNumber] as? Int == -128 { throw CancellationError() }
            throw InstallationError(errorDescription: errorInfo[NSAppleScript.errorMessage] as? String)
        }
    }
}


private extension String {

    /// The string quoted for safe use as a single shell argument.
    var shellQuoted: String {

        "'" + self.replacing("'", with: "'\\''") + "'"
    }
}


private extension Bundle {
    
    var cotURL: URL? {
        
        self.sharedSupportURL?.appending(components: "bin", "cot").standardizedFileURL
    }
}
