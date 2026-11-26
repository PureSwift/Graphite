// The C library's arc tangent, kept apart from the files that use QuickDraw's
// Point and Rect, which Darwin's MacTypes names too.

#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

/// An angle in QuickDraw's terms for a point relative to an oval's center,
/// its coordinates scaled by the oval's half-width and half-height: 0° at
/// twelve o'clock, increasing clockwise, so that 45° passes through the
/// bounding rectangle's corner.
func quickDrawAngle(dx: Double, dy: Double) -> Double {
    let degrees = atan2(dx, -dy) * 180 / .pi
    return degrees < 0 ? degrees + 360 : degrees
}
