//
//  QuickOpenFileCollectorTests.swift
//
//  CotEditor
//  https://coteditor.com
//
//  ---------------------------------------------------------------------------
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
import Testing
@testable import CotEditor

struct QuickOpenFileCollectorTests {
    
    @Test func skipsGitIgnoredFiles() async throws {

        let rootURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let fileManager = FileManager.default
        defer { try? fileManager.removeItem(at: rootURL) }

        try fileManager.createDirectory(at: rootURL.appending(path: "dist"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: rootURL.appending(path: "src/gen"), withIntermediateDirectories: true)
        try "dist/\n.env.local\n".write(to: rootURL.appending(path: ".gitignore"), atomically: true, encoding: .utf8)
        try "gen/\n".write(to: rootURL.appending(path: "src/.gitignore"), atomically: true, encoding: .utf8)
        for path in [".env", ".env.local", "dist/bundle.js", "src/main.js", "src/gen/out.js"] {
            try "".write(to: rootURL.appending(path: path), atomically: true, encoding: .utf8)
        }

        let paths = await QuickOpenFileCollector.collect(in: rootURL).map(\.path)

        #expect(paths == [".env", ".gitignore", "src/.gitignore", "src/main.js"])
    }
    
    
    @Test func includesGitIgnoredFilesWhenRequested() async throws {
        
        let rootURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let fileManager = FileManager.default
        defer { try? fileManager.removeItem(at: rootURL) }
        
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try ".env\n".write(to: rootURL.appending(path: ".gitignore"), atomically: true, encoding: .utf8)
        try "".write(to: rootURL.appending(path: ".env"), atomically: true, encoding: .utf8)
        
        let paths = await QuickOpenFileCollector.collect(in: rootURL, includesGitIgnoredFiles: true).map(\.path)
        
        #expect(paths == [".env", ".gitignore"])
    }
}
