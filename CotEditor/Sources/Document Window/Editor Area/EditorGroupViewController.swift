//
//  EditorGroupViewController.swift
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
import Combine
import OSLog
import Defaults
import UniformTypeIdentifiers

/// An editor pane in a folder window, consisting of a tab bar and the content of the selected tab.
///
/// The content view controller of each tab is cached in the tab,
/// so that switching tabs only swaps views without rebuilding the editor or re-parsing the document.
final class EditorGroupViewController: NSViewController, EditorTabBarDelegate {

    // MARK: Public Properties

    weak var editorArea: EditorAreaViewController?

    private(set) var tabs: [EditorTab] = []
    private(set) var selectedTab: EditorTab?

    /// Whether the group is the focused one in the editor area.
    var isFocused = false {

        didSet {
            guard isFocused != oldValue else { return }
            self.tabBar.isActive = isFocused
        }
    }


    // MARK: Private Properties

    private let tabBar = EditorTabBar()
    private var tabBarHeightConstraint: NSLayoutConstraint?
    private var tabBarVisibilityObserver: AnyCancellable?
    private let containerView = NSView()
    private var emptyViewController: NSViewController?
    private weak var displayedViewController: NSViewController?


    // MARK: View Controller Methods

    override func loadView() {

        let view = NSView()

        self.tabBar.delegate = self
        self.tabBar.isActive = self.isFocused
        self.tabBar.translatesAutoresizingMaskIntoConstraints = false
        self.containerView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(self.containerView)
        view.addSubview(self.tabBar)

        // -> The tab bar extends under the toolbar to fill the area behind it,
        //    while its tabs are placed below the safe area.
        let tabBarHeightConstraint = self.tabBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: EditorTabBar.barHeight)
        self.tabBarHeightConstraint = tabBarHeightConstraint
        
        NSLayoutConstraint.activate([
            self.tabBar.topAnchor.constraint(equalTo: view.topAnchor),
            self.tabBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            self.tabBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabBarHeightConstraint,

            self.containerView.topAnchor.constraint(equalTo: self.tabBar.bottomAnchor),
            self.containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            self.containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            self.containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.group)
        view.setAccessibilityLabel(String(localized: "Editor", table: "Document", comment: "accessibility label"))

        self.view = view
        
        self.tabBarVisibilityObserver = UserDefaults.standard.publisher(for: .showEditorTabBar, initial: true)
            .sink { [weak self] isShown in
                self?.tabBar.isHidden = !isShown
                self?.tabBarHeightConstraint?.constant = isShown ? EditorTabBar.barHeight : 0
            }
        
        self.displaySelectedTab()
    }


    // MARK: Public Methods

    /// The tab presenting the given document, if any.
    ///
    /// - Parameter document: The document to find.
    /// - Returns: A tab in the group.
    func tab(for document: DataDocument) -> EditorTab? {

        self.tabs.first { $0.document === document }
    }


    /// The tab with the given identifier, if any.
    func tab(id: UUID) -> EditorTab? {

        self.tabs.first { $0.id == id }
    }


    /// The temporary tab in the group, if any.
    var temporaryTab: EditorTab? {

        self.tabs.first(where: \.isTemporary)
    }


    /// The view controller of the selected tab if it is a text document editor.
    var documentViewController: DocumentViewController? {

        self.selectedTab?.viewController as? DocumentViewController
    }


    /// Inserts a tab after the selected tab.
    ///
    /// - Parameters:
    ///   - tab: The tab to insert.
    ///   - index: The index to insert, or `nil` to insert after the selected tab.
    func insert(_ tab: EditorTab, at index: Int? = nil) {

        let index = index ?? self.selectedTab.flatMap { self.tabs.firstIndex(of: $0) }.map { $0 + 1 } ?? self.tabs.endIndex

        self.tabs.insert(tab, at: min(index, self.tabs.endIndex))
        self.reloadTabBar()
    }


    /// Removes the tab from the group without closing its document.
    ///
    /// - Parameter tab: The tab to remove.
    func remove(_ tab: EditorTab) {

        guard let index = self.tabs.firstIndex(of: tab) else { return }

        self.tabs.remove(at: index)

        if tab.viewController === self.displayedViewController {
            self.removeDisplayedViewController()
        }
        tab.viewController?.removeFromParent()

        if tab === self.selectedTab {
            // select the next tab, or the previous one for the last tab
            self.selectedTab = self.tabs[safe: index] ?? self.tabs.last
            self.displaySelectedTab()
        }

        self.reloadTabBar()
    }


    /// Selects the given tab and displays its content.
    ///
    /// - Parameter tab: The tab to select.
    func select(_ tab: EditorTab) {

        assert(self.tabs.contains(tab))

        guard tab !== self.selectedTab || tab.viewController?.view.superview == nil else { return }

        self.selectedTab = tab
        self.displaySelectedTab()
        self.reloadTabBar()
    }


    /// Selects the tab next to the selected one.
    ///
    /// - Parameter forward: Whether to move forward.
    func selectAdjacentTab(forward: Bool) {

        guard
            self.tabs.count > 1,
            let selectedTab,
            let index = self.tabs.firstIndex(of: selectedTab)
        else { return }

        let newIndex = (index + (forward ? 1 : -1) + self.tabs.count) % self.tabs.count
        self.select(self.tabs[newIndex])
        self.focusContent()
    }


    /// Selects the tab at the given index.
    func selectTab(at index: Int) {

        guard let tab = self.tabs[safe: index] else { return }

        self.select(tab)
        self.focusContent()
    }


    /// Replaces the document of the tab and invalidates its cached view.
    ///
    /// - Parameters:
    ///   - document: The new document.
    ///   - tab: The tab to update.
    func replaceDocument(_ document: DataDocument, in tab: EditorTab) {

        if tab.viewController === self.displayedViewController {
            self.removeDisplayedViewController()
        }
        tab.viewController?.removeFromParent()
        tab.document = document

        if tab === self.selectedTab {
            self.displaySelectedTab()
        }
        self.reloadTabBar()
    }


    /// Updates the tab bar to reflect the current tab state.
    func reloadTabBar() {

        let items = self.tabs.map { tab in
            EditorTabBarItem(id: tab.id,
                             title: tab.title,
                             toolTip: tab.fileURL?.path(percentEncoded: false),
                             fileType: tab.document?.fileType.flatMap(UTType.init) ?? tab.fileURL.flatMap { UTType(filenameExtension: $0.pathExtension) },
                             isTemporary: tab.isTemporary,
                             isEdited: tab.isEdited)
        }
        self.tabBar.update(items: items, selectedID: self.selectedTab?.id)
    }


    /// Discards the cached editor of the hidden tab to save memory, keeping its selection and scroll position.
    ///
    /// - Parameter tab: The tab whose editor to unload.
    func unloadViewController(of tab: EditorTab) {
        
        guard
            tab !== self.selectedTab,
            let viewController = tab.viewController
        else { return }
        
        if let textView = (viewController as? DocumentViewController)?.focusedTextView,
           let clipView = textView.enclosingScrollView?.contentView
        {
            tab.savedEditorState = .init(selectedRanges: textView.selectedRanges.map(\.rangeValue),
                                         scrollOrigin: clipView.bounds.origin)
        }
        
        viewController.removeFromParent()
        tab.viewController = nil
    }
    
    
    /// Moves the keyboard focus to the content of the selected tab.
    func focusContent() {

        guard let window = self.viewIfLoaded?.window else { return }

        if let textView = self.documentViewController?.focusedTextView {
            window.makeFirstResponderDiscardingMarkedText(textView)
        } else if let view = self.displayedViewController?.view {
            window.makeFirstResponder(view)
        }
    }


    // MARK: Tab Bar Delegate

    func tabBar(_ tabBar: EditorTabBar, didSelectTab id: UUID) {

        guard let tab = self.tab(id: id) else { return }

        self.select(tab)
        self.editorArea?.focus(self)
        self.focusContent()
    }


    func tabBar(_ tabBar: EditorTabBar, didCloseTab id: UUID) {

        guard let tab = self.tab(id: id) else { return }

        self.editorArea?.close(tab, in: self)
    }


    func tabBar(_ tabBar: EditorTabBar, didDoubleClickTab id: UUID) {

        guard let tab = self.tab(id: id) else { return }

        self.editorArea?.keepOpen(tab, in: self)
    }


    func tabBar(_ tabBar: EditorTabBar, moveTab id: UUID, to index: Int) {

        guard
            let tab = self.tab(id: id),
            let currentIndex = self.tabs.firstIndex(of: tab)
        else { return }

        self.tabs.remove(at: currentIndex)
        self.tabs.insert(tab, at: min(index, self.tabs.endIndex))
        self.reloadTabBar()
        self.editorArea?.invalidateDocumentRestorableState()
    }


    func tabBar(_ tabBar: EditorTabBar, dropTab id: UUID, atWindowLocation location: NSPoint) -> Bool {

        guard let tab = self.tab(id: id) else { return false }

        return self.editorArea?.moveTab(tab, from: self, toWindowLocation: location) ?? false
    }


    /// The index in the tab bar for the given point in the window.
    ///
    /// - Parameter location: The location in the window coordinates.
    /// - Returns: The index to insert a tab.
    func tabIndex(at location: NSPoint) -> Int {

        self.tabBar.tabIndex(at: location)
    }


    func tabBar(_ tabBar: EditorTabBar, menuForTab id: UUID) -> NSMenu? {

        guard let tab = self.tab(id: id) else { return nil }

        return self.editorArea?.contextMenu(for: tab, in: self)
    }


    func tabBarDidClickBackground(_ tabBar: EditorTabBar) {

        self.editorArea?.focus(self)
        self.focusContent()
    }


    // MARK: Private Methods
    
    private static let signposter = OSSignposter(subsystem: Bundle.main.bundleIdentifier ?? "CotEditor", category: "EditorTabs")
    
    
    /// Displays the content of the selected tab in the container view.
    private func displaySelectedTab() {
        
        guard self.isViewLoaded else { return }
        
        let signpostState = Self.signposter.beginInterval("Display Tab")
        defer { Self.signposter.endInterval("Display Tab", signpostState) }
        
        let viewController: NSViewController
        var isNewEditor = false
        if let tab = self.selectedTab {
            if tab.document == nil {
                // load the restored placeholder lazily
                self.editorArea?.loadDocument(of: tab, in: self)
            }

            if let cached = tab.viewController {
                viewController = cached
            } else {
                viewController = ContentViewController.viewController(document: tab.document)
                tab.viewController = viewController
                isNewEditor = true
            }
        } else {
            if self.emptyViewController == nil {
                self.emptyViewController = ContentViewController.viewController(document: nil)
            }
            viewController = self.emptyViewController!
        }

        guard viewController !== self.displayedViewController || viewController.view.superview !== self.containerView else { return }

        self.removeDisplayedViewController()

        if viewController.parent !== self {
            self.addChild(viewController)
        }

        let view = viewController.view
        view.translatesAutoresizingMaskIntoConstraints = false
        self.containerView.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: self.containerView.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: self.containerView.trailingAnchor),
            view.topAnchor.constraint(equalTo: self.containerView.topAnchor),
            view.bottomAnchor.constraint(equalTo: self.containerView.bottomAnchor),
        ])
        self.displayedViewController = viewController
        
        if isNewEditor, let viewController = viewController as? DocumentViewController {
            // apply the document state to the new editor
            viewController.document.editorViewController = viewController
            viewController.document.makeWindowControllers()
            
            // restore the state of the unloaded editor
            if let state = self.selectedTab?.savedEditorState, let textView = viewController.focusedTextView {
                let length = textView.string.utf16.count
                let ranges = state.selectedRanges.filter { $0.upperBound <= length }
                if !ranges.isEmpty {
                    textView.selectedRanges = ranges.map(NSValue.init(range:))
                }
                view.layoutSubtreeIfNeeded()
                textView.enclosingScrollView?.contentView.scroll(to: state.scrollOrigin)
                textView.enclosingScrollView?.reflectScrolledClipView(textView.enclosingScrollView!.contentView)
                self.selectedTab?.savedEditorState = nil
            }
        }
        
        self.editorArea?.groupDidChangeSelection(self)
    }


    /// Removes the currently displayed view from the container without discarding its view controller.
    private func removeDisplayedViewController() {

        guard let viewController = self.displayedViewController else { return }

        // keep the focus in the window when the view having the focus is removed
        if let firstResponder = self.view.window?.firstResponder as? NSView,
           firstResponder.isDescendant(of: viewController.view)
        {
            self.view.window?.makeFirstResponder(nil)
        }

        viewController.view.removeFromSuperview()
        self.displayedViewController = nil
    }
}
