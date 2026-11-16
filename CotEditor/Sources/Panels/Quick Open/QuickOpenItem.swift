//
//  QuickOpenItem.swift
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
import StringUtils
import FolderFind

/// A file candidate for Quick Open.
struct QuickOpenItem: Identifiable, Equatable, Sendable {

    var fileURL: URL
    var name: String
    /// The path relative to the project root (or the abbreviated full path for non-project files).
    var path: String

    var id: URL  { self.fileURL }


    init(fileURL: URL, relativeTo rootURL: URL?) {

        self.fileURL = fileURL
        self.name = fileURL.lastPathComponent

        if let rootURL {
            self.path = Self.relativePath(of: fileURL, rootPrefix: Self.rootPrefix(for: rootURL))
        } else {
            self.path = (fileURL.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath
        }
    }


    /// Creates an item in a project by reusing the root prefix among the files in the same project.
    ///
    /// - Parameters:
    ///   - fileURL: The file URL.
    ///   - rootPrefix: The prefix obtained by `rootPrefix(for:)`.
    init(fileURL: URL, rootPrefix: String) {

        self.fileURL = fileURL
        self.name = fileURL.lastPathComponent
        self.path = Self.relativePath(of: fileURL, rootPrefix: rootPrefix)
    }


    /// Returns the path prefix to strip from the files in the given project folder.
    static func rootPrefix(for rootURL: URL) -> String {

        let rootPath = rootURL.standardizedFileURL.path(percentEncoded: false)

        return rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
    }


    static func relativePath(of fileURL: URL, rootPrefix: String) -> String {

        let filePath = fileURL.standardizedFileURL.path(percentEncoded: false)

        return filePath.hasPrefix(rootPrefix) ? String(filePath.dropFirst(rootPrefix.count)) : filePath
    }
}


extension QuickOpenItem {

    struct Match: Equatable, Sendable {

        var nameRanges: [Range<String.Index>]
        var pathRanges: [Range<String.Index>]
        var score: Int
    }


    /// A query prepared once to be matched against many items.
    struct Query: Sendable {

        /// The user input without whitespace.
        var string: String

        /// The lowercased UTF-8 bytes of the query if it consists only of ASCII characters.
        private var asciiLowercased: [UInt8]?

        var isEmpty: Bool  { self.string.isEmpty }


        init(_ input: String) {

            self.string = input.filter { !$0.isWhitespace }

            let utf8 = self.string.utf8
            self.asciiLowercased = utf8.allSatisfy { $0 < 0x80 }
                ? utf8.map { (0x41...0x5A).contains($0) ? $0 | 0x20 : $0 }
                : nil
        }


        /// Cheaply checks whether the query can match the given string.
        ///
        /// - Parameter string: The string to test.
        /// - Returns: `false` only if the query certainly doesn't match.
        fileprivate func canMatch(_ string: String) -> Bool {

            guard let query = self.asciiLowercased else { return true }

            var index = 0
            for byte in string.utf8 {
                // -> Leave non-ASCII strings to the full matcher.
                if byte >= 0x80 || index == query.count { return true }

                if ((0x41...0x5A).contains(byte) ? byte | 0x20 : byte) == query[index] {
                    index += 1
                }
            }

            return index == query.count
        }
    }


    /// Fuzzy matches the query against the filename first, then the relative path (like VS Code).
    ///
    /// - Parameter query: The prepared user input.
    /// - Returns: The match result where a smaller score is better, or `nil` if not matched.
    func match(_ query: Query) -> Match? {

        guard !query.isEmpty else { return Match(nameRanges: [], pathRanges: [], score: 0) }

        // match against the filename
        if query.canMatch(self.name),
           let ranges = self.name.abbreviatedMatchedRanges(with: query.string), let first = ranges.first, let last = ranges.last
        {
            let span = self.name.distance(from: first.lowerBound, to: last.upperBound)
            var score = span * 10 + self.name.count
            if first.lowerBound == self.name.startIndex { score -= 500 }  // prefix bonus
            if self.name.localizedCaseInsensitiveCompare(query.string) == .orderedSame { score -= 1000 }  // exact
            score += self.path.count  // prefer shallower files
            return Match(nameRanges: ranges, pathRanges: [], score: score)
        }

        // match against the relative path
        if query.canMatch(self.path),
           let ranges = self.path.abbreviatedMatchedRanges(with: query.string), let first = ranges.first, let last = ranges.last
        {
            let span = self.path.distance(from: first.lowerBound, to: last.upperBound)
            return Match(nameRanges: [], pathRanges: ranges, score: 10_000 + span * 10 + self.path.count)
        }

        return nil
    }
}


enum QuickOpenFileCollector {

    /// The folder names that are skipped when collecting project files.
    static let ignoredFolderNames: Set<String> = [".git", ".svn", ".hg", "node_modules", ".build", "DerivedData", "Pods", ".swiftpm",
                                                  ".Trash", ".Trashes", ".Spotlight-V100", ".fseventsd", ".DocumentRevisions-V100"]

    /// The file names that are skipped when collecting project files.
    static let ignoredFileNames: Set<String> = [".DS_Store", ".localized"]

    /// The maximum number of files to collect.
    static let limit = 50_000


    /// Recursively collects the files in the given folder.
    ///
    /// - Parameters:
    ///   - rootURL: The project folder.
    ///   - includesGitIgnoredFiles: Whether files and folders matched by `.gitignore` rules are included.
    /// - Returns: The file items.
    static func collect(in rootURL: URL, includesGitIgnoredFiles: Bool = false) async -> [QuickOpenItem] {

        let task = Task.detached(priority: .userInitiated) { () -> [QuickOpenItem] in
            let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isAliasFileKey]
            let keySet = Set(keys)
            guard let enumerator = FileManager.default.enumerator(at: rootURL, includingPropertiesForKeys: keys,
                                                                  options: [.skipsPackageDescendants])
            else { return [] }

            let rootPrefix = QuickOpenItem.rootPrefix(for: rootURL)

            // honor the ignore rules of Git: `.git/info/exclude` first, then `.gitignore` files from the root down
            var gitIgnore: GitIgnore?
            if !includesGitIgnoredFiles {
                gitIgnore = GitIgnore()
                gitIgnore?.loadRoot(rootURL)
            }

            var items: [QuickOpenItem] = []
            while let url = enumerator.nextObject() as? URL {
                if Task.isCancelled { return [] }
                if items.count >= Self.limit { break }

                guard let values = try? url.resourceValues(forKeys: keySet) else { continue }

                let path = QuickOpenItem.relativePath(of: url, rootPrefix: rootPrefix)

                if values.isDirectory == true {
                    if Self.ignoredFolderNames.contains(url.lastPathComponent) || gitIgnore?.isIgnored(path, isDirectory: true) == true {
                        enumerator.skipDescendants()
                    } else {
                        // -> The enumerator visits a folder before its contents.
                        gitIgnore?.load(in: url, base: path)
                    }
                    continue
                }
                guard values.isRegularFile == true || values.isAliasFile == true else { continue }
                guard !Self.ignoredFileNames.contains(url.lastPathComponent) else { continue }
                guard gitIgnore?.isIgnored(path, isDirectory: false) != true else { continue }

                items.append(QuickOpenItem(fileURL: url, rootPrefix: rootPrefix))
            }

            return items.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        }

        // -> A detached task doesn't inherit the cancellation of the caller.
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }
}
