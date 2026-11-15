//
//  ContentViewController.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2024-05-04.
//
//  ---------------------------------------------------------------------------
//
//  © 2024-2026 1024jp
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
import Defaults
import SwiftUI

final class ContentViewController: NSViewController, NSSplitViewDelegate {
    
    // MARK: Public Properties
    
    var document: DataDocument?  { didSet { self.updateDocument(from: oldValue) } }
    
    private(set) var hostedViewController: NSViewController
    
    /// Whether the terminal pane is currently visible.
    var isTerminalShown: Bool  { self.terminalViewController?.viewIfLoaded?.isHidden == false }
    
    
    // MARK: Private Properties
    
    private static let minimumEditorHeight: CGFloat = 80
    private static let minimumTerminalHeight: CGFloat = 80
    
    @ViewLoading private var splitView: NSSplitView
    @ViewLoading private var hostedContainerView: NSView
    private var terminalViewController: TerminalViewController?
    
    private var themeObservers: Set<AnyCancellable> = []
    
    
    // MARK: Lifecycle
    
    init(document: DataDocument?) {
        
        self.document = document
        self.hostedViewController = Self.viewController(document: document)
        
        super.init(nibName: nil, bundle: nil)
        
        self.addChild(self.hostedViewController)
    }
    
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func loadView() {
        
        // -> The hosted view is wrapped in a split view to place the terminal below it.
        let hostedContainerView = NSView()
        hostedContainerView.embedSubview(self.hostedViewController.view)
        self.hostedContainerView = hostedContainerView
        
        let splitView = NSSplitView()
        splitView.isVertical = false
        splitView.dividerStyle = .thin
        splitView.delegate = self
        splitView.addArrangedSubview(hostedContainerView)
        self.splitView = splitView
        
        let view = NSView()
        view.embedSubview(splitView)
        
        self.view = view
    }
    
    
    override func viewWillAppear() {
        
        super.viewWillAppear()
        
        self.themeObservers = [
            NotificationCenter.default.publisher(for: DocumentViewController.didChangeThemeNotification)
                .filter { [weak self] in ($0.object as? NSViewController) === self?.hostedViewController }
                .sink { [weak self] _ in self?.invalidateTerminalTheme() },
            UserDefaults.standard.publisher(for: .theme)
                .sink { [weak self] _ in self?.invalidateTerminalTheme() },
            self.view.publisher(for: \.effectiveAppearance)
                .sink { [weak self] _ in self?.invalidateTerminalTheme() },
        ]
    }
    
    
    override func viewDidDisappear() {
        
        super.viewDidDisappear()
        
        self.themeObservers.removeAll()
    }
    
    
    // MARK: Split View Delegate
    
    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        
        Self.minimumEditorHeight
    }
    
    
    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        
        max(Self.minimumEditorHeight, splitView.bounds.height - splitView.dividerThickness - Self.minimumTerminalHeight)
    }
    
    
    func splitView(_ splitView: NSSplitView, shouldAdjustSizeOfSubview view: NSView) -> Bool {
        
        // keep the terminal height when the window is resized
        view === self.hostedContainerView
    }
    
    
    func splitViewDidResizeSubviews(_ notification: Notification) {
        
        // store the terminal height only when the user drags the divider
        guard
            notification.userInfo?["NSSplitViewDividerIndex"] != nil,
            let terminalView = self.terminalViewController?.viewIfLoaded,
            !terminalView.isHidden
        else { return }
        
        UserDefaults.standard[.terminalHeight] = terminalView.frame.height
    }
    
    
    // MARK: Public Methods
    
    /// Shows the terminal pane and moves the keyboard focus to it.
    ///
    /// - Parameter workingDirectory: The directory where the shell starts when a new terminal session is created.
    func showTerminal(workingDirectory: URL?) {
        
        let terminalViewController: TerminalViewController
        if let controller = self.terminalViewController {
            terminalViewController = controller
        } else {
            terminalViewController = TerminalViewController(workingDirectory: workingDirectory, palette: self.terminalPalette)
            terminalViewController.terminationHandler = { [weak self] in self?.closeTerminal() }
            self.addChild(terminalViewController)
            self.splitView.addArrangedSubview(terminalViewController.view)
            self.terminalViewController = terminalViewController
        }
        
        if terminalViewController.view.isHidden || terminalViewController.view.frame.height < Self.minimumTerminalHeight {
            terminalViewController.view.isHidden = false
            self.splitView.layoutSubtreeIfNeeded()
            
            let height = max(UserDefaults.standard[.terminalHeight], Self.minimumTerminalHeight)
            let position = max(Self.minimumEditorHeight, self.splitView.bounds.height - self.splitView.dividerThickness - height)
            self.splitView.setPosition(position, ofDividerAt: 0)
        }
        
        terminalViewController.focus()
    }
    
    
    /// Hides the terminal pane while keeping the shell session.
    func hideTerminal() {
        
        guard let terminalView = self.terminalViewController?.viewIfLoaded, !terminalView.isHidden else { return }
        
        terminalView.isHidden = true
        self.splitView.adjustSubviews()
    }
    
    
    /// Whether the terminal currently has the keyboard focus.
    var isTerminalFocused: Bool {
        
        self.isTerminalShown && self.terminalViewController?.hasFocus == true
    }
    
    
    
    // MARK: Private Methods
    
    /// Discards the terminal session and its pane.
    private func closeTerminal() {
        
        guard let terminalViewController else { return }
        
        let hadFocus = terminalViewController.hasFocus
        
        terminalViewController.viewIfLoaded?.removeFromSuperview()
        terminalViewController.removeFromParent()
        self.terminalViewController = nil
        self.splitView.adjustSubviews()
        
        if hadFocus {
            self.view.window?.makeFirstResponder((self.hostedViewController as? DocumentViewController)?.focusedTextView)
        }
    }
    
    
    /// The terminal colors that match the theme of the current document.
    private var terminalPalette: TerminalPalette {
        
        let theme = (self.hostedViewController as? DocumentViewController)?.theme
            ?? (try? ThemeManager.shared.setting(name: ThemeManager.shared.userDefaultSettingName(inDarkMode: self.view.effectiveAppearance.isDark)))
            ?? Theme()
        
        return TerminalPalette(theme: theme)
    }
    
    
    /// Updates the terminal colors to match the current theme.
    private func invalidateTerminalTheme() {
        
        self.terminalViewController?.palette = self.terminalPalette
    }
    
    
    /// Updates the hosted view controller when the document changes.
    ///
    /// - Parameter oldDocument: The previous document.
    private func updateDocument(from oldDocument: DataDocument?) {
        
        guard oldDocument != self.document else { return }
        
        // remove only the hosted view controller to preserve accessories such as the status bar
        // -> Split view item accessory controllers can be attached as children (2026-05, macOS 26).
        self.hostedViewController.viewIfLoaded?.removeFromSuperview()
        self.hostedViewController.removeFromParent()
        
        self.hostedViewController = Self.viewController(document: self.document)
        self.addChild(self.hostedViewController)
        if self.isViewLoaded {
            self.hostedContainerView.embedSubview(self.hostedViewController.view)
        }
        
        self.invalidateTerminalTheme()
    }
    
    
    /// Creates a new view controller with the passed-in document.
    ///
    /// - Parameter document: The represented document.
    /// - Returns: A view controller.
    private static func viewController(document: DataDocument?) -> NSViewController {
        
        switch document {
            case let document as TextDocument:
                DocumentViewController(document: document)
            case let document as PreviewDocument:
                Self.hostingController(rootView: FilePreviewView(item: document))
            case .none:
                Self.hostingController(rootView: NoDocumentView())
            default:
                preconditionFailure()
        }
    }
    
    
    /// Creates a hosting controller that doesn’t propagate the SwiftUI content’s ideal size to the split view pane layout.
    ///
    /// - Parameter rootView: The SwiftUI view to host.
    /// - Returns: A hosting controller.
    private static func hostingController(rootView: some View) -> NSViewController {
        
        let controller = NSHostingController(rootView: rootView)
        controller.sizingOptions = []
        
        return controller
    }
}


private extension NSView {
    
    /// Adds a subview constrained to fill the receiver.
    ///
    /// - Parameter subview: The subview to embed.
    func embedSubview(_ subview: NSView) {
        
        subview.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(subview)
        
        NSLayoutConstraint.activate([
            subview.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            subview.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            subview.topAnchor.constraint(equalTo: self.topAnchor),
            subview.bottomAnchor.constraint(equalTo: self.bottomAnchor),
        ])
    }
}
