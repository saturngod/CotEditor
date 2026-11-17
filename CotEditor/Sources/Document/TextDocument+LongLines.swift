//
//  TextDocument+LongLines.swift
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

/// The limits to split long lines on reading files.
///
/// TextKit lays out a whole paragraph at once, and a line of a few megabytes already takes tens of seconds.
enum LongLineLimit {
    
    /// The line length in UTF-8 bytes above which a line is split.
    static let maximumLineLength = 256 * 1024
    
    /// The target length in UTF-8 bytes of each split line.
    static let chunkLength = 16 * 1024
}


struct SplitLongLinesSavingError: LocalizedError {
    
    var errorDescription: String? {
        
        String(localized: "SplitLongLinesSavingError.description",
               defaultValue: "The document can’t be saved because its long lines were split for display.")
    }
    
    
    var recoverySuggestion: String? {
        
        String(localized: "SplitLongLinesSavingError.recoverySuggestion",
               defaultValue: "Saving would add line breaks that aren’t in the original file. Edit the file in another app that supports very long lines.")
    }
}
