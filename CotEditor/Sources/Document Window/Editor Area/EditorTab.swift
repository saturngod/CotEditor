//
//  EditorTab.swift
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

/// How a document should be presented in the editor area of a folder window.
enum EditorOpenDisposition: Sendable {

    /// Reuses the temporary tab of the focused group or creates one (single click in the file browser).
    case temporary

    /// Opens in a permanent tab of the focused group (double click in the file browser).
    case permanent

    /// Always opens in a new permanent tab of the focused group.
    case newTab

    /// Opens in a permanent tab of another editor group, creating one if needed.
    case otherGroup

    /// Replaces the document of the selected tab in the focused group (history navigation).
    case replaceCurrent
}


/// A tab in an editor group of a folder window.
///
/// A tab holds the document it presents and caches the view controller for the document
/// so that switching tabs only swaps views without rebuilding the editor.
@MainActor final class EditorTab {

    // MARK: Public Properties

    let id = UUID()

    /// The presented document, or `nil` while the tab is a restored placeholder not yet loaded.
    var document: DataDocument? {

        didSet {
            guard document !== oldValue else { return }
            self.viewController = nil
            self.placeholderURL = nil
        }
    }

    /// The file URL to open when a restored placeholder tab is selected for the first time.
    var placeholderURL: URL?

    /// Whether the tab is temporary (shown in italic and replaced by the next navigation).
    var isTemporary: Bool

    /// Whether the document should be opened as plain text when it is reloaded.
    var opensAsPlainText: Bool

    /// The navigation history of this tab.
    var history = DocumentHistory()

    /// The cached content view controller for the document.
    var viewController: NSViewController?
    
    /// The edited state currently displayed in the tab bar.
    var displayedEditedState = false
    
    /// The order when the tab was displayed last, used to unload editors of tabs not used for a while.
    var lastDisplayedOrder: UInt64 = 0
    
    /// The editor state saved when the cached view controller was unloaded.
    var savedEditorState: SavedEditorState?
    
    
    struct SavedEditorState {
        
        var selectedRanges: [NSRange]
        var scrollOrigin: NSPoint
    }


    // MARK: Lifecycle

    init(document: DataDocument?, isTemporary: Bool, opensAsPlainText: Bool = false) {

        self.document = document
        self.isTemporary = isTemporary
        self.opensAsPlainText = opensAsPlainText
    }


    // MARK: Public Methods

    /// The file URL the tab represents.
    var fileURL: URL? {

        self.document?.fileURL ?? self.placeholderURL
    }


    /// The title to display in the tab bar.
    var title: String {

        if let document {
            return document.fileURL?.lastPathComponent ?? document.displayName
        }

        return self.placeholderURL?.lastPathComponent ?? ""
    }


    /// Whether the presented document has unsaved changes.
    var isEdited: Bool {

        self.document?.isDocumentEdited ?? false
    }
}


extension EditorTab: Equatable {
    
    nonisolated static func == (lhs: EditorTab, rhs: EditorTab) -> Bool {
        
        lhs === rhs
    }
}
