//
//  LanguageRegistry.swift
//  Syntax
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2026-01-23.
//
//  ---------------------------------------------------------------------------
//
//  © 2026 1024jp
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

import Foundation
import Synchronization
import SwiftTreeSitter
import TreeSitterPHP

extension Query.Definition {
    
    static let outline = Self.custom("outline")
}


public final class LanguageRegistry: Sendable {
    
    enum RegistryError: Error {
        
        case noQueriesDirectory
        case emptyQueries
    }
    
    
    // MARK: Public Properties
    
    public static let shared: LanguageRegistry = .init()
    
    /// The provider/injection names for PHP code without PHP tags.
    ///
    /// Multiple names are provided so that a syntax can parse different kinds of PHP fragments,
    /// such as statements and directive arguments in Blade, as separate documents.
    static let phpOnlyProviderNames: Set<String> = ["php_only", "php_parameter"]
    
    /// The provider/injection name for JavaScript expressions in Vue templates.
    ///
    /// The expressions are parsed as a separate document from the `<script>` element
    /// since they are not always valid code on their own, e.g. `item in items` in `v-for`.
    static let vueExpressionProviderName = "vue_expression"
    
    
    // MARK: Private Properties
    
    private let directoryURL: URL
    private let cachedConfiguration: Mutex<[TreeSitterSyntax: LanguageConfiguration]> = .init([:])
    private let cachedPHPOnlyConfiguration: Mutex<LanguageConfiguration?> = .init(nil)
    private let cachedVueExpressionConfiguration: Mutex<LanguageConfiguration?> = .init(nil)
    
    
    // MARK: Lifecycle
    
    init() {
        
        self.directoryURL = Bundle.module.url(forResource: "Queries", withExtension: nil)!
    }
    
    
    // MARK: Internal Methods
    
    /// Returns a provider mapping from a language provider/injection name to its `LanguageConfiguration`.
    ///
    /// - Parameters:
    ///   - name: The provider or injection name (e.g., "javascript", "markdown_inline").
    /// - Returns: A cached or newly created `LanguageConfiguration` if the language is supported, otherwise `nil`.
    nonisolated func languageProvider(name: String) -> LanguageConfiguration? {
        
        if Self.phpOnlyProviderNames.contains(name.lowercased()) {
            return self.phpOnlyConfiguration()
        }
        
        if name.lowercased() == Self.vueExpressionProviderName {
            return self.vueExpressionConfiguration()
        }
        
        guard let syntax = TreeSitterSyntax(providerName: name) else { return nil }
        
        return try? self.configuration(for: syntax)
    }
    
    
    /// Returns (and caches) the configuration for PHP code that is not enclosed in PHP tags.
    ///
    /// This language is available only as an injection target, such as for PHP expressions in Blade templates.
    ///
    /// - Returns: A language configuration, or `nil` if the PHP highlights query cannot be loaded.
    nonisolated func phpOnlyConfiguration() -> LanguageConfiguration? {
        
        if let cache = self.cachedPHPOnlyConfiguration.withLock({ $0 }) {
            return cache
        }
        
        // -> Share the highlights query with PHP since `php_only` is a strict subset of the PHP grammar.
        //    The injections query is not shared because `php_only` has no text nodes to inject HTML into.
        let language = unsafe Language(tree_sitter_php_only())
        let queryURL = self.queriesURL(for: .php).appending(path: Query.Definition.highlights.filename)
        
        guard let query = try? Query(language: language, url: queryURL) else { return nil }
        
        let config = LanguageConfiguration(language, name: "php_only", queries: [.highlights: query])
        self.cachedPHPOnlyConfiguration.withLock { $0 = config }
        
        return config
    }
    
    
    /// Returns (and caches) the configuration for JavaScript expressions in Vue templates.
    ///
    /// - Returns: A language configuration, or `nil` if the JavaScript highlights query cannot be loaded.
    nonisolated func vueExpressionConfiguration() -> LanguageConfiguration? {
        
        if let cache = self.cachedVueExpressionConfiguration.withLock({ $0 }) {
            return cache
        }
        
        // -> Share only the highlights query with JavaScript.
        let language = unsafe Language(TreeSitterSyntax.javaScript.language)
        let queryURL = self.queriesURL(for: .javaScript).appending(path: Query.Definition.highlights.filename)
        
        guard let query = try? Query(language: language, url: queryURL) else { return nil }
        
        let config = LanguageConfiguration(language, name: Self.vueExpressionProviderName, queries: [.highlights: query])
        self.cachedVueExpressionConfiguration.withLock { $0 = config }
        
        return config
    }
    
    
    /// Returns (and caches) a `LanguageConfiguration` for the given syntax.
    ///
    /// - Parameters:
    ///   - syntax: The target syntax.
    /// - Returns: A language configuration.
    nonisolated func configuration(for syntax: TreeSitterSyntax) throws(RegistryError) -> LanguageConfiguration {
        
        if let cache = self.cachedConfiguration.withLock({ $0[syntax] }) {
            return cache
        }
        
        let queriesURL = self.queriesURL(for: syntax)
        
        guard (try? queriesURL.checkResourceIsReachable()) == true else { throw .noQueriesDirectory }
        
        let queries = syntax.loadQueries(at: queriesURL)
        
        guard !queries.isEmpty else { throw .emptyQueries }
        
        let config = unsafe LanguageConfiguration(syntax.language, name: syntax.name, queries: queries)
        self.cachedConfiguration.withLock { $0[syntax] = config }
        
        return config
    }
    
    
    /// Returns the file URL to the queries directory for the given syntax.
    ///
    /// - Parameters:
    ///   - syntax: The target syntax.
    /// - Returns: A file URL.
    nonisolated func queriesURL(for syntax: TreeSitterSyntax) -> URL {
        
        self.directoryURL.appending(component: syntax.name)
    }
}


// MARK: -

private extension TreeSitterSyntax {
    
    /// Resolves from provider/injection name.
    ///
    /// - Parameter providerName: The provider name.
    init?(providerName: String) {
        
        let lowercased = providerName.lowercased()
        
        guard
            let syntax = Self.allCases.first(where: { $0.providerName == lowercased })
        else { return nil }
        
        self = syntax
    }
    
    
    /// Loads query files from the given directory.
    ///
    /// - Parameters:
    ///   - queriesURL: The queries directory URL.
    /// - Returns: The loaded queries keyed by their definition.
    func loadQueries(at queriesURL: URL) -> [Query.Definition: Query] {
        
        let definitions: [Query.Definition] = [
            .injections,
            .highlights,
            .outline,
        ]
        
        var queries: [Query.Definition: Query] = [:]
        for definition in definitions {
            let queryURL = queriesURL.appending(path: definition.filename)
            
            guard (try? queryURL.resourceValues(forKeys: [.isReadableKey]))?.isReadable == true else { continue }
            
            let language = unsafe Language(self.language)
            do {
                queries[definition] = try Query(language: language, url: queryURL)
            } catch {
                assertionFailure("failed open \(self.name)'s \(queryURL.lastPathComponent): \(error.localizedDescription)")
            }
        }
        
        return queries
    }
}
