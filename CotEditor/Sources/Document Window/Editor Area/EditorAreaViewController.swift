//
//  EditorAreaViewController.swift
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
import UniformTypeIdentifiers
import Defaults
import URLUtils

/// The editor area of a folder window that holds split editor groups, each of which has its own tabs.
final class EditorAreaViewController: NSSplitViewController {

    // MARK: Public Properties

    static let maximumNumberOfGroups = 4
    
    /// The maximum number of tab editors kept in memory, excluding the visible ones.
    static let maximumNumberOfCachedEditors = 16

    private(set) var groups: [EditorGroupViewController] = []
    private(set) weak var focusedGroup: EditorGroupViewController?


    // MARK: Private Properties

    private weak var directoryDocument: DirectoryDocument?

    private var observers: [NotificationCenter.ObservationToken] = []
    private var displayOrder: UInt64 = 0


    // MARK: Lifecycle

    init(directoryDocument: DirectoryDocument) {

        self.directoryDocument = directoryDocument

        super.init(nibName: nil, bundle: nil)
    }


    @available(*, unavailable)
    required init?(coder: NSCoder) {

        fatalError("init(coder:) has not been implemented")
    }


    // MARK: View Controller Methods

    override func viewDidLoad() {

        super.viewDidLoad()

        self.splitView.isVertical = UserDefaults.standard[.splitViewVertical]
        self.splitView.dividerStyle = .thin

        if self.groups.isEmpty {
            self.addGroup()
        }

        self.observers = [
            // move the focused group with the keyboard focus
            NotificationCenter.default.addObserver(for: EditorTextView.DidBecomeFirstResponderMessage.self) { [weak self] message in
                guard
                    let self,
                    let window = self.viewIfLoaded?.window,
                    let textView = window.firstResponder as? NSView,
                    ObjectIdentifier(textView) == message.subjectIdentifier,
                    let group = self.groups.first(where: { textView.isDescendant(of: $0.view) })
                else { return }

                self.focus(group)
            },
            // update tab titles when a document is renamed or moved
            NotificationCenter.default.addObserver(for: NSDocument.DidChangeFileURLMessage.self) { [weak self] _ in
                self?.groups.forEach { $0.reloadTabBar() }
            },
        ]
    }


    // MARK: Split View Controller Methods

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {

        switch item.action {
            case #selector(performClose(_:)):
                return true

            case #selector(newDocumentAsTab(_:)):
                return self.currentTab?.document != nil

            case #selector(selectNextTab(_:)),
                 #selector(selectPreviousTab(_:)):
                return (self.focusedGroup?.tabs.count ?? 0) > 1

            case #selector(openSplitTextView(_:)):
                (item as? NSMenuItem)?.image = self.splitView.isVertical
                    ? NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: nil)
                    : NSImage(systemSymbolName: "rectangle.split.1x2", accessibilityDescription: nil)
                return self.groups.count < Self.maximumNumberOfGroups

            case #selector(closeSplitTextView(_:)):
                return self.groups.count > 1

            case #selector(toggleSplitOrientation(_:)):
                (item as? NSMenuItem)?.title = self.splitView.isVertical
                    ? String(localized: "Stack Editors Horizontally", table: "MainMenu", comment: "verb; menu item")
                    : String(localized: "Stack Editors Vertically", table: "MainMenu", comment: "verb; menu item")
                (item as? NSMenuItem)?.image = self.splitView.isVertical
                    ? NSImage(systemSymbolName: "rectangle.split.1x2", accessibilityDescription: nil)
                    : NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: nil)
                return true

            case #selector(focusNextEditor(_:)),
                 #selector(focusPreviousEditor(_:)):
                return true
                
            case #selector(toggleEditorTabBar(_:)):
                (item as? NSMenuItem)?.title = UserDefaults.standard[.showEditorTabBar]
                    ? String(localized: "Hide Editor Tab Bar", table: "MainMenu", comment: "verb; menu item")
                    : String(localized: "Show Editor Tab Bar", table: "MainMenu", comment: "verb; menu item")
                return true

            default:
                return super.validateUserInterfaceItem(item)
        }
    }


    // MARK: Public Methods

    /// The selected tab in the focused group.
    var currentTab: EditorTab? {

        self.focusedGroup?.selectedTab
    }


    /// The document presented in the focused group.
    var currentDocument: DataDocument? {

        self.currentTab?.document
    }


    /// The text editor in the focused group, if any.
    var documentViewController: DocumentViewController? {

        self.focusedGroup?.documentViewController
    }


    /// All tabs in the editor area.
    var allTabs: [EditorTab] {

        self.groups.flatMap(\.tabs)
    }


    /// Returns whether any tab presents the given document.
    ///
    /// - Parameter document: The document to check.
    /// - Returns: `true` if the document is presented in a tab.
    func isPresenting(_ document: DataDocument) -> Bool {

        self.groups.contains { $0.tab(for: document) != nil }
    }


    /// Presents the document in a tab according to the given disposition.
    ///
    /// - Parameters:
    ///   - document: The document to present.
    ///   - disposition: How to present the document.
    ///   - opensAsPlainText: Whether the document was opened forcibly as plain text.
    /// - Returns: The tab presenting the document.
    @discardableResult func present(_ document: DataDocument, disposition: EditorOpenDisposition, opensAsPlainText: Bool = false) -> EditorTab {

        self.loadViewIfNeeded()

        let group: EditorGroupViewController = switch disposition {
            case .otherGroup:
                self.groups.first { $0 !== self.focusedGroup } ?? self.addGroup(after: self.focusedGroup) ?? self.focusedGroup ?? self.groups[0]
            default:
                self.focusedGroup ?? self.groups[0]
        }

        let tab = self.tab(presenting: document, in: group, disposition: disposition, opensAsPlainText: opensAsPlainText)

        group.select(tab)
        group.reloadTabBar()
        self.focus(group)
        self.invalidateDocumentRestorableState()

        return tab
    }


    /// Removes all tabs presenting the given document without asking to save it.
    ///
    /// - Parameter document: The document whose tabs to remove.
    func removeTabs(presenting document: DataDocument) {

        for group in self.groups {
            for tab in group.tabs where tab.document === document {
                group.remove(tab)
            }
        }
        self.removeEmptyGroups()
        self.notifyCurrentDocumentChange()
        self.invalidateDocumentRestorableState()
    }


    /// Updates the tabs whose edited state changed, and keeps edited temporary tabs open.
    ///
    /// - Note: This method is called every time a document's change count is updated,
    ///         thus it reloads only the tab bars that actually need to update.
    func invalidateEditedStates() {
        
        for group in self.groups {
            var needsReload = false
            for tab in group.tabs where tab.isEdited != tab.displayedEditedState {
                tab.displayedEditedState = tab.isEdited
                if tab.isEdited, tab.isTemporary {
                    tab.isTemporary = false
                }
                needsReload = true
            }
            if needsReload {
                group.reloadTabBar()
            }
        }
    }
    
    
    /// Updates the tabs presenting the given document.
    ///
    /// - Parameter document: The document updated.
    func reloadTabs(presenting document: DataDocument) {

        for group in self.groups where group.tab(for: document) != nil {
            // keep the tab permanently once the document is edited
            if document.isDocumentEdited {
                group.tabs
                    .filter { $0.document === document && $0.isTemporary }
                    .forEach { $0.isTemporary = false }
            }
            group.reloadTabBar()
        }
    }


    /// Makes the given group the focused one.
    ///
    /// - Parameter group: The group to focus.
    func focus(_ group: EditorGroupViewController) {

        guard self.groups.contains(group) else { return }

        let changed = group !== self.focusedGroup

        self.focusedGroup = group
        for item in self.groups {
            item.isFocused = (item === group)
        }

        if changed {
            self.registerViewController(of: group)
            self.notifyCurrentDocumentChange()
        }
    }


    /// Closes the given tab, asking to save the document if needed.
    ///
    /// - Parameters:
    ///   - tab: The tab to close.
    ///   - group: The group owning the tab.
    func close(_ tab: EditorTab, in group: EditorGroupViewController) {

        Task {
            _ = await self.closeTab(tab, in: group)
        }
    }


    /// Moves the tab to the editor group under the given location.
    ///
    /// - Parameters:
    ///   - tab: The tab to move.
    ///   - sourceGroup: The group currently owning the tab.
    ///   - location: The drop location in the window coordinates.
    /// - Returns: `true` if the tab was moved.
    func moveTab(_ tab: EditorTab, from sourceGroup: EditorGroupViewController, toWindowLocation location: NSPoint) -> Bool {

        guard
            let targetGroup = self.groups.first(where: { $0 !== sourceGroup && $0.view.bounds.contains($0.view.convert(location, from: nil)) })
        else { return false }

        // just select the existing tab if the target already presents the document
        if let document = tab.document, let existingTab = targetGroup.tab(for: document) {
            sourceGroup.remove(tab)
            targetGroup.select(existingTab)
        } else {
            let index = targetGroup.tabIndex(at: location)
            sourceGroup.remove(tab)
            targetGroup.insert(tab, at: index)
            targetGroup.select(tab)
            self.applySplitState(to: tab.viewController as? DocumentViewController)
        }

        if sourceGroup.tabs.isEmpty {
            self.removeGroup(sourceGroup)
        }

        self.focus(targetGroup)
        targetGroup.focusContent()
        self.invalidateDocumentRestorableState()

        return true
    }


    /// Makes the tab permanent.
    func keepOpen(_ tab: EditorTab, in group: EditorGroupViewController) {

        guard tab.isTemporary else { return }

        tab.isTemporary = false
        group.reloadTabBar()
        self.invalidateDocumentRestorableState()
    }


    /// Loads the document of a restored placeholder tab.
    ///
    /// - Parameters:
    ///   - tab: The tab to load.
    ///   - group: The group owning the tab.
    func loadDocument(of tab: EditorTab, in group: EditorGroupViewController) {

        guard
            let fileURL = tab.placeholderURL,
            let document = self.directoryDocument?.memberDocument(at: fileURL, asPlainText: tab.opensAsPlainText)
        else { return }

        tab.document = document
        if let fileURL = document.fileURL {
            tab.history.record(fileURL: fileURL, opensAsPlainText: tab.opensAsPlainText, fileType: document.fileType.flatMap(UTType.init))
        }
    }


    /// Notifies that the group changed the displayed tab.
    ///
    /// - Parameter group: The group that changed the selection.
    func groupDidChangeSelection(_ group: EditorGroupViewController) {
        
        if let tab = group.selectedTab {
            self.displayOrder += 1
            tab.lastDisplayedOrder = self.displayOrder
        }
        self.unloadInactiveEditorsIfNeeded()
        
        self.applySplitState(to: group.documentViewController)

        // register the editor for the document if it has no visible editor
        if let viewController = group.documentViewController {
            let document = viewController.document
            if group === self.focusedGroup || document.editorViewController?.viewIfLoaded?.window == nil {
                document.editorViewController = viewController
            }
        }

        if group === self.focusedGroup {
            self.notifyCurrentDocumentChange()
        }
    }


    /// Builds the context menu for a tab.
    ///
    /// - Parameters:
    ///   - tab: The tab clicked.
    ///   - group: The group owning the tab.
    /// - Returns: A menu.
    func contextMenu(for tab: EditorTab, in group: EditorGroupViewController) -> NSMenu {

        let menu = NSMenu()
        let context = TabContext(tab: tab, group: group)

        func addItem(_ title: String, action: Selector, isEnabled: Bool = true) {

            let item = NSMenuItem(title: title, action: isEnabled ? action : nil, keyEquivalent: "")
            item.target = self
            item.representedObject = context
            menu.addItem(item)
        }

        let index = group.tabs.firstIndex(of: tab) ?? 0

        addItem(String(localized: "Close Tab", table: "Document", comment: "menu item for an editor tab"),
                action: #selector(closeTabFromMenu))
        addItem(String(localized: "Close Other Tabs", table: "Document", comment: "menu item for an editor tab"),
                action: #selector(closeOtherTabsFromMenu), isEnabled: group.tabs.count > 1)
        addItem(String(localized: "Close Tabs to the Right", table: "Document", comment: "menu item for an editor tab"),
                action: #selector(closeTabsToRightFromMenu), isEnabled: index < group.tabs.count - 1)
        menu.addItem(.separator())
        if tab.isTemporary {
            addItem(String(localized: "Keep Open", table: "Document", comment: "menu item for an editor tab"),
                    action: #selector(keepOpenFromMenu))
        }
        addItem(String(localized: "Open in Split Editor", table: "Document", comment: "menu item for an editor tab"),
                action: #selector(openInSplitFromMenu), isEnabled: tab.document != nil)
        addItem(String(localized: "Open in New Window", table: "Document", comment: "menu item for an editor tab"),
                action: #selector(openInNewWindowFromMenu), isEnabled: tab.fileURL != nil)
        menu.addItem(.separator())
        addItem(String(localized: "Reveal in File Browser", table: "Document", comment: "menu item for an editor tab"),
                action: #selector(revealInFileBrowserFromMenu), isEnabled: tab.fileURL != nil)
        addItem(String(localized: "Show in Finder", table: "Document", comment: "menu item for an editor tab"),
                action: #selector(showInFinderFromMenu), isEnabled: tab.fileURL != nil)

        return menu
    }


    // MARK: Action Messages

    /// Closes the selected tab, or the window if it is the only tab.
    @IBAction func performClose(_ sender: Any?) {

        let tabCount = self.allTabs.count

        guard tabCount > 1 || self.groups.count > 1, let group = self.focusedGroup else {
            self.view.window?.performClose(sender)
            return
        }

        if let tab = group.selectedTab {
            self.close(tab, in: group)
        } else {
            self.closeGroup(group)
        }
    }


    /// Opens the current document in a new tab.
    @IBAction func newDocumentAsTab(_ sender: Any?) {

        guard let currentTab, let document = currentTab.document else { return NSSound.beep() }

        currentTab.isTemporary = false
        self.present(document, disposition: .newTab, opensAsPlainText: currentTab.opensAsPlainText)
        self.focusedGroup?.focusContent()
    }


    /// Toggles the visibility of the editor tab bars (sync all folder windows).
    @IBAction func toggleEditorTabBar(_ sender: Any?) {
        
        UserDefaults.standard[.showEditorTabBar].toggle()
    }
    
    
    /// Selects the next tab in the focused group.
    @IBAction func selectNextTab(_ sender: Any?) {

        self.focusedGroup?.selectAdjacentTab(forward: true)
    }


    /// Selects the previous tab in the focused group.
    @IBAction func selectPreviousTab(_ sender: Any?) {

        self.focusedGroup?.selectAdjacentTab(forward: false)
    }


    /// Adds a new editor group showing the current document.
    ///
    /// - Note: The selector name should be the same as one in `DocumentViewController`.
    @IBAction func openSplitTextView(_ sender: Any?) {

        guard
            self.groups.count < Self.maximumNumberOfGroups,
            let baseGroup = self.focusedGroup,
            let group = self.addGroup(after: baseGroup)
        else { return NSSound.beep() }

        if let tab = baseGroup.selectedTab, let document = tab.document {
            let newTab = EditorTab(document: document, isTemporary: false, opensAsPlainText: tab.opensAsPlainText)
            newTab.history = tab.history
            group.insert(newTab)
            group.select(newTab)

            // align the visible area with the original editor
            if let baseTextView = baseGroup.documentViewController?.focusedTextView,
               let newTextView = group.documentViewController?.focusedTextView
            {
                newTextView.selectedRanges = baseTextView.selectedRanges
                newTextView.scrollRangeToVisible(baseTextView.selectedRange)
            }
        }

        self.focus(group)
        group.focusContent()
        self.invalidateDocumentRestorableState()
    }


    /// Closes the focused editor group.
    ///
    /// - Note: The selector name should be the same as one in `DocumentViewController`.
    @IBAction func closeSplitTextView(_ sender: Any?) {

        guard
            self.groups.count > 1,
            let group = self.group(for: sender) ?? self.focusedGroup
        else { return }

        self.closeGroup(group)
    }


    /// Toggles the orientation of the editor groups.
    ///
    /// - Note: The selector name should be the same as one in `DocumentViewController`.
    @IBAction func toggleSplitOrientation(_ sender: Any?) {

        self.splitView.isVertical.toggle()
        UserDefaults.standard[.splitViewVertical] = self.splitView.isVertical
        self.distributeGroupsEvenly()
        self.applySplitStateToAll()
    }


    /// Moves the focus to the next editor group.
    ///
    /// - Note: The selector name should be the same as one in `DocumentViewController`.
    @IBAction func focusNextEditor(_ sender: Any?) {

        self.focusAdjacentGroup(forward: true)
    }


    /// Moves the focus to the previous editor group.
    ///
    /// - Note: The selector name should be the same as one in `DocumentViewController`.
    @IBAction func focusPreviousEditor(_ sender: Any?) {

        self.focusAdjacentGroup(forward: false)
    }


    // MARK: Restoration

    /// Encodes the tab layout for state restoration.
    ///
    /// - Returns: A property list representation, or `nil` if empty.
    func encodedState() -> Data? {

        let groups: [[String: Any]] = self.groups.map { group in
            let tabs: [[String: Any]] = group.tabs.compactMap { tab in
                guard let bookmark = try? tab.fileURL?.bookmarkData(options: .withSecurityScope) else { return nil }
                return [
                    StateKey.bookmark: bookmark,
                    StateKey.isTemporary: tab.isTemporary,
                    StateKey.opensAsPlainText: tab.opensAsPlainText,
                ]
            }
            let selectedIndex = group.selectedTab.flatMap { group.tabs.firstIndex(of: $0) } ?? 0
            return [StateKey.tabs: tabs, StateKey.selectedIndex: selectedIndex]
        }

        guard groups.contains(where: { ($0[StateKey.tabs] as? [Any])?.isEmpty == false }) else { return nil }

        let state: [String: Any] = [
            StateKey.groups: groups,
            StateKey.focusedIndex: self.focusedGroup.flatMap { self.groups.firstIndex(of: $0) } ?? 0,
        ]

        return try? PropertyListSerialization.data(fromPropertyList: state, format: .binary, options: 0)
    }


    /// Restores the tab layout from the encoded state.
    ///
    /// Only the selected tab of each group loads its document immediately; the others load when selected.
    ///
    /// - Parameters:
    ///   - data: The encoded state.
    ///   - rootURL: The folder URL that all files must belong to.
    /// - Returns: `true` if any tab was restored.
    @discardableResult func restore(from data: Data, in rootURL: URL) -> Bool {

        guard
            let state = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let groupStates = state[StateKey.groups] as? [[String: Any]]
        else { return false }

        self.loadViewIfNeeded()

        var restoredGroups: [(EditorGroupViewController, Int)] = []
        for groupState in groupStates.prefix(Self.maximumNumberOfGroups) {
            let tabStates = groupState[StateKey.tabs] as? [[String: Any]] ?? []
            let tabs: [EditorTab] = tabStates.compactMap { tabState in
                guard let bookmark = tabState[StateKey.bookmark] as? Data else { return nil }

                var isStale = false
                guard
                    let fileURL = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, bookmarkDataIsStale: &isStale),
                    rootURL.isAncestor(of: fileURL),
                    fileURL.isReachable
                else { return nil }

                let tab = EditorTab(document: nil,
                                    isTemporary: tabState[StateKey.isTemporary] as? Bool ?? false,
                                    opensAsPlainText: tabState[StateKey.opensAsPlainText] as? Bool ?? false)
                tab.placeholderURL = fileURL
                return tab
            }

            guard !tabs.isEmpty else { continue }

            let group: EditorGroupViewController = if let lastGroup = restoredGroups.last?.0 {
                self.addGroup(after: lastGroup) ?? lastGroup
            } else if let firstGroup = self.groups.first {
                firstGroup
            } else {
                self.addGroup()!
            }
            for tab in tabs {
                group.insert(tab, at: group.tabs.endIndex)
            }
            let selectedIndex = (groupState[StateKey.selectedIndex] as? Int ?? 0).clamped(to: 0...(tabs.count - 1))
            restoredGroups.append((group, selectedIndex))
        }

        guard !restoredGroups.isEmpty else { return false }

        for (group, selectedIndex) in restoredGroups {
            group.select(group.tabs[selectedIndex])
        }

        let focusedIndex = (state[StateKey.focusedIndex] as? Int ?? 0).clamped(to: 0...(restoredGroups.count - 1))
        self.focus(restoredGroups[focusedIndex].0)
        self.notifyCurrentDocumentChange()

        return true
    }


    // MARK: Private Methods

    private enum StateKey {

        static let groups = "groups"
        static let focusedIndex = "focusedIndex"
        static let tabs = "tabs"
        static let selectedIndex = "selectedIndex"
        static let bookmark = "bookmark"
        static let isTemporary = "isTemporary"
        static let opensAsPlainText = "opensAsPlainText"
    }


    private final class TabContext {

        weak var tab: EditorTab?
        weak var group: EditorGroupViewController?

        init(tab: EditorTab, group: EditorGroupViewController) {

            self.tab = tab
            self.group = group
        }
    }


    /// Finds or creates the tab to present the document in the group.
    private func tab(presenting document: DataDocument, in group: EditorGroupViewController, disposition: EditorOpenDisposition, opensAsPlainText: Bool) -> EditorTab {

        // replace the content of the selected tab (history navigation)
        if disposition == .replaceCurrent, let tab = group.selectedTab {
            if tab.document !== document {
                let oldDocument = tab.document
                tab.opensAsPlainText = opensAsPlainText
                group.replaceDocument(document, in: tab)
                self.releaseIfUnused(oldDocument)
            }
            return tab
        }

        // select the existing tab
        if disposition != .newTab, let tab = group.tab(for: document) {
            if disposition != .temporary {
                tab.isTemporary = false
            }
            return tab
        }

        // reuse the temporary tab
        if disposition == .temporary || disposition == .replaceCurrent, let tab = group.temporaryTab {
            let oldDocument = tab.document
            tab.opensAsPlainText = opensAsPlainText
            group.replaceDocument(document, in: tab)
            self.releaseIfUnused(oldDocument)
            return tab
        }

        let tab = EditorTab(document: document,
                            isTemporary: disposition == .temporary || disposition == .replaceCurrent,
                            opensAsPlainText: opensAsPlainText)
        group.insert(tab)

        return tab
    }


    /// Closes the tab, asking to save if it is the last tab presenting an edited document.
    ///
    /// - Returns: `false` if the user cancelled.
    private func closeTab(_ tab: EditorTab, in group: EditorGroupViewController) async -> Bool {

        guard group.tabs.contains(tab) else { return true }

        let document = tab.document
        let isLastReference = document.map { document in
            self.groups.flatMap(\.tabs).filter { $0.document === document }.count == 1
        } ?? false

        if isLastReference, let document, document.isDocumentEdited {
            group.select(tab)
            guard await document.canClose() else { return false }
        }

        let isFocusedGroup = (group === self.focusedGroup)
        group.remove(tab)

        if group.tabs.isEmpty, self.groups.count > 1 {
            self.removeGroup(group)
        } else if isFocusedGroup {
            group.focusContent()
        }

        if isLastReference, let document {
            self.directoryDocument?.releaseDocument(document, force: true)
        }

        self.notifyCurrentDocumentChange()
        self.invalidateDocumentRestorableState()

        return true
    }


    /// Closes all tabs in the group, then removes the group.
    private func closeGroup(_ group: EditorGroupViewController) {

        Task {
            for tab in group.tabs.reversed() {
                guard await self.closeTab(tab, in: group) else { return }
            }
            if self.groups.contains(group), self.groups.count > 1 {
                self.removeGroup(group)
                self.notifyCurrentDocumentChange()
                self.invalidateDocumentRestorableState()
            }
        }
    }


    /// Unloads the editors of the tabs not displayed for the longest time when too many editors are cached.
    private func unloadInactiveEditorsIfNeeded() {
        
        let visibleTabs = self.groups.compactMap(\.selectedTab)
        let hiddenTabs = self.groups
            .flatMap { group in group.tabs.map { (tab: $0, group: group) } }
            .filter { $0.tab.viewController != nil && !visibleTabs.contains($0.tab) }
        
        guard hiddenTabs.count > Self.maximumNumberOfCachedEditors else { return }
        
        let tabsToUnload = hiddenTabs
            .sorted { $0.tab.lastDisplayedOrder < $1.tab.lastDisplayedOrder }
            .prefix(hiddenTabs.count - Self.maximumNumberOfCachedEditors)
        
        for item in tabsToUnload {
            item.group.unloadViewController(of: item.tab)
        }
    }
    
    
    /// Releases the document if no tab presents it anymore.
    private func releaseIfUnused(_ document: DataDocument?) {

        guard let document, !self.isPresenting(document) else { return }

        self.directoryDocument?.releaseDocument(document, force: false)
    }


    /// Adds a new editor group.
    ///
    /// - Parameter baseGroup: The group after which the new group is inserted, or `nil` to append.
    /// - Returns: The group added, or `nil` if the maximum number of groups is reached.
    @discardableResult private func addGroup(after baseGroup: EditorGroupViewController? = nil) -> EditorGroupViewController? {

        guard self.groups.count < Self.maximumNumberOfGroups else { return nil }

        let group = EditorGroupViewController()
        group.editorArea = self

        let index = baseGroup.flatMap { self.groups.firstIndex(of: $0) }.map { $0 + 1 } ?? self.groups.endIndex
        let item = NSSplitViewItem(viewController: group)
        item.minimumThickness = 120
        item.holdingPriority = .defaultLow

        self.groups.insert(group, at: index)
        self.insertSplitViewItem(item, at: index)

        if self.focusedGroup == nil {
            self.focus(group)
        }

        self.distributeGroupsEvenly()
        self.applySplitStateToAll()

        return group
    }


    /// Removes the editor group.
    private func removeGroup(_ group: EditorGroupViewController) {

        guard let index = self.groups.firstIndex(of: group), self.groups.count > 1 else { return }

        if let item = self.splitViewItem(for: group) {
            self.removeSplitViewItem(item)
        }
        self.groups.remove(at: index)

        if self.focusedGroup === group || self.focusedGroup == nil {
            let newGroup = self.groups[safe: index - 1] ?? self.groups[0]
            self.focus(newGroup)
            newGroup.focusContent()
        }

        self.distributeGroupsEvenly()
        self.applySplitStateToAll()
    }


    /// Removes groups without tabs, keeping at least one group.
    private func removeEmptyGroups() {

        for group in self.groups where group.tabs.isEmpty && self.groups.count > 1 {
            self.removeGroup(group)
        }
    }


    /// Moves the focus to the next/previous group, or refocuses the current one if not split.
    private func focusAdjacentGroup(forward: Bool) {

        guard
            let focusedGroup,
            let index = self.groups.firstIndex(of: focusedGroup)
        else { return }

        let newGroup = self.groups[(index + (forward ? 1 : -1) + self.groups.count) % self.groups.count]
        self.focus(newGroup)
        newGroup.focusContent()
    }


    /// Finds the group containing the sender view.
    private func group(for sender: Any?) -> EditorGroupViewController? {

        guard let view = sender as? NSView else { return nil }

        return self.groups.first { view.isDescendant(of: $0.view) }
    }


    /// Sizes all groups evenly.
    private func distributeGroupsEvenly() {

        guard self.isViewLoaded, self.groups.count > 1 else { return }

        self.splitView.layoutSubtreeIfNeeded()

        let length = self.splitView.isVertical ? self.splitView.bounds.width : self.splitView.bounds.height
        let thickness = self.splitView.dividerThickness
        let size = (length - thickness * CGFloat(self.groups.count - 1)) / CGFloat(self.groups.count)

        for index in 0..<(self.groups.count - 1) {
            self.splitView.setPosition((size + thickness) * CGFloat(index + 1) - thickness, ofDividerAt: index)
        }
    }


    /// Sets the split editor state to the document view controller.
    private func applySplitState(to viewController: DocumentViewController?) {

        viewController?.applyExternalSplitState(isVertical: self.splitView.isVertical, canClose: self.groups.count > 1)
    }


    /// Sets the split editor state to all cached document view controllers.
    private func applySplitStateToAll() {

        for tab in self.allTabs {
            self.applySplitState(to: tab.viewController as? DocumentViewController)
        }
    }


    /// Registers the editor of the group as the main editor for its document.
    private func registerViewController(of group: EditorGroupViewController) {

        guard let viewController = group.documentViewController else { return }

        viewController.document.editorViewController = viewController
    }


    /// Notifies the directory document that the current document may have changed.
    private func notifyCurrentDocumentChange() {

        self.directoryDocument?.editorAreaDidChangeCurrentDocument()
    }


    /// Invalidates the restorable state of the directory document.
    func invalidateDocumentRestorableState() {

        self.directoryDocument?.invalidateRestorableState()
    }


    // MARK: Context Menu Actions

    @objc private func closeTabFromMenu(_ sender: NSMenuItem) {

        guard let context = sender.representedObject as? TabContext, let tab = context.tab, let group = context.group else { return }

        self.close(tab, in: group)
    }


    @objc private func closeOtherTabsFromMenu(_ sender: NSMenuItem) {

        guard let context = sender.representedObject as? TabContext, let tab = context.tab, let group = context.group else { return }

        let tabs = group.tabs.filter { $0 !== tab }
        Task {
            for other in tabs {
                guard await self.closeTab(other, in: group) else { return }
            }
        }
    }


    @objc private func closeTabsToRightFromMenu(_ sender: NSMenuItem) {

        guard
            let context = sender.representedObject as? TabContext,
            let tab = context.tab,
            let group = context.group,
            let index = group.tabs.firstIndex(of: tab)
        else { return }

        let tabs = Array(group.tabs[(index + 1)...])
        Task {
            for other in tabs.reversed() {
                guard await self.closeTab(other, in: group) else { return }
            }
        }
    }


    @objc private func keepOpenFromMenu(_ sender: NSMenuItem) {

        guard let context = sender.representedObject as? TabContext, let tab = context.tab, let group = context.group else { return }

        self.keepOpen(tab, in: group)
    }


    @objc private func openInSplitFromMenu(_ sender: NSMenuItem) {

        guard let context = sender.representedObject as? TabContext, let document = context.tab?.document else { return }

        self.present(document, disposition: .otherGroup, opensAsPlainText: context.tab?.opensAsPlainText ?? false)
        self.focusedGroup?.focusContent()
    }


    @objc private func openInNewWindowFromMenu(_ sender: NSMenuItem) {

        guard let context = sender.representedObject as? TabContext, let fileURL = context.tab?.fileURL else { return }

        self.directoryDocument?.openInNewWindow(fileURL: fileURL)
    }


    @objc private func revealInFileBrowserFromMenu(_ sender: NSMenuItem) {

        guard let context = sender.representedObject as? TabContext, let fileURL = context.tab?.fileURL else { return }

        self.directoryDocument?.revealInFileBrowser(fileURL: fileURL)
    }


    @objc private func showInFinderFromMenu(_ sender: NSMenuItem) {

        guard let context = sender.representedObject as? TabContext, let fileURL = context.tab?.fileURL else { return }

        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }
}
