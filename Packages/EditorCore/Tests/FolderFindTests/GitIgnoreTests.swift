//
//  GitIgnoreTests.swift
//  FolderFindTests
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
import TextFind
import FolderFind

struct GitIgnoreTests {

    private func make(_ contents: String, base: String = "") -> GitIgnore {

        var gitIgnore = GitIgnore()
        gitIgnore.add(contents: contents, base: base)
        return gitIgnore
    }


    @Test func commentsAndBlankLines() {

        let gitIgnore = self.make("# comment\n\n   \n")

        #expect(gitIgnore.isEmpty)
    }


    @Test func plainName() {

        let gitIgnore = self.make("build\n*.log\n")

        #expect(gitIgnore.isIgnored("build", isDirectory: true))
        #expect(gitIgnore.isIgnored("a/b/build", isDirectory: true))
        #expect(gitIgnore.isIgnored("a/debug.log", isDirectory: false))
        #expect(!gitIgnore.isIgnored("builder", isDirectory: true))
        #expect(!gitIgnore.isIgnored("a/log.txt", isDirectory: false))
    }


    @Test func directoryOnly() {

        let gitIgnore = self.make("vendor/\n")

        #expect(gitIgnore.isIgnored("vendor", isDirectory: true))
        #expect(gitIgnore.isIgnored("lib/vendor", isDirectory: true))
        #expect(!gitIgnore.isIgnored("vendor", isDirectory: false))
    }


    @Test func anchored() {

        let gitIgnore = self.make("/dist\ndocs/api\n")

        #expect(gitIgnore.isIgnored("dist", isDirectory: true))
        #expect(!gitIgnore.isIgnored("a/dist", isDirectory: true))
        #expect(gitIgnore.isIgnored("docs/api", isDirectory: true))
        #expect(!gitIgnore.isIgnored("x/docs/api", isDirectory: true))
    }


    @Test func doubleAsterisk() {

        let gitIgnore = self.make("**/cache\nlogs/**\na/**/b\n")

        #expect(gitIgnore.isIgnored("cache", isDirectory: true))
        #expect(gitIgnore.isIgnored("x/y/cache", isDirectory: true))
        #expect(gitIgnore.isIgnored("logs/today.txt", isDirectory: false))
        #expect(gitIgnore.isIgnored("a/b", isDirectory: true))
        #expect(gitIgnore.isIgnored("a/x/y/b", isDirectory: true))
        #expect(!gitIgnore.isIgnored("ab", isDirectory: true))
    }


    @Test func negation() {

        let gitIgnore = self.make(".env*\n!.env.example\n")

        #expect(gitIgnore.isIgnored(".env", isDirectory: false))
        #expect(gitIgnore.isIgnored(".env.local", isDirectory: false))
        #expect(!gitIgnore.isIgnored(".env.example", isDirectory: false))
    }


    @Test func characterClassAndEscape() {

        let gitIgnore = self.make("file[0-9].txt\nnot[!a].md\n\\#hash\n\\!bang\n")

        #expect(gitIgnore.isIgnored("file3.txt", isDirectory: false))
        #expect(!gitIgnore.isIgnored("fileA.txt", isDirectory: false))
        #expect(gitIgnore.isIgnored("notb.md", isDirectory: false))
        #expect(!gitIgnore.isIgnored("nota.md", isDirectory: false))
        #expect(gitIgnore.isIgnored("#hash", isDirectory: false))
        #expect(gitIgnore.isIgnored("!bang", isDirectory: false))
    }


    @Test func nestedBase() {

        var gitIgnore = self.make("*.tmp\n")
        gitIgnore.add(contents: "/out\n!keep.tmp\n", base: "sub")

        #expect(gitIgnore.isIgnored("sub/out", isDirectory: true))
        #expect(!gitIgnore.isIgnored("out", isDirectory: true))
        #expect(!gitIgnore.isIgnored("other/out", isDirectory: true))
        #expect(!gitIgnore.isIgnored("sub/keep.tmp", isDirectory: false))
        #expect(gitIgnore.isIgnored("keep.tmp", isDirectory: false))
    }
    
    
    @Test func searchSkipsGitIgnoredFiles() async throws {
        
        let rootURL = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let fileManager = FileManager.default
        defer { try? fileManager.removeItem(at: rootURL) }
        
        try fileManager.createDirectory(at: rootURL.appending(path: "build"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: rootURL.appending(path: "src/gen"), withIntermediateDirectories: true)
        try "build/\n".write(to: rootURL.appending(path: ".gitignore"), atomically: true, encoding: .utf8)
        try "gen/\n".write(to: rootURL.appending(path: "src/.gitignore"), atomically: true, encoding: .utf8)
        for path in ["build/a.txt", "src/b.txt", "src/gen/c.txt"] {
            try "needle\n".write(to: rootURL.appending(path: path), atomically: true, encoding: .utf8)
        }
        let pattern = try FolderFind.Query(findString: "needle", mode: .textual(options: [], fullWord: false)).pattern()
        
        var search = try Search(rootURL: rootURL, pattern: pattern)
        #expect(try await search.run().files.map(\.filename) == ["b.txt"])
        
        var inclusiveSearch = try Search(rootURL: rootURL, pattern: pattern, options: .init(includesGitIgnoredFiles: true))
        #expect(try await inclusiveSearch.run().files.map(\.filename).sorted() == ["a.txt", "b.txt", "c.txt"])
    }
}
