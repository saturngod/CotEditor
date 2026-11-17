//
//  EditorAreaTests.swift
//  Tests
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
import Testing
@testable import CotEditor

@MainActor @Suite(.serialized) struct EditorAreaTests {

    @Test func opensFilesInTabs() async throws {

        let (document, folderURL) = try self.makeFolderDocument()
        defer {
            document.close()
            try? FileManager.default.removeItem(at: folderURL)
        }

        let editorArea = try #require(self.editorArea(of: document))
        #expect(editorArea.groups.count == 1)
        #expect(editorArea.allTabs.isEmpty)

        let aURL = folderURL.appending(component: "a.txt")
        let bURL = folderURL.appending(component: "b.txt")

        // single click reuses the temporary tab
        #expect(await document.openDocument(at: aURL))
        #expect(await document.openDocument(at: bURL))
        #expect(editorArea.allTabs.count == 1)
        #expect(editorArea.currentTab?.isTemporary == true)
        #expect(editorArea.currentDocument?.fileURL == bURL)

        // double click opens a permanent tab
        #expect(await document.openDocument(at: aURL, disposition: .permanent))
        #expect(editorArea.allTabs.count == 2)
        #expect(editorArea.currentTab?.isTemporary == false)
        #expect(editorArea.currentDocument?.fileURL == aURL)
        #expect(editorArea.documentViewController?.document.fileURL == aURL)

        // switching tabs keeps the cached editor
        let group = try #require(editorArea.focusedGroup)
        let aEditor = try #require(editorArea.documentViewController)
        group.selectAdjacentTab(forward: false)
        #expect(editorArea.currentDocument?.fileURL == bURL)
        group.selectAdjacentTab(forward: true)
        #expect(editorArea.documentViewController === aEditor)
    }


    @Test func splitsEditor() async throws {

        let (document, folderURL) = try self.makeFolderDocument()
        defer {
            document.close()
            try? FileManager.default.removeItem(at: folderURL)
        }

        let editorArea = try #require(self.editorArea(of: document))
        let aURL = folderURL.appending(component: "a.txt")

        #expect(await document.openDocument(at: aURL, disposition: .permanent))
        let firstGroup = try #require(editorArea.focusedGroup)

        // the new group shows the same document with another editor
        editorArea.openSplitTextView(nil)
        #expect(editorArea.groups.count == 2)
        let secondGroup = try #require(editorArea.focusedGroup)
        #expect(secondGroup !== firstGroup)
        #expect(secondGroup.selectedTab?.document === firstGroup.selectedTab?.document)
        #expect(secondGroup.documentViewController !== firstGroup.documentViewController)

        // a file opened in the other group
        let cURL = folderURL.appending(component: "sub/c.txt")
        #expect(await document.openDocument(at: cURL, disposition: .otherGroup))
        #expect(editorArea.groups.count == 2)
        #expect(editorArea.focusedGroup === firstGroup)
        #expect(editorArea.currentDocument?.fileURL == cURL)
    }


    @Test func restoresTabs() async throws {

        let (document, folderURL) = try self.makeFolderDocument()
        defer { try? FileManager.default.removeItem(at: folderURL) }
        
        let editorArea = try #require(self.editorArea(of: document))
        #expect(await document.openDocument(at: folderURL.appending(component: "a.txt"), disposition: .permanent))
        #expect(await document.openDocument(at: folderURL.appending(component: "b.txt"), disposition: .permanent))
        let state = try #require(editorArea.encodedState())
        
        // close the files so that another window can open them
        document.close()

        let (otherDocument, _) = try self.makeFolderDocument(at: folderURL)
        defer { otherDocument.close() }
        let otherArea = try #require(self.editorArea(of: otherDocument))

        #expect(otherArea.restore(from: state, in: folderURL))
        #expect(otherArea.allTabs.map(\.fileURL?.lastPathComponent) == ["a.txt", "b.txt"])
        #expect(otherArea.currentDocument?.fileURL?.lastPathComponent == "b.txt")
        // non-selected tabs load lazily
        #expect(otherArea.allTabs.first?.document == nil)
    }


    // MARK: Private Methods

    /// Makes a folder document with some files and its window.
    private func makeFolderDocument(at existingURL: URL? = nil) throws -> (DirectoryDocument, URL) {

        let folderURL: URL
        if let existingURL {
            folderURL = existingURL
        } else {
            folderURL = URL.temporaryDirectory
                .appending(component: "EditorAreaTests-\(UUID().uuidString)", directoryHint: .isDirectory)
                .resolvingSymlinksInPath()
            try FileManager.default.createDirectory(at: folderURL.appending(component: "sub"), withIntermediateDirectories: true)
            try "a".write(to: folderURL.appending(component: "a.txt"), atomically: true, encoding: .utf8)
            try "b".write(to: folderURL.appending(component: "b.txt"), atomically: true, encoding: .utf8)
            try "c".write(to: folderURL.appending(component: "sub/c.txt"), atomically: true, encoding: .utf8)
        }

        let typeName = try NSDocumentController.shared.typeForContents(of: folderURL)
        let document = try #require(try NSDocumentController.shared.makeDocument(withContentsOf: folderURL, ofType: typeName) as? DirectoryDocument)
        NSDocumentController.shared.addDocument(document)
        document.makeWindowControllers()

        return (document, folderURL)
    }


    private func editorArea(of document: DirectoryDocument) -> EditorAreaViewController? {

        (document.windowControllers.first?.contentViewController as? WindowContentViewController)?.editorArea
    }
}
