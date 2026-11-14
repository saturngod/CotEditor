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
            let rootPath = rootURL.standardizedFileURL.path(percentEncoded: false)
            let filePath = fileURL.standardizedFileURL.path(percentEncoded: false)
            let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
            self.path = filePath.hasPrefix(prefix) ? String(filePath.dropFirst(prefix.count)) : filePath
        } else {
            self.path = (fileURL.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath
        }
    }
}


extension QuickOpenItem {

    struct Match: Equatable, Sendable {

        var nameRanges: [Range<String.Index>]
        var pathRanges: [Range<String.Index>]
        var score: Int
    }


    /// Fuzzy matches the query against the filename first, then the relative path (like VS Code).
    ///
    /// - Parameter query: The user input.
    /// - Returns: The match result where a smaller score is better, or `nil` if not matched.
    func match(_ query: String) -> Match? {

        let query = query.filter { !$0.isWhitespace }

        guard !query.isEmpty else { return Match(nameRanges: [], pathRanges: [], score: 0) }

        // match against the filename
        if let ranges = self.name.abbreviatedMatchedRanges(with: query), let first = ranges.first, let last = ranges.last {
            let span = self.name.distance(from: first.lowerBound, to: last.upperBound)
            var score = span * 10 + self.name.count
            if first.lowerBound == self.name.startIndex { score -= 500 }  // prefix bonus
            if self.name.localizedCaseInsensitiveCompare(query) == .orderedSame { score -= 1000 }  // exact
            score += self.path.count  // prefer shallower files
            return Match(nameRanges: ranges, pathRanges: [], score: score)
        }

        // match against the relative path
        if let ranges = self.path.abbreviatedMatchedRanges(with: query), let first = ranges.first, let last = ranges.last {
            let span = self.path.distance(from: first.lowerBound, to: last.upperBound)
            return Match(nameRanges: [], pathRanges: ranges, score: 10_000 + span * 10 + self.path.count)
        }

        return nil
    }
}


enum QuickOpenFileCollector {

    /// The folder names that are skipped when collecting project files.
    static let ignoredFolderNames: Set<String> = [".git", ".svn", ".hg", "node_modules", ".build", "DerivedData", "Pods", ".swiftpm"]

    /// The maximum number of files to collect.
    static let limit = 50_000


    /// Recursively collects the files in the given folder.
    ///
    /// - Parameter rootURL: The project folder.
    /// - Returns: The file items.
    static func collect(in rootURL: URL) async -> [QuickOpenItem] {

        await Task.detached(priority: .userInitiated) {
            let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isAliasFileKey]
            guard let enumerator = FileManager.default.enumerator(at: rootURL, includingPropertiesForKeys: keys,
                                                                  options: [.skipsHiddenFiles, .skipsPackageDescendants])
            else { return [] }

            var items: [QuickOpenItem] = []
            while let url = enumerator.nextObject() as? URL {
                if Task.isCancelled || items.count >= Self.limit { break }

                guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }

                if values.isDirectory == true {
                    if Self.ignoredFolderNames.contains(url.lastPathComponent) {
                        enumerator.skipDescendants()
                    }
                    continue
                }
                guard values.isRegularFile == true || values.isAliasFile == true else { continue }

                items.append(QuickOpenItem(fileURL: url, relativeTo: rootURL))
            }

            return items.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        }.value
    }
}
