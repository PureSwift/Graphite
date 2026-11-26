// A font's horizontal metrics as ATS gives them (ATSFontGetHorizontalMetrics):
// fractions of the em, so they hold at any size.

/// Distances in ems: ascent is above the baseline, descent below it and
/// negative, and the underline position is below it and negative too.
public struct HorizontalFontMetrics: Hashable, Sendable {

    public var ascent: Double
    public var descent: Double
    public var leading: Double
    public var averageAdvance: Double
    public var maximumAdvance: Double
    public var minimumLeftSideBearing: Double
    public var minimumRightSideBearing: Double
    public var capHeight: Double
    public var xHeight: Double

    /// Degrees; negative leans right.
    public var italicAngle: Double
    public var underlinePosition: Double
    public var underlineThickness: Double

    public init(ascent: Double, descent: Double, leading: Double = 0, averageAdvance: Double = 0,
                maximumAdvance: Double = 0, minimumLeftSideBearing: Double = 0, minimumRightSideBearing: Double = 0,
                capHeight: Double = 0, xHeight: Double = 0, italicAngle: Double = 0,
                underlinePosition: Double = 0, underlineThickness: Double = 0) {
        self.ascent = ascent
        self.descent = descent
        self.leading = leading
        self.averageAdvance = averageAdvance
        self.maximumAdvance = maximumAdvance
        self.minimumLeftSideBearing = minimumLeftSideBearing
        self.minimumRightSideBearing = minimumRightSideBearing
        self.capHeight = capHeight
        self.xHeight = xHeight
        self.italicAngle = italicAngle
        self.underlinePosition = underlinePosition
        self.underlineThickness = underlineThickness
    }
}
