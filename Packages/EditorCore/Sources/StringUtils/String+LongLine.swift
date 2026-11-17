//
//  String+LongLine.swift
//  StringUtils
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

public extension String {

    /// Returns a copy of the receiver in which every line longer than `maximumLineLength` is broken into chunks of about `chunkLength`.
    ///
    /// TextKit lays out a whole paragraph at once, so a multi-megabyte single line makes the editor unresponsive.
    /// Inserting line breaks keeps each paragraph small enough to lay out quickly.
    ///
    /// Lengths are measured in UTF-8 bytes. Breaks are placed only before the start of a Unicode scalar,
    /// preferably after `>`, whitespace, `,` or `;` and before an ASCII character so that grapheme clusters stay intact.
    ///
    /// - Parameters:
    ///   - maximumLineLength: The line length in UTF-8 bytes above which a line is split.
    ///   - chunkLength: The target length in UTF-8 bytes of each split piece. Must be less than or equal to `maximumLineLength`.
    ///   - separator: The line ending to insert, or `nil` to use the first line ending found in the receiver (LF if none).
    /// - Returns: The split string, or `nil` if no line exceeds `maximumLineLength`.
    func splittingLongLines(maximumLineLength: Int, chunkLength: Int, separator: String? = nil) -> String? {

        precondition(chunkLength > 0 && chunkLength <= maximumLineLength)

        return Self.splitLongLines(Array(self.utf8), maximumLineLength: maximumLineLength, chunkLength: chunkLength, separator: separator)
    }


    private static func splitLongLines(_ bytes: [UInt8], maximumLineLength: Int, chunkLength: Int, separator: String?) -> String? {

        let lf: UInt8 = 0x0A
        let cr: UInt8 = 0x0D

        // find the first line ending and check whether any line is too long
        var firstLineEnding: String?
        var hasLongLine = false
        var lineLength = 0
        for (index, byte) in bytes.enumerated() {
            if byte == lf || byte == cr {
                if firstLineEnding == nil {
                    firstLineEnding = (byte == cr)
                        ? ((index + 1 < bytes.count && bytes[index + 1] == lf) ? "\r\n" : "\r")
                        : "\n"
                }
                lineLength = 0
            } else {
                lineLength += 1
                if lineLength > maximumLineLength {
                    hasLongLine = true
                    if firstLineEnding != nil { break }
                }
            }
        }

        guard hasLongLine else { return nil }

        let separator = separator ?? firstLineEnding ?? "\n"

        // whether a new line can start at the given offset without breaking a character
        func isASCIIBoundary(_ offset: Int) -> Bool {

            let byte = bytes[offset]
            return byte < 0x80 && byte != lf && byte != cr
        }
        func isScalarBoundary(_ offset: Int) -> Bool {

            (bytes[offset] & 0b1100_0000) != 0b1000_0000
        }
        func isPreferredBreak(after byte: UInt8) -> Bool {

            switch byte {
                case UInt8(ascii: ">"), UInt8(ascii: " "), UInt8(ascii: "\t"), UInt8(ascii: ","), UInt8(ascii: ";"): true
                default: false
            }
        }

        var result = ""
        result.reserveCapacity(bytes.count + bytes.count / chunkLength * separator.utf8.count)

        func append(_ range: Range<Int>) {

            // -> Ranges always start and end at scalar boundaries, so decoding never fails.
            result += String(bytes: bytes[range], encoding: .utf8) ?? ""
        }

        var lineStart = 0
        var offset = 0
        while offset <= bytes.count {
            // find the end of the current line
            var lineEnd = offset
            while lineEnd < bytes.count, bytes[lineEnd] != lf, bytes[lineEnd] != cr {
                lineEnd += 1
            }

            // split the line if it is too long
            var pieceStart = lineStart
            if lineEnd - lineStart > maximumLineLength {
                while lineEnd - pieceStart > chunkLength {
                    let limit = pieceStart + chunkLength
                    let lowerBound = pieceStart + Swift.max(chunkLength / 2, 1)

                    let breakOffset = stride(from: limit, through: lowerBound, by: -1)
                        .first { isASCIIBoundary($0) && isPreferredBreak(after: bytes[$0 - 1]) }
                        ?? stride(from: limit, through: lowerBound, by: -1).first(where: isASCIIBoundary)
                        ?? stride(from: limit, through: pieceStart + 1, by: -1).first(where: isScalarBoundary)
                        ?? limit

                    append(pieceStart..<breakOffset)
                    result += separator
                    pieceStart = breakOffset
                }
            }

            // append the rest of the line including its line ending
            var nextLineStart = lineEnd
            if nextLineStart < bytes.count {
                nextLineStart += (bytes[nextLineStart] == cr && nextLineStart + 1 < bytes.count && bytes[nextLineStart + 1] == lf) ? 2 : 1
            }
            append(pieceStart..<nextLineStart)

            guard nextLineStart < bytes.count else { break }
            lineStart = nextLineStart
            offset = nextLineStart
        }

        return result
    }
}
