//
//  TerminalPanelViewController.swift
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

/// A view controller that manages multiple terminal sessions with a header bar and a session list.
final class TerminalPanelViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {

    // MARK: Public Properties

    /// The colors to apply to the terminals.
    var palette: TerminalPalette  { didSet { if palette != oldValue { self.applyPalette() } } }

    /// The handler invoked when the last terminal session has been closed.
    var closeHandler: (@MainActor () -> Void)?


    // MARK: Private Properties

    private static let headerHeight: CGFloat = 28
    private static let listWidth: CGFloat = 150

    private var sessions: [TerminalViewController] = []
    private var selectedIndex: Int?

    @ViewLoading private var sessionContainerView: NSView
    @ViewLoading private var listContainerView: NSView
    @ViewLoading private var listWidthConstraint: NSLayoutConstraint
    @ViewLoading private var tableView: NSTableView


    // MARK: Lifecycle

    /// Creates a terminal panel without sessions.
    ///
    /// - Parameter palette: The colors to apply to the terminals.
    init(palette: TerminalPalette) {

        self.palette = palette

        super.init(nibName: nil, bundle: nil)
    }


    @available(*, unavailable)
    required init?(coder: NSCoder) {

        fatalError("init(coder:) has not been implemented")
    }


    override func loadView() {

        // header
        let titleLabel = NSTextField(labelWithString: String(localized: "Terminal", table: "Document", comment: "title of the terminal pane"))
        titleLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor

        let newButton = Self.makeButton(symbolName: "plus", action: Selector(("newTerminal:")), target: nil,
                                        label: String(localized: "New Terminal", table: "Document", comment: "button label"))
        let killButton = Self.makeButton(symbolName: "trash", action: #selector(closeSelectedSession), target: self,
                                         label: String(localized: "Kill Terminal", table: "Document", comment: "button label"))
        let hideButton = Self.makeButton(symbolName: "xmark", action: Selector(("toggleTerminal:")), target: nil,
                                         label: String(localized: "Hide Terminal", table: "Document", comment: "button label"))

        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let headerView = NSStackView(views: [titleLabel, spacer, newButton, killButton, hideButton])
        headerView.orientation = .horizontal
        headerView.spacing = 10
        headerView.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)

        let topSeparator = Self.makeSeparator()
        let headerSeparator = Self.makeSeparator()
        let listSeparator = Self.makeSeparator()

        // session list
        let tableView = NSTableView()
        tableView.addTableColumn(NSTableColumn(identifier: .init("session")))
        tableView.headerView = nil
        tableView.style = .sourceList
        tableView.backgroundColor = .clear
        tableView.rowHeight = 22
        tableView.allowsEmptySelection = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.setAccessibilityLabel(String(localized: "Terminals", table: "Document", comment: "accessibility label"))
        let menu = NSMenu()
        menu.addItem(withTitle: String(localized: "Kill Terminal", table: "Document", comment: "button label"),
                     action: #selector(closeClickedSession), keyEquivalent: "").target = self
        tableView.menu = menu
        self.tableView = tableView

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false

        let listContainerView = NSView()
        listContainerView.addSubview(listSeparator)
        listContainerView.addSubview(scrollView)
        listContainerView.isHidden = true
        self.listContainerView = listContainerView

        let sessionContainerView = NSView()
        self.sessionContainerView = sessionContainerView

        // -> Fill the area under the status bar with the terminal background.
        let view = TerminalBackgroundView()
        for subview in [topSeparator, headerView, headerSeparator, sessionContainerView, listContainerView, listSeparator, scrollView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
        }
        for subview in [topSeparator, headerView, headerSeparator, sessionContainerView, listContainerView] {
            view.addSubview(subview)
        }

        // -> Don't read `@ViewLoading` properties here; that re-enters `loadView()` before the view is set.
        let listWidthConstraint = listContainerView.widthAnchor.constraint(equalToConstant: 0)
        self.listWidthConstraint = listWidthConstraint

        // -> The list collapses to zero width, which is narrower than its separator,
        //    so let the scroll view give way instead of conflicting with the separator.
        let scrollViewTrailingConstraint = scrollView.trailingAnchor.constraint(equalTo: listContainerView.trailingAnchor)
        scrollViewTrailingConstraint.priority = .required - 1

        // -> The split view lays the pane out with zero size when adding or collapsing it,
        //    which is smaller than the header, so let the header's trailing edge
        //    and the content under the header give way.
        let headerTrailingConstraint = headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        headerTrailingConstraint.priority = .required - 1
        let bottomConstraints = [
            sessionContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            listContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.bottomAnchor.constraint(equalTo: listContainerView.safeAreaLayoutGuide.bottomAnchor),
        ]
        for constraint in bottomConstraints {
            constraint.priority = .required - 1
        }

        NSLayoutConstraint.activate(bottomConstraints + [
            topSeparator.topAnchor.constraint(equalTo: view.topAnchor),
            topSeparator.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topSeparator.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            headerView.topAnchor.constraint(equalTo: topSeparator.bottomAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerTrailingConstraint,
            headerView.heightAnchor.constraint(equalToConstant: Self.headerHeight),

            headerSeparator.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            headerSeparator.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerSeparator.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            sessionContainerView.topAnchor.constraint(equalTo: headerSeparator.bottomAnchor),
            sessionContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sessionContainerView.trailingAnchor.constraint(equalTo: listContainerView.leadingAnchor),

            listContainerView.topAnchor.constraint(equalTo: headerSeparator.bottomAnchor),
            listContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            listWidthConstraint,

            listSeparator.leadingAnchor.constraint(equalTo: listContainerView.leadingAnchor),
            listSeparator.topAnchor.constraint(equalTo: listContainerView.topAnchor),
            listSeparator.bottomAnchor.constraint(equalTo: listContainerView.bottomAnchor),
            listSeparator.widthAnchor.constraint(equalToConstant: 1),

            scrollView.leadingAnchor.constraint(equalTo: listSeparator.trailingAnchor),
            scrollViewTrailingConstraint,
            scrollView.topAnchor.constraint(equalTo: listContainerView.topAnchor, constant: 4),
        ])

        self.view = view
        self.view.setAccessibilityElement(true)
        self.view.setAccessibilityRole(.group)
        self.view.setAccessibilityLabel(String(localized: "Terminal", table: "Document", comment: "title of the terminal pane"))

        self.applyPalette()
    }


    // MARK: Public Methods

    /// Whether one of the terminals currently has the keyboard focus.
    var hasFocus: Bool {

        guard
            self.isViewLoaded,
            let responder = self.view.window?.firstResponder as? NSView
        else { return false }

        return responder.isDescendant(of: self.view)
    }


    /// Whether the panel has no terminal sessions.
    var isEmpty: Bool {

        self.sessions.isEmpty
    }


    /// Moves the keyboard focus to the selected terminal.
    func focus() {

        guard let selectedIndex else { return }

        self.sessions[selectedIndex].focus()
    }


    /// Creates a new terminal session and selects it.
    ///
    /// - Parameter workingDirectory: The directory where the shell starts, or `nil` to start in the home directory.
    func addSession(workingDirectory: URL?) {

        _ = self.view  // load view

        let session = TerminalViewController(workingDirectory: workingDirectory, palette: self.palette)
        session.terminationHandler = { [weak self, unowned session] in self?.close(session: session) }
        session.titleHandler = { [weak self, unowned session] in self?.reloadTitle(of: session) }

        self.addChild(session)
        self.sessions.append(session)
        self.tableView.reloadData()
        self.invalidateListVisibility()
        self.select(index: self.sessions.count - 1)
    }


    // MARK: Table View Data Source

    func numberOfRows(in tableView: NSTableView) -> Int {

        self.sessions.count
    }


    // MARK: Table View Delegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {

        let identifier = NSUserInterfaceItemIdentifier("TerminalSessionCell")
        let cellView: NSTableCellView
        if let view = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
            cellView = view
        } else {
            cellView = NSTableCellView()
            cellView.identifier = identifier

            let imageView = NSImageView(image: NSImage(systemSymbolName: "apple.terminal", accessibilityDescription: nil) ?? NSImage())
            imageView.symbolConfiguration = .init(pointSize: NSFont.smallSystemFontSize, weight: .regular)
            imageView.setContentHuggingPriority(.required, for: .horizontal)
            let textField = NSTextField(labelWithString: "")
            textField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            textField.lineBreakMode = .byTruncatingTail
            textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            imageView.translatesAutoresizingMaskIntoConstraints = false
            textField.translatesAutoresizingMaskIntoConstraints = false
            cellView.addSubview(imageView)
            cellView.addSubview(textField)
            cellView.imageView = imageView
            cellView.textField = textField

            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 2),
                imageView.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
                textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
                textField.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -2),
                textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
            ])
        }

        cellView.textField?.stringValue = self.sessions[row].displayTitle
        cellView.toolTip = self.sessions[row].displayTitle

        return cellView
    }


    func tableViewSelectionDidChange(_ notification: Notification) {

        let row = self.tableView.selectedRow

        guard row >= 0, row != self.selectedIndex else { return }

        self.select(index: row)
        self.focus()
    }


    // MARK: Action Messages

    /// Closes the terminal session currently selected.
    @IBAction func closeSelectedSession(_ sender: Any?) {

        guard let selectedIndex else { return }

        self.close(session: self.sessions[selectedIndex])
    }


    /// Closes the terminal session clicked in the session list.
    @IBAction func closeClickedSession(_ sender: Any?) {

        let row = self.tableView.clickedRow

        guard self.sessions.indices.contains(row) else { return }

        self.close(session: self.sessions[row])
    }


    // MARK: Private Methods

    /// Shows the session at the given index.
    ///
    /// - Parameter index: The index of the session to select.
    private func select(index: Int) {

        guard self.sessions.indices.contains(index) else { return }

        let hadFocus = self.hasFocus
        let session = self.sessions[index]

        for subview in self.sessionContainerView.subviews where subview !== session.view {
            subview.removeFromSuperview()
        }
        if session.view.superview !== self.sessionContainerView {
            session.view.translatesAutoresizingMaskIntoConstraints = false
            self.sessionContainerView.addSubview(session.view)
            NSLayoutConstraint.activate([
                session.view.leadingAnchor.constraint(equalTo: self.sessionContainerView.leadingAnchor),
                session.view.trailingAnchor.constraint(equalTo: self.sessionContainerView.trailingAnchor),
                session.view.topAnchor.constraint(equalTo: self.sessionContainerView.topAnchor),
                session.view.bottomAnchor.constraint(equalTo: self.sessionContainerView.bottomAnchor),
            ])
        }

        self.selectedIndex = index
        if self.tableView.selectedRow != index {
            self.tableView.selectRowIndexes([index], byExtendingSelection: false)
        }

        if hadFocus {
            session.focus()
        }
    }


    /// Terminates the given session and removes it from the panel.
    ///
    /// - Parameter session: The session to close.
    private func close(session: TerminalViewController) {

        guard let index = self.sessions.firstIndex(of: session) else { return }

        let hadFocus = self.hasFocus

        session.terminationHandler = nil
        session.titleHandler = nil
        session.terminate()
        session.viewIfLoaded?.removeFromSuperview()
        session.removeFromParent()
        self.sessions.remove(at: index)
        self.selectedIndex = nil

        guard !self.sessions.isEmpty else {
            self.tableView.reloadData()
            self.closeHandler?()
            return
        }

        self.tableView.reloadData()
        self.invalidateListVisibility()
        self.select(index: min(index, self.sessions.count - 1))
        if hadFocus {
            self.focus()
        }
    }


    /// Updates the title of the given session in the session list.
    ///
    /// - Parameter session: The session whose title has changed.
    private func reloadTitle(of session: TerminalViewController) {

        guard let index = self.sessions.firstIndex(of: session) else { return }

        self.tableView.reloadData(forRowIndexes: [index], columnIndexes: [0])
    }


    /// Shows the session list only when there are multiple sessions.
    private func invalidateListVisibility() {

        let showsList = self.sessions.count > 1

        self.listContainerView.isHidden = !showsList
        self.listWidthConstraint.constant = showsList ? Self.listWidth : 0
    }


    /// Applies the current palette to the panel and its sessions.
    private func applyPalette() {

        for session in self.sessions {
            session.palette = self.palette
        }

        guard self.isViewLoaded else { return }

        self.view.appearance = NSAppearance(named: self.palette.isDark ? .darkAqua : .aqua)
        (self.view as? TerminalBackgroundView)?.backgroundColor = self.palette.background
    }


    /// Creates a borderless symbol button for the header.
    private static func makeButton(symbolName: String, action: Selector, target: AnyObject?, label: String) -> NSButton {

        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label) ?? NSImage()
        let button = NSButton(image: image, target: target, action: action)
        button.isBordered = false
        button.symbolConfiguration = .init(pointSize: 12, weight: .regular)
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = label
        button.refusesFirstResponder = true
        button.setContentHuggingPriority(.required, for: .horizontal)

        return button
    }


    /// Creates a separator line.
    private static func makeSeparator() -> NSBox {

        let separator = NSBox()
        separator.boxType = .separator

        return separator
    }
}


// MARK: -

/// A view filled with the terminal background color.
final class TerminalBackgroundView: NSView {

    var backgroundColor: NSColor = .textBackgroundColor  { didSet { self.needsDisplay = true } }


    override var isOpaque: Bool { true }


    override func draw(_ dirtyRect: NSRect) {

        self.backgroundColor.setFill()
        dirtyRect.fill()
    }
}
