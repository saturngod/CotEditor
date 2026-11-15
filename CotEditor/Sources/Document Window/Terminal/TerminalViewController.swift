//
//  TerminalViewController.swift
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
import Defaults
import SwiftTerm

/// A view controller that hosts a terminal emulator running the user's login shell.
final class TerminalViewController: NSViewController {

    // MARK: Public Properties

    /// The colors to apply to the terminal.
    var palette: TerminalPalette  { didSet { if palette != oldValue { self.applyPalette() } } }

    /// The handler invoked when the shell process has terminated.
    var terminationHandler: (@MainActor () -> Void)?

    /// The handler invoked when the title of the terminal has changed.
    var titleHandler: (@MainActor () -> Void)?

    /// The title to display in the session list.
    var displayTitle: String {

        let title = self.terminalTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        return title.isEmpty ? URL(filePath: Self.loginShell).lastPathComponent : title
    }


    // MARK: Private Properties

    private let workingDirectory: URL?

    @ViewLoading private var terminalView: LocalProcessTerminalView
    private var isProcessStarted = false
    private var terminalTitle = ""

    private var fontObserver: AnyCancellable?


    // MARK: Lifecycle

    /// Creates a terminal view controller.
    ///
    /// - Parameters:
    ///   - workingDirectory: The directory where the shell starts, or `nil` to start in the home directory.
    ///   - palette: The colors to apply to the terminal.
    init(workingDirectory: URL?, palette: TerminalPalette) {

        self.workingDirectory = workingDirectory
        self.palette = palette

        super.init(nibName: nil, bundle: nil)
    }


    @available(*, unavailable)
    required init?(coder: NSCoder) {

        fatalError("init(coder:) has not been implemented")
    }


    isolated deinit {
        if self.isProcessStarted {
            self.viewIfLoaded.flatMap { _ in self.terminalView }?.terminate()
        }
    }


    override func loadView() {

        let terminalView = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 640, height: 240))
        terminalView.processDelegate = self
        terminalView.font = Self.font
        terminalView.translatesAutoresizingMaskIntoConstraints = false
        self.terminalView = terminalView

        let view = NSView()
        view.addSubview(terminalView)

        let inset: CGFloat = 6
        // -> The pane can be laid out smaller than the insets while the split view adds or collapses it,
        //    so let the far edges give way instead of conflicting.
        let farEdgeConstraints = [
            terminalView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            terminalView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ]
        for constraint in farEdgeConstraints {
            constraint.priority = .required - 1
        }
        NSLayoutConstraint.activate(farEdgeConstraints + [
            terminalView.topAnchor.constraint(equalTo: view.topAnchor, constant: inset),
            terminalView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: inset),
        ])

        self.view = view

        self.applyPalette()
    }


    override func viewWillAppear() {

        super.viewWillAppear()

        self.fontObserver = UserDefaults.standard.publisher(for: .fontKey(for: .monospaced))
            .sink { [weak self] _ in self?.terminalView.font = Self.font }
    }


    override func viewDidAppear() {

        super.viewDidAppear()

        // -> Start the shell after the view gets its actual size
        //    so that the shell knows the right number of columns and rows.
        self.startProcessIfNeeded()
    }


    override func viewDidDisappear() {

        super.viewDidDisappear()

        self.fontObserver?.cancel()
        self.fontObserver = nil
    }


    // MARK: Public Methods

    /// Whether the terminal currently has the keyboard focus.
    var hasFocus: Bool {

        guard
            self.isViewLoaded,
            let responder = self.view.window?.firstResponder as? NSView
        else { return false }

        return responder.isDescendant(of: self.view)
    }


    /// Moves the keyboard focus to the terminal.
    func focus() {

        self.view.window?.makeFirstResponder(self.terminalView)
    }


    /// Terminates the shell process.
    func terminate() {

        guard self.isProcessStarted, self.isViewLoaded else { return }

        self.terminalView.terminate()
    }


    // MARK: Private Methods

    /// The font for the terminal.
    private static var font: NSFont {

        let font = UserDefaults.standard.font(for: .monospaced)

        // -> A terminal cannot work with proportional fonts.
        return font.isFixedPitch ? font : .monospacedSystemFont(ofSize: font.pointSize, weight: .regular)
    }


    /// Launches the user's login shell if not yet.
    private func startProcessIfNeeded() {

        guard !self.isProcessStarted else { return }

        self.isProcessStarted = true

        let shell = Self.loginShell
        let shellName = URL(filePath: shell).lastPathComponent
        var environment = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        environment.append("TERM_PROGRAM=CotEditor")
        environment.append("CLICOLOR=1")
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            environment.append("PATH=\(path)")
        }

        var isDirectory: ObjCBool = false
        let directory = self.workingDirectory?.path(percentEncoded: false)
        let currentDirectory = if let directory, FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory), isDirectory.boolValue {
            directory
        } else {
            NSHomeDirectory()
        }

        // start as a login shell so that the user's profile is loaded
        self.terminalView.startProcess(executable: shell, environment: environment, execName: "-" + shellName, currentDirectory: currentDirectory)
    }


    /// The path to the user's login shell.
    private static let loginShell: String = {

        if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell {
            let path = String(cString: shell)
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        return ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    }()


    /// Applies the current palette to the terminal view.
    private func applyPalette() {

        guard self.isViewLoaded else { return }

        let palette = self.palette

        self.terminalView.installColors(palette.ansiColors.map(SwiftTerm.Color.init(nsColor:)))
        self.terminalView.nativeForegroundColor = palette.foreground
        self.terminalView.nativeBackgroundColor = palette.background
        self.terminalView.caretColor = palette.caret
        self.terminalView.selectedTextBackgroundColor = palette.selection
        self.terminalView.appearance = NSAppearance(named: palette.isDark ? .darkAqua : .aqua)
        self.terminalView.needsDisplay = true
    }
}


// MARK: Terminal View Delegate

extension TerminalViewController: LocalProcessTerminalViewDelegate {

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) { }


    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {

        self.terminalTitle = title
        self.titleHandler?()
    }


    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) { }


    func processTerminated(source: TerminalView, exitCode: Int32?) {

        self.terminationHandler?()
    }
}


// MARK: - Private Extensions

private extension SwiftTerm.Color {

    /// Creates a terminal color from an `NSColor`.
    ///
    /// - Parameter nsColor: The color to convert.
    convenience init(nsColor: NSColor) {

        let color = nsColor.usingColorSpace(.sRGB) ?? .gray

        self.init(red: UInt16((color.redComponent * 65535).rounded().clamped(to: 0...65535)),
                  green: UInt16((color.greenComponent * 65535).rounded().clamped(to: 0...65535)),
                  blue: UInt16((color.blueComponent * 65535).rounded().clamped(to: 0...65535)))
    }
}


private extension CGFloat {

    /// Returns the value clamped to the given range.
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {

        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
