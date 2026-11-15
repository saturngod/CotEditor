//
//  TerminalPalette.swift
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

import AppKit.NSColor

/// The colors for a terminal derived from an editor theme.
struct TerminalPalette: Equatable {

    var foreground: NSColor
    var background: NSColor
    var caret: NSColor
    var selection: NSColor

    /// The 16 ANSI colors in the order of black, red, green, yellow, blue, magenta, cyan, white, and their bright variants.
    var ansiColors: [NSColor]

    var isDark: Bool
}


extension TerminalPalette {

    /// Creates a terminal palette from the given editor theme.
    ///
    /// The ANSI colors keep their conventional hues so that the meaning of colored output (e.g., red for errors) is preserved,
    /// but they are taken from the syntax colors of the theme when the theme has a color with a close hue.
    /// Otherwise, they are synthesized to match the tone of the theme.
    ///
    /// - Parameter theme: The editor theme.
    init(theme: Theme) {

        let isDark = theme.isDarkTheme
        let foreground = theme.text.color.sRGB
        let background = theme.background.color.sRGB

        // collect colorful syntax colors in the theme
        let syntaxColors = [theme.keywords, theme.commands, theme.types, theme.attributes, theme.variables,
                            theme.values, theme.numbers, theme.strings, theme.characters]
            .map(\.color.sRGB)
            .filter { $0.saturationComponent > 0.2 && $0.contrastRatio(to: background) > 1.8 }

        // -> Use the tone of the theme for the colors the theme doesn't have.
        let saturation = (syntaxColors.map(\.saturationComponent).median ?? 0.6).clamped(to: 0.45...0.9)
        let brightness = (syntaxColors.map(\.brightnessComponent).median ?? (isDark ? 0.85 : 0.6))
            .clamped(to: isDark ? 0.7...1.0 : 0.35...0.75)

        let hues: [Double] = [0, 120, 50, 220, 300, 180]  // red, green, yellow, blue, magenta, cyan
        let normalColors: [NSColor] = hues.map { (hue: Double) -> NSColor in
            let closest: NSColor? = syntaxColors
                .filter { hueDistance(Double($0.hueComponent) * 360, hue) <= 30 }
                .min { hueDistance(Double($0.hueComponent) * 360, hue) < hueDistance(Double($1.hueComponent) * 360, hue) }

            return closest ?? NSColor(colorSpace: .sRGB, hue: hue / 360, saturation: saturation, brightness: brightness, alpha: 1)
        }
        let brightColors: [NSColor] = normalColors.map { (color: NSColor) -> NSColor in
            isDark ? color.mixed(0.25, with: .white) : color.mixed(0.2, with: .black)
        }

        // grayscale colors
        let comments = theme.comments.color.sRGB
        let dimmed = (comments.contrastRatio(to: background) > 1.8) ? comments : foreground.mixed(0.5, with: background)
        let black: NSColor
        let white: NSColor
        let brightWhite: NSColor
        if isDark {
            black = background.mixed(0.15, with: foreground)
            white = foreground.mixed(0.15, with: background)
            brightWhite = foreground
        } else {
            black = foreground
            white = background.mixed(0.45, with: foreground)
            brightWhite = background.mixed(0.25, with: foreground)
        }

        self.foreground = foreground
        self.background = background
        self.caret = theme.insertionPointColor.sRGB
        self.selection = theme.selectionColor.sRGB
        self.ansiColors = [black] + normalColors + [white, dimmed] + brightColors + [brightWhite]
        self.isDark = isDark
    }
}


// MARK: - Private Extensions

/// Returns the distance between two hues in degree.
private func hueDistance(_ lhs: Double, _ rhs: Double) -> Double {

    let distance = abs(lhs - rhs).truncatingRemainder(dividingBy: 360)

    return min(distance, 360 - distance)
}


private extension NSColor {

    /// The color converted into the sRGB color space.
    var sRGB: NSColor {

        self.usingColorSpace(.sRGB) ?? .gray
    }


    /// The relative luminance defined in WCAG.
    private var relativeLuminance: Double {

        let components = [self.redComponent, self.greenComponent, self.blueComponent]
            .map { ($0 <= 0.03928) ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }

        return 0.2126 * components[0] + 0.7152 * components[1] + 0.0722 * components[2]
    }


    /// Returns the WCAG contrast ratio to the given color.
    ///
    /// - Parameter color: The color to compare in the sRGB color space.
    /// - Returns: The contrast ratio between 1 and 21.
    func contrastRatio(to color: NSColor) -> Double {

        let luminances = [self.relativeLuminance, color.relativeLuminance].sorted()

        return (luminances[1] + 0.05) / (luminances[0] + 0.05)
    }


    /// Returns the color mixed with the given color.
    ///
    /// - Parameters:
    ///   - fraction: The amount of the other color between 0 and 1.
    ///   - color: The color to mix.
    /// - Returns: A mixed color.
    func mixed(_ fraction: Double, with color: NSColor) -> NSColor {

        self.blended(withFraction: fraction, of: color) ?? self
    }
}


private extension Collection<CGFloat> {

    /// The median value of the collection.
    var median: Double? {

        guard !self.isEmpty else { return nil }

        let sorted = self.sorted()

        return Double(sorted[sorted.count / 2])
    }
}


private extension Double {

    /// Returns the value clamped to the given range.
    func clamped(to range: ClosedRange<Double>) -> Double {

        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
