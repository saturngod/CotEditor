//
//  LongLineTests.swift
//  StringUtilsTests
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

import Testing
@testable import StringUtils

struct LongLineTests {

    @Test func noLongLine() {

        #expect("".splittingLongLines(maximumLineLength: 4, chunkLength: 2) == nil)
        #expect("abcd\nefgh\r\nijkl".splittingLongLines(maximumLineLength: 4, chunkLength: 2) == nil)
    }


    @Test func splitKeepsContent() throws {

        let string = String(repeating: "abcdefghij", count: 100)
        let split = try #require(string.splittingLongLines(maximumLineLength: 50, chunkLength: 20))

        #expect(split.replacing("\n", with: "") == string)
        #expect(split.split(separator: "\n").allSatisfy { $0.utf8.count <= 20 })
    }


    @Test func preferredBreak() throws {

        let string = "<b>noun</b> <i>word</i><br>" + String(repeating: "x", count: 40)
        let split = try #require(string.splittingLongLines(maximumLineLength: 30, chunkLength: 16))

        #expect(split.hasPrefix("<b>noun</b> <i>\n"))
        #expect(split.replacing("\n", with: "") == string)
    }


    @Test func onlyLongLinesAreSplit() throws {

        let string = "short\n" + String(repeating: "a", count: 30) + "\nend"
        let split = try #require(string.splittingLongLines(maximumLineLength: 10, chunkLength: 10))

        #expect(split == "short\naaaaaaaaaa\naaaaaaaaaa\naaaaaaaaaa\nend")
    }


    @Test func inferLineEnding() {

        let string = "a\r\n" + String(repeating: "b", count: 12)

        #expect(string.splittingLongLines(maximumLineLength: 5, chunkLength: 4) == "a\r\nbbbb\r\nbbbb\r\nbbbb")
        #expect(String(repeating: "c", count: 6).splittingLongLines(maximumLineLength: 5, chunkLength: 3) == "ccc\nccc")
        #expect(String(repeating: "c", count: 6).splittingLongLines(maximumLineLength: 5, chunkLength: 3, separator: "\r") == "ccc\rccc")
    }


    @Test func keepsCharactersIntact() throws {

        // Myanmar text consists of multi-byte scalars and combining marks
        let string = String(repeating: "မြန်မာ", count: 200)
        let split = try #require(string.splittingLongLines(maximumLineLength: 100, chunkLength: 40))

        #expect(split.replacing("\n", with: "") == string)
        #expect(split.unicodeScalars.contains("\u{FFFD}") == false)

        let emoji = String(repeating: "👨‍👩‍👧", count: 50)
        let emojiSplit = try #require(emoji.splittingLongLines(maximumLineLength: 30, chunkLength: 20))
        #expect(emojiSplit.replacing("\n", with: "") == emoji)
    }
}
