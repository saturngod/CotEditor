//
//  TreeSitterVueHighlightTests.swift
//  SyntaxParsersTests
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

import Foundation
import Testing
import StringUtils
import ValueRange
import SyntaxFormat
@testable import SyntaxParsers

struct TreeSitterVueHighlightTests {
    
    private let registry: LanguageRegistry = .shared
    
    
    @Test func providersAreAvailable() {
        
        #expect(self.registry.languageProvider(name: "vue") != nil)
        #expect(self.registry.languageProvider(name: "vue_expression") != nil)
    }
    
    
    @Test func highlightTemplate() async throws {
        
        let source = #"""
            <!-- note -->
            <template>
              <div class="box" v-if="count > 0" @click.prevent="open = true">{{ user.name }} &amp; {{ 42 }}</div>
            </template>
            """#
        
        let highlights = try await self.highlights(in: source)
        
        #expect(highlights.contains(.init(value: .comments, text: "<!-- note -->")))
        #expect(highlights.contains(.init(value: .keywords, text: "template")))
        #expect(highlights.contains(.init(value: .keywords, text: "div")))
        #expect(highlights.contains(.init(value: .attributes, text: "class")))
        #expect(highlights.contains(.init(value: .strings, text: "\"box\"")))
        #expect(highlights.contains(.init(value: .commands, text: "v-if")))
        #expect(highlights.contains(.init(value: .attributes, text: "click")))
        #expect(highlights.contains(.init(value: .attributes, text: "prevent")))
        #expect(highlights.contains(.init(value: .characters, text: "{{")))
        
        // injected expressions
        #expect(highlights.contains(.init(value: .numbers, text: "0")))
        #expect(highlights.contains(.init(value: .numbers, text: "42")))
    }
    
    
    @Test func highlightScriptAndStyle() async throws {
        
        let source = #"""
            <script setup lang="ts">
            const total: number = 42
            </script>
            <script>
            export default { name: 'App' }
            </script>
            <style scoped>
            .box { color: red; }
            </style>
            """#
        
        let highlights = try await self.highlights(in: source)
        
        #expect(highlights.contains(.init(value: .keywords, text: "const")))
        #expect(highlights.contains(.init(value: .numbers, text: "42")))
        #expect(highlights.contains(.init(value: .types, text: "number")))
        #expect(highlights.contains(.init(value: .keywords, text: "export")))
        #expect(highlights.contains { $0.value == .strings && $0.text.contains("App") })
        #expect(highlights.contains { $0.text == "color" })
    }
    
    
    @Test func injectedHighlightsStayWithinInjectedRanges() async throws {
        
        // -> `v-for` expressions, such as `item in items`, are not valid JavaScript on their own.
        let source = #"""
            <template>
              <li v-for="item in items" :key="item.id">{{ item.name }}</li>
              <p>{{ label }}</p>
            </template>
            """#
        
        let highlights = try await self.highlights(in: source)
        
        #expect(!highlights.contains { $0.text.contains("\n") || ($0.text.contains("<") && $0.value != .keywords) })
    }
    
    
    // MARK: Private Methods
    
    private struct Item: Equatable {
        
        var value: SyntaxType
        var text: String
    }
    
    
    private func highlights(in source: String) async throws -> [Item] {
        
        let parser = try self.registry.parser(syntax: .vue)
        let result = try #require(await parser.parseHighlights(in: source, range: source.nsRange))
        
        return result.highlights.map { Item(value: $0.value, text: (source as NSString).substring(with: $0.range)) }
    }
}
