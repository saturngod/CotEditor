//
//  EditorTabBar.swift
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

@MainActor protocol EditorTabBarDelegate: AnyObject {

    func tabBar(_ tabBar: EditorTabBar, didSelectTab id: UUID)
    func tabBar(_ tabBar: EditorTabBar, didCloseTab id: UUID)
    func tabBar(_ tabBar: EditorTabBar, didDoubleClickTab id: UUID)
    func tabBar(_ tabBar: EditorTabBar, moveTab id: UUID, to index: Int)
    func tabBar(_ tabBar: EditorTabBar, dropTab id: UUID, atWindowLocation location: NSPoint) -> Bool
    func tabBar(_ tabBar: EditorTabBar, menuForTab id: UUID) -> NSMenu?
    func tabBarDidClickBackground(_ tabBar: EditorTabBar)
}


/// The display information of a tab in the tab bar.
struct EditorTabBarItem: Equatable {

    var id: UUID
    var title: String
    var toolTip: String?
    var fileType: UTType?
    var isTemporary: Bool
    var isEdited: Bool
}


/// A lightweight AppKit tab bar for an editor group.
///
/// Tab item views are reused by tab identifier and laid out by frame without Auto Layout,
/// so that updating a single tab doesn't relayout or redraw the others.
final class EditorTabBar: NSView {

    // MARK: Public Properties

    static let barHeight: CGFloat = 30

    weak var delegate: (any EditorTabBarDelegate)?

    /// Whether the editor group owning the tab bar has the focus.
    var isActive = true {

        didSet {
            guard isActive != oldValue else { return }
            self.itemViews.values.forEach { $0.isActive = isActive }
        }
    }


    // MARK: Private Properties

    private static let minimumTabWidth: CGFloat = 110
    private static let maximumTabWidth: CGFloat = 260
    private static let horizontalInset: CGFloat = 6

    private var items: [EditorTabBarItem] = []
    private var selectedID: UUID?
    private var itemViews: [UUID: EditorTabItemView] = [:]

    private let scrollView = NSScrollView()
    private let documentView = FlippedView()


    // MARK: Lifecycle

    override init(frame frameRect: NSRect) {

        super.init(frame: frameRect)

        self.scrollView.drawsBackground = false
        self.scrollView.hasHorizontalScroller = false
        self.scrollView.hasVerticalScroller = false
        self.scrollView.horizontalScrollElasticity = .allowed
        self.scrollView.verticalScrollElasticity = .none
        self.scrollView.automaticallyAdjustsContentInsets = false
        self.scrollView.documentView = self.documentView
        self.addSubview(self.scrollView)

        self.setAccessibilityElement(true)
        self.setAccessibilityRole(.tabGroup)
        self.setAccessibilityLabel(String(localized: "Editor Tabs", table: "Document", comment: "accessibility label for the editor tab bar"))
    }


    @available(*, unavailable)
    required init?(coder: NSCoder) {

        fatalError("init(coder:) has not been implemented")
    }


    // MARK: View Methods

    override var isFlipped: Bool  { true }


    override var mouseDownCanMoveWindow: Bool  { false }


    override func layout() {

        super.layout()

        self.scrollView.frame = self.barRect
        self.layoutItems(animated: false)
    }


    override func draw(_ dirtyRect: NSRect) {

        // separator at the bottom
        let lineWidth = 1 / (self.window?.backingScaleFactor ?? 2)
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: self.bounds.maxY - lineWidth, width: self.bounds.width, height: lineWidth).fill()
    }


    override func mouseDown(with event: NSEvent) {

        if event.clickCount == 2 {
            // double click on the empty area: follow the system preference like the title bar
            self.window?.performZoom(nil)
            return
        }

        self.delegate?.tabBarDidClickBackground(self)
    }


    override func accessibilityChildren() -> [Any]? {

        self.items.compactMap { self.itemViews[$0.id] }
    }


    // MARK: Public Methods

    /// Updates the tabs to display.
    ///
    /// - Parameters:
    ///   - items: The tab items in order.
    ///   - selectedID: The identifier of the selected tab.
    func update(items: [EditorTabBarItem], selectedID: UUID?) {

        let needsLayout = items.map(\.id) != self.items.map(\.id)

        // remove obsolete views
        let ids = Set(items.map(\.id))
        for (id, view) in self.itemViews where !ids.contains(id) {
            view.removeFromSuperview()
            self.itemViews[id] = nil
        }

        // add or update views
        for item in items {
            let view: EditorTabItemView
            if let existing = self.itemViews[item.id] {
                view = existing
            } else {
                view = EditorTabItemView(id: item.id)
                view.tabBar = self
                view.isActive = self.isActive
                self.documentView.addSubview(view)
                self.itemViews[item.id] = view
            }
            if view.item != item {
                view.item = item
            }
            view.isSelected = (item.id == selectedID)
        }

        self.items = items
        self.selectedID = selectedID

        if needsLayout {
            self.layoutItems(animated: false)
        }
        self.scrollSelectedTabToVisible()
    }


    // MARK: Fileprivate Methods

    fileprivate func select(_ view: EditorTabItemView) {

        self.delegate?.tabBar(self, didSelectTab: view.id)
    }


    fileprivate func close(_ view: EditorTabItemView) {

        self.delegate?.tabBar(self, didCloseTab: view.id)
    }


    fileprivate func doubleClick(_ view: EditorTabItemView) {

        self.delegate?.tabBar(self, didDoubleClickTab: view.id)
    }


    fileprivate func menu(for view: EditorTabItemView) -> NSMenu? {

        self.delegate?.tabBar(self, menuForTab: view.id)
    }


    /// Tracks dragging a tab to reorder it in the bar or to move it to another editor group.
    ///
    /// - Parameters:
    ///   - view: The tab item view being dragged.
    ///   - event: The mouse down event.
    /// - Returns: `true` if the tab was dragged.
    fileprivate func trackDragging(_ view: EditorTabItemView, with event: NSEvent) -> Bool {

        guard let window = self.window else { return false }

        let startPoint = self.documentView.convert(event.locationInWindow, from: nil)
        let startX = view.frame.minX
        var isDragging = false
        var lastLocation = event.locationInWindow

        while let nextEvent = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let point = self.documentView.convert(nextEvent.locationInWindow, from: nil)
            let deltaX = point.x - startPoint.x
            let deltaY = point.y - startPoint.y
            lastLocation = nextEvent.locationInWindow

            if nextEvent.type == .leftMouseUp { break }

            if !isDragging {
                guard abs(deltaX) > 4 || abs(deltaY) > 4 else { continue }
                isDragging = true
                view.layer?.zPosition = 1
                self.select(view)
            }

            let maxX = max(0, self.documentView.bounds.width - view.frame.width)
            view.frame.origin.x = (startX + deltaX).clamped(to: 0...maxX)

            // move other tabs to make a room
            let targetIndex = self.targetIndex(for: view)
            let width = view.frame.width
            var index = 0
            for item in self.items where item.id != view.id {
                if index == targetIndex { index += 1 }
                self.itemViews[item.id]?.animator().frame.origin.x = Self.horizontalInset + CGFloat(index) * width
                index += 1
            }
        }

        view.layer?.zPosition = 0

        guard isDragging else { return false }

        // drop on another editor group
        if !self.bounds.contains(self.convert(lastLocation, from: nil)),
           self.delegate?.tabBar(self, dropTab: view.id, atWindowLocation: lastLocation) == true
        {
            return true
        }

        let targetIndex = self.targetIndex(for: view)
        if let currentIndex = self.items.firstIndex(where: { $0.id == view.id }), currentIndex != targetIndex {
            self.delegate?.tabBar(self, moveTab: view.id, to: targetIndex)
        }
        self.layoutItems(animated: true)

        return true
    }


    /// The index to insert a tab dropped at the given location.
    ///
    /// - Parameter location: The location in the window coordinates.
    /// - Returns: The insertion index.
    func tabIndex(at location: NSPoint) -> Int {

        let point = self.documentView.convert(location, from: nil)

        guard self.convert(location, from: nil).y >= self.barRect.minY - 4, self.tabWidth > 0 else { return self.items.count }

        return Int(((point.x - Self.horizontalInset) / self.tabWidth).rounded()).clamped(to: 0...self.items.count)
    }


    // MARK: Private Methods

    /// The rectangle where tabs are placed.
    private var barRect: NSRect {

        NSRect(x: 0, y: self.bounds.height - Self.barHeight, width: self.bounds.width, height: Self.barHeight)
    }


    /// The width for each tab.
    private var tabWidth: CGFloat {

        guard !self.items.isEmpty else { return 0 }

        let availableWidth = self.bounds.width - 2 * Self.horizontalInset

        return (availableWidth / CGFloat(self.items.count))
            .clamped(to: Self.minimumTabWidth...Self.maximumTabWidth)
    }


    /// Places tab item views by frame.
    ///
    /// - Parameter animated: Whether to animate the change.
    private func layoutItems(animated: Bool) {

        let width = self.tabWidth
        let height = Self.barHeight
        let contentWidth = max(self.scrollView.bounds.width, 2 * Self.horizontalInset + width * CGFloat(self.items.count))
        self.documentView.frame = NSRect(x: 0, y: 0, width: contentWidth, height: height)

        for (index, item) in self.items.enumerated() {
            guard let view = self.itemViews[item.id] else { continue }

            let frame = NSRect(x: Self.horizontalInset + CGFloat(index) * width, y: 0, width: width, height: height)
            if animated {
                view.animator().frame = frame
            } else {
                view.frame = frame
            }
            view.showsLeadingSeparator = index > 0
        }
    }


    /// Returns the index where the dragged view would be dropped.
    private func targetIndex(for view: EditorTabItemView) -> Int {

        let width = max(self.tabWidth, 1)
        let index = Int(((view.frame.midX - Self.horizontalInset) / width).rounded(.down))

        return index.clamped(to: 0...(self.items.count - 1))
    }


    /// Scrolls the bar so that the selected tab is visible.
    private func scrollSelectedTabToVisible() {

        guard let selectedID, let view = self.itemViews[selectedID] else { return }

        self.documentView.scrollToVisible(view.frame)
    }
}


// MARK: - Tab Item View

private final class EditorTabItemView: NSView {

    // MARK: Properties

    let id: UUID
    weak var tabBar: EditorTabBar?

    var item: EditorTabBarItem? {

        didSet { self.applyItem() }
    }

    var isSelected = false {

        didSet {
            guard isSelected != oldValue else { return }
            self.updateAppearance()
        }
    }

    var isActive = true {

        didSet {
            guard isActive != oldValue else { return }
            self.updateAppearance()
        }
    }

    var showsLeadingSeparator = false {

        didSet {
            guard showsLeadingSeparator != oldValue else { return }
            self.needsDisplay = true
        }
    }


    // MARK: Private Properties

    private static var iconCache: [String: NSImage] = [:]

    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let closeButton: NSButton
    private var isHovered = false {

        didSet {
            guard isHovered != oldValue else { return }
            self.updateAppearance()
        }
    }


    // MARK: Lifecycle

    init(id: UUID) {

        self.id = id

        let closeImage = NSImage(systemSymbolName: "xmark", accessibilityDescription: String(localized: "Close Tab", table: "Document", comment: "accessibility label for the close button in an editor tab"))!
            .withSymbolConfiguration(.init(pointSize: 9, weight: .semibold))!
        self.closeButton = NSButton(image: closeImage, target: nil, action: nil)

        super.init(frame: .zero)

        self.wantsLayer = true
        self.layerContentsRedrawPolicy = .onSetNeedsDisplay

        self.closeButton.isBordered = false
        self.closeButton.bezelStyle = .accessoryBarAction
        self.closeButton.contentTintColor = .secondaryLabelColor
        self.closeButton.target = self
        self.closeButton.action = #selector(closeTab)
        self.closeButton.toolTip = String(localized: "Close Tab", table: "Document", comment: "tooltip for the close button in an editor tab")

        self.iconView.imageScaling = .scaleProportionallyDown
        self.iconView.setAccessibilityElement(false)

        self.titleField.lineBreakMode = .byTruncatingMiddle
        self.titleField.alignment = .center
        self.titleField.setAccessibilityElement(false)

        self.addSubview(self.iconView)
        self.addSubview(self.titleField)
        self.addSubview(self.closeButton)

        self.setAccessibilityElement(true)
        self.setAccessibilityRole(.radioButton)

        self.updateAppearance()
    }


    @available(*, unavailable)
    required init?(coder: NSCoder) {

        fatalError("init(coder:) has not been implemented")
    }


    // MARK: View Methods

    override var isFlipped: Bool  { true }


    override var mouseDownCanMoveWindow: Bool  { false }


    override func updateTrackingAreas() {

        super.updateTrackingAreas()

        if self.trackingAreas.isEmpty {
            self.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self))
        }
    }


    override func mouseEntered(with event: NSEvent) {

        self.isHovered = true
    }


    override func mouseExited(with event: NSEvent) {

        self.isHovered = false
    }


    override func layout() {

        super.layout()

        let bounds = self.bounds
        let buttonSize: CGFloat = 16
        let iconSize: CGFloat = 16
        let midY = bounds.midY

        self.closeButton.frame = NSRect(x: 8, y: midY - buttonSize / 2, width: buttonSize, height: buttonSize)

        // center icon and title together
        let titleWidth = min(self.titleField.intrinsicContentSize.width, bounds.width - 2 * (8 + buttonSize + 4) - iconSize - 4)
        let contentWidth = iconSize + 4 + max(0, titleWidth)
        let originX = max(8 + buttonSize + 4, (bounds.width - contentWidth) / 2)
        let titleHeight = self.titleField.intrinsicContentSize.height

        self.iconView.frame = NSRect(x: originX, y: midY - iconSize / 2, width: iconSize, height: iconSize)
        self.titleField.frame = NSRect(x: originX + iconSize + 4, y: midY - titleHeight / 2, width: max(0, titleWidth), height: titleHeight)
    }


    override func draw(_ dirtyRect: NSRect) {

        let lineWidth = 1 / (self.window?.backingScaleFactor ?? 2)

        if self.isSelected || self.isHovered {
            let alpha: CGFloat = switch (self.isSelected, self.isActive) {
                case (true, true): 0.12
                case (true, false): 0.07
                default: 0.05
            }
            NSColor.labelColor.withAlphaComponent(alpha).setFill()
            NSBezierPath(roundedRect: self.bounds.insetBy(dx: 2, dy: 3), xRadius: 6, yRadius: 6).fill()

        } else if self.showsLeadingSeparator {
            NSColor.separatorColor.setFill()
            NSRect(x: 0, y: 8, width: lineWidth, height: self.bounds.height - 16).fill()
        }

        // edited indicator in place of the close button
        if self.item?.isEdited == true, !self.isHovered {
            let rect = NSRect(x: 8 + 4, y: self.bounds.midY - 4, width: 8, height: 8)
            NSColor.secondaryLabelColor.setFill()
            NSBezierPath(ovalIn: rect).fill()
        }
    }


    override func mouseDown(with event: NSEvent) {

        if event.clickCount == 2 {
            self.tabBar?.doubleClick(self)
            return
        }

        if self.tabBar?.trackDragging(self, with: event) == true { return }

        self.tabBar?.select(self)
    }


    override func otherMouseDown(with event: NSEvent) {

        // middle click closes the tab
        guard event.buttonNumber == 2 else { return super.otherMouseDown(with: event) }

        self.tabBar?.close(self)
    }


    override func menu(for event: NSEvent) -> NSMenu? {

        self.tabBar?.menu(for: self)
    }


    override func accessibilityPerformPress() -> Bool {

        self.tabBar?.select(self)
        return true
    }


    override func accessibilityValue() -> Any? {

        self.isSelected
    }


    // MARK: Actions

    @objc private func closeTab(_ sender: Any?) {

        self.tabBar?.close(self)
    }


    // MARK: Private Methods

    /// Applies the item information to the subviews.
    private func applyItem() {

        guard let item else { return }

        let baseFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize + 1)
        self.titleField.font = item.isTemporary
            ? NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
            : baseFont
        self.titleField.stringValue = item.title
        self.iconView.image = Self.icon(for: item.fileType)
        self.toolTip = item.toolTip
        self.setAccessibilityLabel(item.title)

        self.updateAppearance()
        self.needsLayout = true
    }


    /// Updates the visual state of the subviews.
    private func updateAppearance() {

        self.titleField.textColor = self.isSelected ? .labelColor : .secondaryLabelColor
        self.iconView.alphaValue = self.isSelected ? 1 : 0.8
        self.closeButton.isHidden = !self.isHovered
        self.needsDisplay = true
    }


    /// Returns the cached file icon for the given type.
    ///
    /// - Parameter type: The file type.
    /// - Returns: An icon image.
    private static func icon(for type: UTType?) -> NSImage {

        let type = type ?? .plainText

        if let icon = Self.iconCache[type.identifier] {
            return icon
        }

        let icon = NSWorkspace.shared.icon(for: type)
        Self.iconCache[type.identifier] = icon

        return icon
    }
}


// MARK: -

private final class FlippedView: NSView {

    override var isFlipped: Bool  { true }
}
