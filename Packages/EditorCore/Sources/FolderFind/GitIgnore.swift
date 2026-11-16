//
//  GitIgnore.swift
//  FolderFind
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

public import Foundation

/// A matcher for the `.gitignore` rules collected in a folder tree.
///
/// Rules are evaluated in the order they were added and the last matching rule wins,
/// so rules from deeper `.gitignore` files should be added after those of their parents.
public struct GitIgnore: Sendable {

    fileprivate struct Rule: @unchecked Sendable {

        /// The folder path the rule file is in, relative to the root, with a trailing slash (or empty for the root).
        var base: String
        var regex: NSRegularExpression
        var isNegated: Bool
        var isDirectoryOnly: Bool
        /// Whether the pattern is matched against the whole path relative to `base` instead of the file name.
        var isAnchored: Bool
    }


    private var rules: [Rule] = []
    
    
    public init() { }

    public var isEmpty: Bool  { self.rules.isEmpty }


    /// Adds the rules in the contents of a `.gitignore` file.
    ///
    /// - Parameters:
    ///   - contents: The file contents.
    ///   - base: The path of the folder containing the file, relative to the root (empty for the root).
    public mutating func add(contents: String, base: String = "") {

        let base = (base.isEmpty || base.hasSuffix("/")) ? base : base + "/"

        for line in contents.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline) {
            if let rule = Self.rule(line: String(line), base: base) {
                self.rules.append(rule)
            }
        }
    }


    /// Loads the `.gitignore` file in the given folder, if any.
    ///
    /// - Parameters:
    ///   - folderURL: The folder to look in.
    ///   - base: The path of the folder relative to the root (empty for the root).
    public mutating func load(in folderURL: URL, base: String = "") {

        let fileURL = folderURL.appending(component: ".gitignore", directoryHint: .notDirectory)

        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { return }

        self.add(contents: contents, base: base)
    }


    /// Loads `.git/info/exclude` and the `.gitignore` file in the given root folder, if any.
    ///
    /// - Parameter rootURL: The root folder.
    public mutating func loadRoot(_ rootURL: URL) {
        
        let excludeURL = rootURL.appending(path: ".git/info/exclude", directoryHint: .notDirectory)
        if let contents = try? String(contentsOf: excludeURL, encoding: .utf8) {
            self.add(contents: contents)
        }
        self.load(in: rootURL)
    }
    
    
    /// Returns whether the given path is ignored.
    ///
    /// The parent folders of the path are not checked; callers are expected to skip ignored folders' contents.
    ///
    /// - Parameters:
    ///   - path: The path relative to the root without a leading slash.
    ///   - isDirectory: Whether the path is a folder.
    public func isIgnored(_ path: String, isDirectory: Bool) -> Bool {

        let name = path.split(separator: "/").last.map(String.init) ?? path

        for rule in self.rules.reversed() {
            guard !rule.isDirectoryOnly || isDirectory else { continue }
            guard path.hasPrefix(rule.base), path.count > rule.base.count else { continue }

            let target = rule.isAnchored ? String(path.dropFirst(rule.base.count)) : name
            let range = NSRange(target.startIndex..., in: target)

            if rule.regex.firstMatch(in: target, range: range) != nil {
                return !rule.isNegated
            }
        }

        return false
    }
}


private extension GitIgnore {

    static func rule(line: String, base: String) -> Rule? {

        var pattern = Substring(line)

        // comment
        if pattern.hasPrefix("#") { return nil }

        // trailing spaces are ignored unless escaped with a backslash
        while pattern.hasSuffix(" "), !pattern.hasSuffix("\\ ") {
            pattern = pattern.dropLast()
        }

        var isNegated = false
        if pattern.hasPrefix("!") {
            isNegated = true
            pattern = pattern.dropFirst()
        } else if pattern.hasPrefix("\\!") || pattern.hasPrefix("\\#") {
            pattern = pattern.dropFirst()
        }

        var isDirectoryOnly = false
        if pattern.hasSuffix("/") {
            isDirectoryOnly = true
            pattern = pattern.dropLast()
        }

        // a separator at the beginning or middle anchors the pattern to the base folder
        let isAnchored = pattern.contains("/")
        if pattern.hasPrefix("/") {
            pattern = pattern.dropFirst()
        }

        guard !pattern.isEmpty,
              let regex = try? NSRegularExpression(pattern: "^" + self.regexPattern(glob: pattern) + "$")
        else { return nil }

        return Rule(base: base, regex: regex, isNegated: isNegated, isDirectoryOnly: isDirectoryOnly, isAnchored: isAnchored)
    }


    /// Converts a gitignore glob into a regular expression pattern.
    static func regexPattern(glob: Substring) -> String {

        let chars = Array(glob)
        var regex = ""
        var index = 0

        while index < chars.count {
            let char = chars[index]

            switch char {
                case "*" where index + 1 < chars.count && chars[index + 1] == "*":
                    let isSegmentStart = (index == 0 || chars[index - 1] == "/")
                    let next = index + 2
                    if isSegmentStart, next == chars.count {
                        // trailing `**`: everything inside
                        regex += ".*"
                        index = next
                    } else if isSegmentStart, chars[next] == "/" {
                        // `**/`: zero or more folders
                        regex += "(?:.*/)?"
                        index = next + 1
                    } else {
                        // consecutive asterisks elsewhere act like a regular `*`
                        regex += "[^/]*"
                        index = next
                    }
                    continue

                case "*":
                    regex += "[^/]*"

                case "?":
                    regex += "[^/]"

                case "[":
                    if let end = chars[(index + 1)...].firstIndex(of: "]"), end > index + 1 {
                        var body = String(chars[(index + 1)..<end])
                        if body.hasPrefix("!") { body = "^" + body.dropFirst() }
                        body = body.replacing("\\", with: "\\\\")
                        regex += "[" + body + "]"
                        index = end + 1
                        continue
                    }
                    regex += "\\["

                case "\\" where index + 1 < chars.count:
                    regex += NSRegularExpression.escapedPattern(for: String(chars[index + 1]))
                    index += 2
                    continue

                default:
                    regex += NSRegularExpression.escapedPattern(for: String(char))
            }
            index += 1
        }

        return regex
    }
}
