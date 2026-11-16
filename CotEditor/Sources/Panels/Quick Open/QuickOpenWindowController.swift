//
//  QuickOpenWindowController.swift
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

import AppKit
import Defaults
import SwiftUI
import StringUtils
import SyntaxParsers
import URLUtils

/// The VS Code-like Quick Open bar that appears at the top of the document window.
final class QuickOpenWindowController: NSWindowController {

    // MARK: Public Properties

    static let shared = QuickOpenWindowController()


    // MARK: Private Properties

    private let model = QuickOpenView.Model()
    private weak var directoryDocument: DirectoryDocument?
    private weak var parentWindow: NSWindow?
    private weak var textDocument: TextDocument?
    private var loadTask: Task<Void, Never>?

    /// Cache of the collected project files keyed by the project folder.
    private var cache: (rootURL: URL, items: [QuickOpenItem])?


    // MARK: Lifecycle

    init() {

        let panel = QuickOpenPanel(contentRect: .zero, styleMask: [.borderless, .fullSizeContentView], backing: .buffered, defer: false)
        let hostingView = QuickOpenHostingView(rootView: QuickOpenView(model: self.model))
        hostingView.sizingOptions = [.intrinsicContentSize]
        hostingView.safeAreaRegions = []

        panel.contentView = hostingView
        panel.title = String(localized: "Quick Open", table: "QuickOpen", comment: "window title (for VoiceOver)")
        panel.animationBehavior = .none
        panel.collectionBehavior.insert(.fullScreenAuxiliary)
        panel.isFloatingPanel = true
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear

        super.init(window: panel)

        self.model.onOpen = { [unowned self] item, line in self.open(item, line: line) }
        self.model.onSelectSymbol = { [unowned self] symbol in self.select(symbol) }
        self.model.onPerformCommand = { [unowned self] command, label in self.perform(command, label: label) }
        self.model.onSelectSyntax = { [unowned self] name in self.selectSyntax(name: name) }
        self.model.onCancel = { [unowned self] in self.close() }
    }


    @available(*, unavailable)
    required init?(coder: NSCoder) {

        fatalError("init(coder:) has not been implemented")
    }


    // MARK: Window Controller Methods

    override func showWindow(_ sender: Any?) {

        self.show(input: "", sender: sender)
    }


    override func close() {

        self.loadTask?.cancel()

        super.close()
    }


    // MARK: Public Methods

    /// The current input in the field.
    var input: String {

        self.model.input
    }


    /// Whether the bar is currently in the language selector mode.
    var isSyntaxMode: Bool {

        self.model.mode == .syntax
    }


    /// Shows the language selector to change the syntax of the current text document.
    ///
    /// - Parameter sender: The sender of the action.
    func showSyntaxSelector(sender: Any? = nil) {

        self.show(input: "", mode: .syntax, sender: sender)

        if self.textDocument == nil {
            self.close()
            NSSound.beep()
        }
    }


    /// Shows the Quick Open bar with the given initial input.
    ///
    /// - Parameters:
    ///   - input: The initial input, such as `"@"` to go to a symbol.
    ///   - mode: The mode of the bar.
    ///   - sender: The sender of the action.
    func show(input: String, mode: QuickOpenView.Mode = .standard, sender: Any? = nil) {

        if self.window?.isVisible == true {
            self.enter(mode: mode, input: input)
            return
        }

        self.parentWindow = NSApp.mainWindow
        let document = self.parentWindow?.windowController?.document
        self.directoryDocument = document as? DirectoryDocument
        self.textDocument = (document as? TextDocument) ?? (self.directoryDocument?.currentDocument as? TextDocument)

        self.enter(mode: mode, input: input)
        self.model.symbols = self.textDocument?.syntaxController.outlineItems?.filter { !$0.isSeparator }
        // -> Collect commands before the panel becomes key so that menu validation targets the document window.
        self.model.commands = NSApp.actionCommands.filter { !Self.excludedActions.contains($0.action) }
        if self.textDocument != nil {
            self.model.commands.append(Self.changeSyntaxCommand)
        }
        self.model.recentCommandLabels = UserDefaults.standard.stringArray(forKey: Self.recentCommandsKey) ?? []
        self.loadItems()
        self.reposition()

        super.showWindow(sender)
    }


    // MARK: Private Methods

    /// The command to switch the bar to the language selector.
    private static let changeSyntaxCommand = ActionCommand(
        id: ObjectIdentifier(QuickOpenWindowController.self),
        kind: .command,
        title: String(localized: "Change Language Mode", table: "QuickOpen", comment: "command to show the language selector"),
        action: #selector(AppDelegate.showLanguageSelector))


    /// Switches the mode of the bar.
    private func enter(mode: QuickOpenView.Mode, input: String) {

        if mode == .syntax {
            self.model.syntaxNames = SyntaxManager.shared.settingNames
            self.model.currentSyntaxName = self.textDocument?.syntaxName
        }
        self.model.mode = mode
        self.model.input = input
    }


    /// Changes the syntax of the current text document.
    ///
    /// - Parameter name: The syntax name, or `nil` to detect the syntax from the filename and the content.
    private func selectSyntax(name: String?) {

        let textDocument = self.textDocument

        self.close()
        self.parentWindow?.makeKeyAndOrderFront(nil)

        guard let textDocument else { return NSSound.beep() }

        let name = name
            ?? SyntaxManager.shared.settingName(documentName: textDocument.fileURL?.lastPathComponent ?? textDocument.displayName,
                                                content: textDocument.textStorage.string)
            ?? SyntaxName.none

        textDocument.setSyntax(name: name)
    }


    /// Collects the candidate files.
    private func loadItems() {

        let openURLs = NSDocumentController.shared.documents.compactMap(\.fileURL)
        let recentURLs = NSDocumentController.shared.recentDocumentURLs

        guard let rootURL = self.directoryDocument?.fileURL else {
            // not in a folder: offer open and recent documents
            let urls = (openURLs + recentURLs).uniqued.filter { (try? $0.checkResourceIsReachable()) == true }
            self.model.items = urls.map { QuickOpenItem(fileURL: $0, relativeTo: nil) }
            self.model.recentURLs = urls
            self.model.isLoading = false
            return
        }

        var recents: [URL] = []
        if let current = self.directoryDocument?.currentDocument?.fileURL {
            recents.append(current)
        }
        recents += (openURLs + recentURLs).filter { rootURL.isAncestor(of: $0) }
        self.model.recentURLs = recents.uniqued

        let includesGitIgnoredFiles = UserDefaults.standard[.folderFindIncludesGitIgnoredFiles]

        if let cache = self.cache, cache.rootURL == rootURL {
            self.model.items = cache.items
        } else {
            self.model.items = []
        }

        // (re)scan the folder in the background to pick up file changes
        self.model.isLoading = true
        self.loadTask?.cancel()
        self.loadTask = Task { [weak self] in
            let items = await QuickOpenFileCollector.collect(in: rootURL, includesGitIgnoredFiles: includesGitIgnoredFiles)
            guard !Task.isCancelled, let self else { return }

            self.cache = (rootURL, items)
            if self.directoryDocument?.fileURL == rootURL, self.model.items != items {
                self.model.items = items
            }
            self.model.isLoading = false
        }
    }


    /// Places the panel at the top center of the parent window, just below the toolbar.
    private func reposition() {

        guard let panel = self.window as? QuickOpenPanel, let contentView = panel.contentView else { return }

        let anchorFrame: NSRect
        let top: CGFloat
        if let parent = self.parentWindow {
            anchorFrame = parent.frame
            top = parent.frame.minY + parent.contentLayoutRect.maxY - 6
        } else {
            anchorFrame = NSScreen.main?.visibleFrame ?? .zero
            top = anchorFrame.maxY - anchorFrame.height / 5
        }

        let width = max(min(640, anchorFrame.width - 40), 320)
        if self.model.width != width {
            self.model.width = width
        }

        contentView.layoutSubtreeIfNeeded()
        let size = contentView.fittingSize
        let origin = NSPoint(x: (anchorFrame.midX - size.width / 2).rounded(), y: top.rounded() - size.height)
        let frame = NSRect(origin: origin, size: size)
        panel.anchoredTop = top.rounded()

        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
    }


    private static let recentCommandsKey = "QuickOpenRecentCommands"
    private static let maxRecentCommands = 10
    private static let excludedActions: [Selector] = [
        #selector(AppDelegate.showQuickOpen),
        #selector(AppDelegate.showGoToSymbol),
        #selector(AppDelegate.showCommandPalette),
        #selector(AppDelegate.showLanguageSelector),
    ]


    /// Performs the selected menu command in the document window.
    private func perform(_ command: ActionCommand, label: String) {

        var recents = UserDefaults.standard.stringArray(forKey: Self.recentCommandsKey) ?? []
        recents.removeAll { $0 == label }
        recents.insert(label, at: 0)
        UserDefaults.standard.set(Array(recents.prefix(Self.maxRecentCommands)), forKey: Self.recentCommandsKey)

        // switch to the language selector in place
        if command.id == Self.changeSyntaxCommand.id {
            self.enter(mode: .syntax, input: "")
            return
        }

        // close first so that the action is delivered to the document window's responder chain
        self.close()
        self.parentWindow?.makeKeyAndOrderFront(nil)

        if !command.perform() {
            NSSound.beep()
        }
    }


    /// Jumps to the selected symbol in the current text document.
    private func select(_ symbol: OutlineItem) {

        let textDocument = self.textDocument

        self.close()
        self.parentWindow?.makeKeyAndOrderFront(nil)

        guard
            let textView = textDocument?.textView,
            textView.string.length >= symbol.range.upperBound
        else { return NSSound.beep() }

        textView.window?.makeFirstResponder(textView)
        textView.selectedRange = symbol.range
        textView.centerSelectionInVisibleArea(nil)
    }


    /// Opens the selected file.
    private func open(_ item: QuickOpenItem, line: FuzzyRange?) {

        let directoryDocument = self.directoryDocument
        let parentWindow = self.parentWindow

        self.close()
        parentWindow?.makeKeyAndOrderFront(nil)

        Task {
            let textDocument: TextDocument?

            if let directoryDocument, let rootURL = directoryDocument.fileURL, rootURL.isAncestor(of: item.fileURL) {
                guard await directoryDocument.openDocument(at: item.fileURL, prefersOriginal: true) else { return }
                directoryDocument.fileBrowserViewController?.selectCurrentDocument()
                textDocument = directoryDocument.currentDocument as? TextDocument

            } else {
                do {
                    let (document, _) = try await NSDocumentController.shared.openDocument(withContentsOf: item.fileURL, display: true)
                    textDocument = document as? TextDocument
                } catch {
                    NSApp.presentError(error)
                    return
                }
            }

            guard let line, let textDocument else { return }

            // wait for the text view to be ready
            for _ in 0..<20 {
                if let textView = textDocument.textView {
                    guard let range = textView.string.rangeForLine(in: line) else { return NSSound.beep() }
                    textView.window?.makeFirstResponder(textView)
                    textView.select(range: range)
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }
}


// MARK: - Private Classes

private final class QuickOpenHostingView: NSHostingView<QuickOpenView> {

    override func invalidateIntrinsicContentSize() {

        super.invalidateIntrinsicContentSize()

        // fit the panel to the content explicitly, keeping its top edge (anchored in `QuickOpenPanel.setFrame(_:display:)`)
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window, window.isVisible else { return }

            let size = self.intrinsicContentSize
            guard size.height > 0, size.height != window.frame.height else { return }

            var frame = window.frame
            frame.size.height = size.height
            window.setFrame(frame, display: true)
        }
    }
}


private final class QuickOpenPanel: NSPanel {

    override var canBecomeKey: Bool  { true }


    /// The screen position of the top edge to keep while the panel is resized to fit the result list.
    var anchoredTop: CGFloat?

    private var resizeObserver: (any NSObjectProtocol)?


    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {

        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)

        // -> The hosting view doesn't always resize the window through `setFrame(_:display:)`.
        self.resizeObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: self, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let top = self.anchoredTop, self.frame.maxY != top else { return }
                self.setFrameOrigin(NSPoint(x: self.frame.minX, y: top - self.frame.height))
            }
        }
    }


    override func setFrame(_ frameRect: NSRect, display flag: Bool) {

        // keep the top edge anchored when the hosting view resizes the panel to fit the result list
        var frame = frameRect
        if let top = self.anchoredTop {
            frame.origin.y = top - frame.height
        }

        super.setFrame(frame, display: flag)
    }


    override func cancelOperation(_ sender: Any?) {

        self.close()
    }


    override func resignKey() {

        super.resignKey()

        self.close()
    }
}
