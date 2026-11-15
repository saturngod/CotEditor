//
//  QuickOpenView.swift
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

import SwiftUI
import AppKit
import StringUtils
import SyntaxFormat
import SyntaxParsers
import Shortcut
import DocumentFile

struct QuickOpenView: View {

    enum Mode {

        /// Files, symbols (`@`), and commands (`>`).
        case standard
        /// The language (syntax) selector.
        case syntax
    }


    @Observable final class Model {

        var mode: Mode = .standard
        var input: String = ""

        /// Files in the project (or open/recent files).
        var items: [QuickOpenItem] = []
        var recentURLs: [URL] = []
        var isLoading = false

        /// Symbols in the current text document, or `nil` if no symbol information is available.
        var symbols: [OutlineItem]?

        /// Menu commands available in the current context.
        var commands: [ActionCommand] = []
        /// Labels of recently performed commands, newest first.
        var recentCommandLabels: [String] = []

        /// Syntax names available for the language selector.
        var syntaxNames: [String] = []
        /// The syntax name of the current text document.
        var currentSyntaxName: String?

        var width: CGFloat = 600

        var onOpen: (_ item: QuickOpenItem, _ line: FuzzyRange?) -> Void = { _, _ in }
        var onSelectSymbol: (_ symbol: OutlineItem) -> Void = { _ in }
        var onPerformCommand: (_ command: ActionCommand, _ label: String) -> Void = { _, _ in }
        /// Called with the selected syntax name, or `nil` for auto-detection.
        var onSelectSyntax: (_ name: String?) -> Void = { _ in }
        var onCancel: () -> Void = {}
    }


    struct Candidate: Identifiable, Equatable {

        enum Value: Equatable {

            case file(QuickOpenItem)
            case symbol(OutlineItem)
            case command(ActionCommand)
            case syntax(String?)
        }

        var value: Value
        var title: String
        var titleRanges: [Range<String.Index>] = []
        var subtitle: String = ""
        var subtitleRanges: [Range<String.Index>] = []
        var score: Int = 0
        var shortcut: Shortcut?
        var badge: String?

        var id: String {

            switch self.value {
                case .file(let item): item.fileURL.absoluteString
                case .symbol(let item): item.id.uuidString
                case .command(let command): "command:\(command.id.hashValue)"
                case .syntax(let name): name.map { "syntax:\($0)" } ?? "syntax-auto"
            }
        }
    }


    @Bindable var model: Model

    @State private var candidates: [Candidate] = []
    @State private var selection: Candidate.ID?
    @State private var position = ScrollPosition(edge: .top)

    private static let maxCandidates = 200
    private static let symbolPrefix: Character = "@"
    private static let commandPrefix: Character = ">"


    var body: some View {

        VStack(spacing: 0) {
            QuickOpenTextField(
                prompt: self.prompt,
                text: $model.input,
                onMove: self.move(down:),
                onSubmit: self.submit,
                onCancel: self.model.onCancel
            )
            .frame(height: 24)
            .padding(8)

            if !self.candidates.isEmpty {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(self.candidates) { candidate in
                            QuickOpenRow(candidate: candidate, isSelected: candidate.id == self.selection)
                                .id(candidate.id)
                                .onTapGesture {
                                    self.selection = candidate.id
                                    self.submit()
                                }
                                .accessibilityAddTraits(.isButton)
                        }
                    }
                    .padding(.horizontal, 6)
                }
                .scrollPosition($position)
                .contentMargins(.bottom, 6, for: .scrollContent)
                .frame(maxHeight: 360)
                .fixedSize(horizontal: false, vertical: true)

            } else if let message = self.message {
                Text(message)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.quaternary, in: .rect(cornerRadius: 5))
                    .padding(.horizontal, 6)
                    .padding(.bottom, 6)
            }
        }
        .frame(width: self.model.width)
        .background(.regularMaterial, in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
        .onChange(of: self.model.input, initial: true) { self.updateCandidates() }
        .onChange(of: self.model.mode) { self.updateCandidates() }
        .onChange(of: self.model.items) { self.updateCandidates() }
        .onChange(of: self.model.symbols) { self.updateCandidates() }
        .onChange(of: self.selection) { _, newValue in
            self.position.scrollTo(id: newValue)
        }
    }


    // MARK: Private Methods

    private var prompt: String {

        switch self.model.mode {
            case .standard:
                String(localized: "Search files by name (append : to go to line, prefix @ to go to symbol, or > to run a command)",
                       table: "QuickOpen", comment: "placeholder for the Quick Open field")
            case .syntax:
                String(localized: "Select Language Mode", table: "QuickOpen", comment: "placeholder for the language selector")
        }
    }


    private var isSyntaxMode: Bool {

        self.model.mode == .syntax
    }


    private var isSymbolMode: Bool {

        !self.isSyntaxMode && self.model.input.first == Self.symbolPrefix
    }


    private var isCommandMode: Bool {

        !self.isSyntaxMode && self.model.input.first == Self.commandPrefix
    }


    /// The message to show when no candidate is listed.
    private var message: String? {

        if self.isSyntaxMode {
            return String(localized: "No matching languages", table: "QuickOpen", comment: "message when no syntax matched")
        }

        if self.isCommandMode {
            return String(localized: "No matching commands", table: "QuickOpen", comment: "message when no command matched")
        }

        if self.isSymbolMode {
            if self.model.symbols == nil {
                return String(localized: "To go to a symbol, first open a text editor with symbol information.",
                              table: "QuickOpen", comment: "message in Quick Open when no symbol information is available")
            }
            return String(localized: "No matching symbols", table: "QuickOpen", comment: "message when no symbol matched")
        }

        guard !self.model.input.isEmpty, !self.model.isLoading else { return nil }

        return String(localized: "No matching files", table: "QuickOpen", comment: "message when no file matched")
    }


    /// The query part of the input and the line part following `:`.
    private var parsedFileInput: (query: String, line: FuzzyRange?) {

        let input = self.model.input
        guard let colon = input.firstIndex(of: ":") else { return (input, nil) }

        let query = String(input[..<colon])
        let lineString = input[input.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        let line = try? FuzzyRange.FormatStyle().parseStrategy.parse(lineString)

        return (query, line)
    }


    private func updateCandidates() {

        self.candidates = if self.isSyntaxMode {
            self.syntaxCandidates()
        } else if self.isCommandMode {
            self.commandCandidates()
        } else if self.isSymbolMode {
            self.symbolCandidates()
        } else {
            self.fileCandidates()
        }
        self.selection = self.candidates.first?.id
    }


    private func fileCandidates() -> [Candidate] {

        let query = QuickOpenItem.Query(self.parsedFileInput.query)
        let items = self.model.items
        let limit = Self.maxCandidates

        if query.isEmpty {
            // show recently used files first, then the rest
            let recents = self.model.recentURLs
            let recentSet = Set(recents)
            var recentItems: [URL: QuickOpenItem] = [:]
            var rest: [QuickOpenItem] = []

            for item in items {
                if recentSet.contains(item.fileURL) {
                    if recentItems[item.fileURL] == nil {
                        recentItems[item.fileURL] = item
                    }
                } else if rest.count < limit {
                    rest.append(item)
                }
                if rest.count >= limit, recentItems.count == recentSet.count { break }
            }

            return (recents.compactMap { recentItems[$0] } + rest)
                .prefix(limit)
                .map { Candidate(value: .file($0), title: $0.name, subtitle: $0.parentPath) }
        }

        // keep only the best matches while scanning to avoid building and sorting candidates for all files
        typealias Entry = (score: Int, index: Int, match: QuickOpenItem.Match)
        let isOrdered: (Entry, Entry) -> Bool = { ($0.score, $0.index) < ($1.score, $1.index) }
        var entries: [Entry] = []
        entries.reserveCapacity(limit * 2)
        var threshold = Int.max  // scores not smaller than this can no longer be in the result

        for (index, item) in items.enumerated() {
            guard let match = item.match(query), match.score < threshold else { continue }

            entries.append((match.score, index, match))

            if entries.count >= limit * 2 {
                entries.sort(by: isOrdered)
                entries.removeSubrange(limit...)
                threshold = entries[limit - 1].score
            }
        }
        entries.sort(by: isOrdered)

        return entries.prefix(limit).map { entry in
            let item = items[entry.index]
            let parentPath = item.parentPath

            return Candidate(value: .file(item), title: item.name, titleRanges: entry.match.nameRanges,
                             subtitle: parentPath,
                             subtitleRanges: entry.match.pathRanges.filter { $0.upperBound <= parentPath.endIndex },
                             score: entry.score)
        }
    }


    private func symbolCandidates() -> [Candidate] {

        guard let symbols = self.model.symbols else { return [] }

        let query = self.model.input.dropFirst().filter { !$0.isWhitespace }

        let candidates = symbols.enumerated().compactMap { offset, symbol -> Candidate? in
            let title = symbol.title.trimmingCharacters(in: .whitespaces)
            let subtitle = symbol.kind.map { String(localized: $0.label) } ?? ""

            if query.isEmpty {
                return Candidate(value: .symbol(symbol), title: title, subtitle: subtitle, score: offset)
            }

            guard
                let ranges = title.abbreviatedMatchedRanges(with: String(query)),
                let first = ranges.first, let last = ranges.last
            else { return nil }

            var score = title.distance(from: first.lowerBound, to: last.upperBound) * 10
            if first.lowerBound == title.startIndex { score -= 500 }

            return Candidate(value: .symbol(symbol), title: title, titleRanges: ranges, subtitle: subtitle,
                             score: score * symbols.count + offset)  // keep document order for ties
        }

        return query.isEmpty ? candidates : candidates.sorted { $0.score < $1.score }
    }


    private func commandCandidates() -> [Candidate] {

        let query = self.model.input.dropFirst().trimmingCharacters(in: .whitespaces)
        let recents = self.model.recentCommandLabels
        let recentlyUsed = String(localized: "recently used", table: "QuickOpen", comment: "badge for recently used commands")

        let candidates = self.model.commands.enumerated().compactMap { offset, command -> Candidate? in
            let label = command.label
            let recentIndex = recents.firstIndex(of: label)

            var candidate = Candidate(value: .command(command), title: label, shortcut: command.shortcut,
                                      badge: (recentIndex != nil) ? recentlyUsed : nil)

            if query.isEmpty {
                candidate.score = recentIndex.map { $0 - recents.count } ?? offset
                return candidate
            }

            guard
                let ranges = label.abbreviatedMatchedRanges(with: query),
                let first = ranges.first, let last = ranges.last
            else { return nil }

            var score = label.distance(from: first.lowerBound, to: last.upperBound) * 10
            // prefer matches in the command title rather than in the menu path
            if let titleStart = label.range(of: command.title, options: .backwards)?.lowerBound, first.lowerBound >= titleStart {
                score -= 300
                if first.lowerBound == titleStart { score -= 300 }
            }
            if recentIndex != nil { score -= 200 }

            candidate.titleRanges = ranges
            candidate.score = score * self.model.commands.count + offset  // keep menu order for ties
            return candidate
        }

        return candidates.sorted { $0.score < $1.score }
    }


    private func syntaxCandidates() -> [Candidate] {

        let query = self.model.input.filter { !$0.isWhitespace }
        let current = String(localized: "current", table: "QuickOpen", comment: "badge for the syntax currently used in the document")

        let autoDetect = Candidate(value: .syntax(nil),
                                   title: String(localized: "Auto Detect", table: "QuickOpen", comment: "item to detect the syntax automatically"))
        let none = Candidate(value: .syntax(SyntaxName.none),
                             title: String(localized: "SyntaxName.none", defaultValue: "None"))
        let all = [autoDetect, none] + self.model.syntaxNames.map { Candidate(value: .syntax($0), title: $0) }

        let candidates = all.enumerated().compactMap { offset, candidate -> Candidate? in
            var candidate = candidate
            if case .syntax(let name?) = candidate.value, name == self.model.currentSyntaxName {
                candidate.badge = current
            }

            if query.isEmpty {
                candidate.score = offset
                return candidate
            }

            guard
                let ranges = candidate.title.abbreviatedMatchedRanges(with: query),
                let first = ranges.first, let last = ranges.last
            else { return nil }

            var score = candidate.title.distance(from: first.lowerBound, to: last.upperBound) * 10 + candidate.title.count
            if first.lowerBound == candidate.title.startIndex { score -= 500 }

            candidate.titleRanges = ranges
            candidate.score = score * all.count + offset  // keep list order for ties
            return candidate
        }

        return query.isEmpty ? candidates : candidates.sorted { $0.score < $1.score }
    }


    private func move(down: Bool) {

        guard !self.candidates.isEmpty else { return }

        let index = self.candidates.firstIndex { $0.id == self.selection } ?? -1
        let newIndex = min(max(index + (down ? 1 : -1), 0), self.candidates.count - 1)
        self.selection = self.candidates[newIndex].id
    }


    private func submit() {

        guard let candidate = self.candidates.first(where: { $0.id == self.selection }) else {
            return NSSound.beep()
        }

        switch candidate.value {
            case .file(let item):
                self.model.onOpen(item, self.parsedFileInput.line)
            case .symbol(let symbol):
                self.model.onSelectSymbol(symbol)
            case .command(let command):
                self.model.onPerformCommand(command, candidate.title)
            case .syntax(let name):
                self.model.onSelectSyntax(name)
        }
    }
}


extension ActionCommand {

    /// The VS Code-like label, such as “Format: Theme: Dracula”.
    var label: String {

        (self.paths + [self.title]).joined(separator: ": ")
    }
}


private extension QuickOpenItem {

    /// The parent directory part of the relative path.
    var parentPath: String {

        guard let slash = self.path.lastIndex(of: "/") else { return "" }
        return String(self.path[..<slash])
    }
}


private struct QuickOpenRow: View {

    var candidate: QuickOpenView.Candidate
    var isSelected: Bool


    var body: some View {

        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if self.hasIcon {
                self.icon
                    .frame(width: 16, height: 16)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 }
            }

            Text(self.highlighted(self.candidate.title, ranges: self.candidate.titleRanges))
                .layoutPriority(1)

            Text(self.highlighted(self.candidate.subtitle, ranges: self.candidate.subtitleRanges))
                .font(.callout)
                .foregroundStyle(self.isSelected ? Color(nsColor: .selectedMenuItemTextColor).opacity(0.8) : .secondary)
                .truncationMode(.head)

            if !self.hasIcon {
                Spacer(minLength: 8)

                if let shortcut = self.candidate.shortcut {
                    ShortcutView(shortcut)
                        .foregroundStyle(self.isSelected ? Color(nsColor: .selectedMenuItemTextColor) : .secondary)
                        .layoutPriority(2)
                }

                if let badge = self.candidate.badge {
                    Text(badge)
                        .font(.callout)
                        .foregroundStyle(self.isSelected ? Color(nsColor: .selectedMenuItemTextColor).opacity(0.8) : .secondary)
                        .layoutPriority(2)
                }
            }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .contentShape(.rect)
        .foregroundStyle(self.isSelected ? Color(nsColor: .selectedMenuItemTextColor) : .primary)
        .background(self.isSelected ? Color.accentColor : .clear, in: .rect(cornerRadius: 5))
        .accessibilityElement(children: .combine)
    }


    private var hasIcon: Bool {

        switch self.candidate.value {
            case .file, .symbol: true
            case .command, .syntax: false
        }
    }


    @ViewBuilder private var icon: some View {

        switch self.candidate.value {
            case .file(let item):
                Image(systemName: File.Kind(pathExtension: item.fileURL.pathExtension, isDirectory: false).symbolName)
                    .foregroundStyle(self.isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            case .symbol(let symbol):
                if let kind = symbol.kind {
                    kind.icon()
                } else {
                    Image(systemName: "number")
                        .foregroundStyle(.secondary)
                }
            case .command, .syntax:
                EmptyView()
        }
    }


    private func highlighted(_ string: String, ranges: [Range<String.Index>]) -> AttributedString {

        let attributed = AttributedString(string)

        return ranges
            .compactMap { Range($0, in: attributed) }
            .reduce(into: attributed) { string, range in
                string[range].font = .body.weight(.bold)
                if !self.isSelected {
                    string[range].foregroundColor = .accentColor
                }
            }
    }
}


/// A text field that forwards arrow keys, return and escape.
private struct QuickOpenTextField: NSViewRepresentable {

    var prompt: String
    @Binding var text: String
    var onMove: (_ down: Bool) -> Void
    var onSubmit: () -> Void
    var onCancel: () -> Void


    func makeNSView(context: Context) -> NSTextField {

        let textField = NSTextField(string: self.text)
        textField.usesSingleLineMode = true
        textField.placeholderString = self.prompt
        textField.delegate = context.coordinator
        textField.bezelStyle = .roundedBezel
        textField.font = .systemFont(ofSize: NSFont.systemFontSize + 1)
        textField.focusRingType = .default
        textField.setAccessibilitySubrole(.searchField)

        return textField
    }


    func updateNSView(_ nsView: NSTextField, context: Context) {

        context.coordinator.parent = self

        if nsView.placeholderString != self.prompt {
            nsView.placeholderString = self.prompt
        }

        if nsView.stringValue != self.text {
            nsView.stringValue = self.text
            // place the cursor at the end (e.g., after the prefilled "@")
            nsView.currentEditor()?.selectedRange = NSRange(location: (self.text as NSString).length, length: 0)
        }
    }


    func makeCoordinator() -> Coordinator {

        Coordinator(parent: self)
    }


    final class Coordinator: NSObject, NSTextFieldDelegate {

        var parent: QuickOpenTextField


        init(parent: QuickOpenTextField) {

            self.parent = parent
        }


        func controlTextDidChange(_ obj: Notification) {

            guard let textField = obj.object as? NSTextField else { return }

            self.parent.text = textField.stringValue
        }


        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {

            switch commandSelector {
                case #selector(NSResponder.moveUp(_:)):
                    self.parent.onMove(false)
                case #selector(NSResponder.moveDown(_:)):
                    self.parent.onMove(true)
                case #selector(NSResponder.insertNewline(_:)):
                    self.parent.onSubmit()
                case #selector(NSResponder.cancelOperation(_:)):
                    self.parent.onCancel()
                default:
                    return false
            }
            return true
        }
    }
}
