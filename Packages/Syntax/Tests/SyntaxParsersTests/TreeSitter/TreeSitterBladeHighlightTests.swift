//
//  TreeSitterBladeHighlightTests.swift
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

struct TreeSitterBladeHighlightTests {
    
    private let registry: LanguageRegistry = .shared
    
    
    @Test func phpOnlyProviderIsAvailable() {
        
        #expect(self.registry.languageProvider(name: "php_only") != nil)
        #expect(self.registry.languageProvider(name: "php_parameter") != nil)
        #expect(self.registry.languageProvider(name: "blade") != nil)
    }
    
    
    @Test func highlightTemplate() async throws {
        
        let source = #"""
            {{-- note --}}
            @extends('layouts.app')
            
            @if ($count > 0)
                <div class="box" id="main">{{ $user->name }} &amp; {!! $raw !!}</div>
            @endif
            """#
        
        let highlights = try await self.highlights(in: source)
        
        // Blade
        #expect(highlights.contains(.init(value: .comments, text: "{{-- note --}}")))
        #expect(highlights.contains(.init(value: .commands, text: "@extends")))
        #expect(highlights.contains(.init(value: .commands, text: "@if")))
        #expect(highlights.contains(.init(value: .commands, text: "@endif")))
        #expect(highlights.contains(.init(value: .characters, text: "{{")))
        #expect(highlights.contains(.init(value: .characters, text: "!!}")))
        
        // HTML
        #expect(highlights.contains(.init(value: .keywords, text: "div")))
        #expect(highlights.contains(.init(value: .attributes, text: "class")))
        #expect(highlights.contains(.init(value: .strings, text: "box")))
        #expect(highlights.contains(.init(value: .characters, text: "&amp;")))
        
        // injected PHP
        #expect(highlights.contains { $0.value == .strings && $0.text.contains("layouts.app") })
        #expect(highlights.contains { $0.value == .variables && $0.text.contains("count") })
        #expect(highlights.contains { $0.value == .variables && $0.text.contains("user") })
        #expect(highlights.contains { $0.value == .variables && $0.text.contains("raw") })
        #expect(highlights.contains(.init(value: .numbers, text: "0")))
    }
    
    
    @Test func highlightPHPBlocks() async throws {
        
        let source = #"""
            @php
                $label = strtoupper('users');
            @endphp
            
            <?php echo $label; ?>
            """#
        
        let highlights = try await self.highlights(in: source)
        
        #expect(highlights.contains(.init(value: .commands, text: "@php")))
        #expect(highlights.contains(.init(value: .commands, text: "@endphp")))
        #expect(highlights.contains(.init(value: .keywords, text: "<?php")))
        #expect(highlights.contains(.init(value: .keywords, text: "echo")))
        #expect(highlights.contains { $0.value == .strings && $0.text.contains("users") })
        #expect(highlights.count { $0.value == .variables && $0.text.contains("label") } == 2)
    }
    
    
    @Test func highlightEmbeddedScriptAndStyle() async throws {
        
        let source = #"""
            <script>
                const total = 42;
            </script>
            <style>
                .box { color: red; }
            </style>
            <x-card :post="$post" @click="open = true" />
            """#
        
        let highlights = try await self.highlights(in: source)
        
        #expect(highlights.contains(.init(value: .keywords, text: "const")))
        #expect(highlights.contains(.init(value: .numbers, text: "42")))
        #expect(highlights.contains { $0.text == "color" })
        #expect(highlights.contains(.init(value: .keywords, text: "x-card")))
        #expect(highlights.contains(.init(value: .attributes, text: ":post")))
        #expect(highlights.contains(.init(value: .strings, text: "open = true")))
    }
    
    
    @Test func injectedHighlightsStayWithinInjectedRanges() async throws {
        
        // -> Directive arguments, such as `$posts as $post`, are not valid PHP expressions on their own.
        let source = #"""
            @forelse ($posts as $post)
                <x-post-card :post="$post" class="mb-4" />
            @empty
                <p>{{ $label }}</p>
            @endforelse
            @foreach ($users as $user)
                <li>{{ $user->name }}</li>
            @endforeach
            """#
        
        let highlights = try await self.highlights(in: source)
        
        #expect(!highlights.contains { $0.value == .variables && ($0.text.contains("\n") || $0.text.contains("<")) })
        #expect(highlights.contains(.init(value: .variables, text: "$label")))
        #expect(highlights.contains(.init(value: .variables, text: "$posts")))
        #expect(highlights.contains(.init(value: .variables, text: "$post")))
        #expect(highlights.contains(.init(value: .variables, text: "$users")))
        #expect(highlights.count { $0 == .init(value: .variables, text: "$user") } == 2)
    }
    
    
    // MARK: Private Methods
    
    private struct Item: Equatable {
        
        var value: SyntaxType
        var text: String
    }
    
    
    private func highlights(in source: String) async throws -> [Item] {
        
        let parser = try self.registry.parser(syntax: .blade)
        let result = try #require(await parser.parseHighlights(in: source, range: source.nsRange))
        
        return result.highlights.map { Item(value: $0.value, text: (source as NSString).substring(with: $0.range)) }
    }
}
