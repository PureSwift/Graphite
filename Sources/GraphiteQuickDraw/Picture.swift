// QuickDraw pictures (PICT, Inside Macintosh: Imaging With QuickDraw, A-1):
// a size, a frame, then opcodes, one byte each in version 1 and two, at even
// offsets, in version 2. Each becomes an operation; those Graphite doesn't
// use are skipped by the lengths Inside Macintosh gives every opcode, so a
// picture with them still draws the rest. Drawing scales the frame to the
// destination rectangle.

import GraphiteBase

/// Decodes a QuickTime-compressed image in a picture: JPEG, PNG and the
/// rest, by its codec's type. The host supplies one; without it such
/// images aren't drawn.
public protocol PictureImageDecoder {
    func decode(codec: FourCharCode, width: Int, height: Int, depth: Int, data: [UInt8]) -> PixelBuffer?
}

/// A shape a picture draws.
public enum PictureShape: Hashable, Sendable {
    case rect(Rect)
    case roundRect(Rect, ovalWidth: Int16, ovalHeight: Int16)
    case oval(Rect)
    case arc(Rect, startAngle: Int16, arcAngle: Int16)
    case polygon(Polygon)
    case region(Region)
}

/// What a picture draws a shape with: frame, paint, erase, invert, or fill
/// with its fill pattern.
public enum PictureVerb: Int, Hashable, Sendable {
    case frame, paint, erase, invert, fill
}

/// Draws a picture's text: the host's text engine, which draws MacRoman
/// bytes at the port's pen in the port's text settings.
public protocol PictureTextDrawer {
    func drawText(macRoman bytes: [UInt8], in port: Port)
}

public struct Picture {

    public enum Operation {
        case clip(Region)
        case backPattern(Pattern)
        case penPattern(Pattern)
        case fillPattern(Pattern)
        case penSize(Point)
        case penMode(TransferMode)
        case ovalSize(Point)
        case origin(dh: Int16, dv: Int16)
        case foreColor(RGBColor)
        case backColor(RGBColor)
        case opColor(RGBColor)
        case highlightColor(RGBColor)
        case textFont(Int16)
        case textFace(UInt8)
        case textSize(Int16)
        case textMode(TransferMode)
        case fontName(id: Int16, name: PascalString)
        /// Text at a point, or after the last text by a distance.
        case text(PascalString, location: Point)
        case line(from: Point, to: Point)
        case shape(PictureVerb, PictureShape)
        /// Pixels copied: BitsRect, PackBitsRect, DirectBitsRect and their
        /// region forms.
        case pixels(PixelBuffer, sourceRect: Rect, destinationRect: Rect, mode: TransferMode, mask: Region?)
        /// A QuickTime-compressed image: its codec's type, size, depth and
        /// data, and where it goes.
        case compressedImage(codec: FourCharCode, width: Int, height: Int, depth: Int, data: [UInt8], destinationRect: Rect, mode: TransferMode)
        case comment(kind: Int16, data: [UInt8])
    }

    /// picFrame.
    public var frame: Rect

    /// 1 or 2.
    public var version: Int

    public var operations: [Operation]

    /// A picture's bytes, from picSize. Throws for a picture that ends
    /// before its end opcode, or whose data is malformed.
    public init(bytes: [UInt8]) throws(MacError) {
        var reader = BigEndianReader(bytes)
        do {
            try reader.skip(2)                                  // picSize: its low 16 bits alone
            frame = try PicturePixels.readRect(&reader)
            let marker = try reader.peek(UInt16.self, at: reader.offset)
            if marker == 0x1101 {
                version = 1
                try reader.skip(2)
            } else if marker == 0x0011, try reader.peek(UInt16.self, at: reader.offset + 2) == 0x02FF {
                version = 2
                try reader.skip(4)
            } else {
                throw MacError.parameter
            }
            var parser = Parser(reader: reader, version: version)
            operations = try parser.parse()
        } catch let error as MacError {
            throw error
        } catch {
            throw .parameter
        }
    }

    /// A PICT file's picture: after its 512-byte header.
    public init(file bytes: [UInt8]) throws(MacError) {
        guard bytes.count > 512 else { throw .parameter }
        try self.init(bytes: Array(bytes[512...]))
    }

    // MARK: Drawing

    /// DrawPicture: the picture scaled from its frame to a rectangle in the
    /// port's coordinates, in the port's state, which is restored after.
    public func draw(in port: Port, destination: Rect, decoder: (any PictureImageDecoder)? = nil, text: (any PictureTextDrawer)? = nil) {
        let saved = (port.pen, port.foreColor, port.backColor, port.backPattern, port.fillPattern, port.clipRegion, port.text)
        defer { (port.pen, port.foreColor, port.backColor, port.backPattern, port.fillPattern, port.clipRegion, port.text) = saved }
        let map = Mapping(frame: frame, destination: destination)
        port.pen = PenState()
        port.foreColor = .black
        port.backColor = .white
        port.clipRegion = saved.5
        for operation in operations {
            switch operation {
            case .clip(let region):
                port.clipRegion = map.region(region).intersection(saved.5)
            case .backPattern(let pattern): port.backPattern = pattern
            case .penPattern(let pattern): port.pen.pattern = pattern
            case .fillPattern(let pattern): port.fillPattern = pattern
            case .penSize(let size): port.pen.size = map.size(size)
            case .penMode(let mode): port.pen.mode = mode
            case .ovalSize: break
            case .origin: break
            case .foreColor(let color): port.foreColor = color
            case .backColor(let color): port.backColor = color
            case .opColor(let color): port.opColor = color
            case .highlightColor(let color): port.highlightColor = color
            case .textFont(let font): port.text.font = font
            case .textFace(let face): port.text.face = face
            case .textSize(let size): port.text.size = size
            case .textMode(let mode): port.text.mode = mode
            case .text(let string, let location):
                port.move(to: map.point(location))
                text?.drawText(macRoman: string.bytes, in: port)
            case .fontName, .comment:
                break
            case .line(let from, let to):
                port.move(to: map.point(from))
                port.line(to: map.point(to))
            case .shape(let verb, let shape):
                let operation: ShapeOperation
                switch verb {
                case .frame: operation = .frame
                case .paint: operation = .paint
                case .erase: operation = .erase
                case .invert: operation = .invert
                case .fill: operation = .fill(port.fillPattern)
                }
                switch shape {
                case .rect(let rect): port.perform(operation, rect: map.rect(rect))
                case .roundRect(let rect, let width, let height):
                    let size = map.size(Point(v: height, h: width))
                    port.perform(operation, roundRect: map.rect(rect), ovalWidth: size.h, ovalHeight: size.v)
                case .oval(let rect): port.perform(operation, oval: map.rect(rect))
                case .arc(let rect, let start, let extent): port.perform(operation, arc: map.rect(rect), startAngle: start, arcAngle: extent)
                case .polygon(let polygon): port.perform(operation, polygon: Polygon(points: polygon.points.map(map.point)))
                case .region(let region): port.perform(operation, region: map.region(region))
                }
            case .pixels(let buffer, let sourceRect, let destinationRect, let mode, let mask):
                port.copyBits(from: buffer, sourceRect: sourceRect, destinationRect: map.rect(destinationRect), mode: mode,
                              mask: mask.map(map.region))
            case .compressedImage(let codec, let width, let height, let depth, let data, let destinationRect, let mode):
                guard let buffer = decoder?.decode(codec: codec, width: width, height: height, depth: depth, data: data) else { continue }
                port.copyBits(from: buffer, sourceRect: buffer.bounds, destinationRect: map.rect(destinationRect), mode: mode)
            }
        }
    }

    /// The scale from a picture's frame to where it is drawn.
    struct Mapping {
        let frame: Rect
        let destination: Rect

        private func scale(_ value: Int16, _ from: Int16, _ fromLength: Int, _ to: Int16, _ toLength: Int) -> Int16 {
            guard fromLength != 0 else { return to }
            return Int16(clamping: Int(to) + (Int(value) - Int(from)) * toLength / fromLength)
        }

        func point(_ point: Point) -> Point {
            Point(v: scale(point.v, frame.top, frame.height, destination.top, destination.height),
                  h: scale(point.h, frame.left, frame.width, destination.left, destination.width))
        }

        func rect(_ rect: Rect) -> Rect {
            Rect(topLeft: point(rect.topLeft), bottomRight: point(rect.bottomRight))
        }

        func size(_ size: Point) -> Point {
            guard frame.width > 0, frame.height > 0 else { return size }
            return Point(v: Int16(clamping: max(1, Int(size.v) * destination.height / frame.height)),
                         h: Int16(clamping: max(1, Int(size.h) * destination.width / frame.width)))
        }

        func region(_ region: Region) -> Region {
            if frame == destination { return region }
            return region.rectangles.reduce(Region()) { $0.union(Region(rect: rect($1))) }
        }
    }
}

// MARK: - Parsing

private struct Parser {

    var reader: BigEndianReader
    let version: Int

    /// The last shapes' rectangles, polygon and region, which the "same"
    /// opcodes draw again.
    var lastRect = Rect.zero, lastRoundRect = Rect.zero, lastOval = Rect.zero, lastArc = Rect.zero
    var lastPolygon = Polygon(points: [])
    var lastRegion = Region()
    var ovalSize = Point.zero
    var penLocation = Point.zero
    var textLocation = Point.zero

    init(reader: BigEndianReader, version: Int) {
        self.reader = reader
        self.version = version
    }

    mutating func parse() throws -> [Picture.Operation] {
        var operations: [Picture.Operation] = []
        while true {
            if version == 2, reader.offset % 2 == 1 { try reader.skip(1) }
            let opcode = version == 2 ? Int(try reader.read(UInt16.self)) : Int(try reader.read(UInt8.self))
            if opcode == 0x00FF || (version == 1 && opcode == 0xFF) { return operations }
            if let operation = try operation(opcode) { operations.append(operation) }
        }
    }

    private mutating func point() throws -> Point {
        let v = Int16(bitPattern: try reader.read(UInt16.self))
        return Point(v: v, h: Int16(bitPattern: try reader.read(UInt16.self)))
    }

    private mutating func rect() throws -> Rect { try PicturePixels.readRect(&reader) }

    private mutating func color() throws -> RGBColor {
        RGBColor(red: try reader.read(UInt16.self), green: try reader.read(UInt16.self), blue: try reader.read(UInt16.self))
    }

    private mutating func pattern() throws -> Pattern { Pattern(try reader.readBytes(8)) }

    private mutating func region() throws -> Region {
        let size = Int(try reader.peek(UInt16.self, at: reader.offset))
        return try Region(record: Array(try reader.readBytes(max(10, size))))
    }

    private mutating func polygon() throws -> Polygon {
        let size = Int(try reader.peek(UInt16.self, at: reader.offset))
        return try Polygon(record: Array(try reader.readBytes(max(10, size))))
    }

    private mutating func pascal() throws -> PascalString {
        let length = Int(try reader.read(UInt8.self))
        return PascalString(bytes: try reader.readBytes(length))
    }

    private mutating func skipWordLength() throws { try reader.skip(Int(try reader.read(UInt16.self))) }

    private mutating func skipLongLength() throws { try reader.skip(Int(try reader.read(UInt32.self))) }

    private mutating func operation(_ opcode: Int) throws -> Picture.Operation? {
        switch opcode {
        case 0x00: return nil
        case 0x01: return .clip(try region())
        case 0x02: return .backPattern(try pattern())
        case 0x03: return .textFont(Int16(bitPattern: try reader.read(UInt16.self)))
        case 0x04: return .textFace(try reader.read(UInt8.self))
        case 0x05: return .textMode(TransferMode(rawValue: Int16(bitPattern: try reader.read(UInt16.self))))
        case 0x06: try reader.skip(4); return nil                      // SpExtra
        case 0x07: return .penSize(try point())
        case 0x08: return .penMode(TransferMode(rawValue: Int16(bitPattern: try reader.read(UInt16.self))))
        case 0x09: return .penPattern(try pattern())
        case 0x0A: return .fillPattern(try pattern())
        case 0x0B:
            ovalSize = try point()
            return .ovalSize(ovalSize)
        case 0x0C:
            let offset = try point()
            return .origin(dh: offset.h, dv: offset.v)
        case 0x0D: return .textSize(Int16(bitPattern: try reader.read(UInt16.self)))
        case 0x0E: return RGBColor(classic: Int32(bitPattern: try reader.read(UInt32.self))).map(Picture.Operation.foreColor)
        case 0x0F: return RGBColor(classic: Int32(bitPattern: try reader.read(UInt32.self))).map(Picture.Operation.backColor)
        case 0x10: try reader.skip(8); return nil                      // TxRatio
        case 0x11: try reader.skip(version == 2 ? 2 : 1); return nil   // VersionOp
        case 0x12, 0x13, 0x14:                                          // BkPixPat, PnPixPat, FillPixPat
            let pattern = try pixelPattern()
            switch opcode {
            case 0x12: return .backPattern(pattern)
            case 0x13: return .penPattern(pattern)
            default: return .fillPattern(pattern)
            }
        case 0x15, 0x16: try reader.skip(2); return nil                // PnLocHFrac, ChExtra
        case 0x17, 0x18, 0x19: return nil
        case 0x1A: return .foreColor(try color())
        case 0x1B: return .backColor(try color())
        case 0x1C, 0x1E: return nil                                     // HiliteMode, DefHilite
        case 0x1D: return .highlightColor(try color())
        case 0x1F: return .opColor(try color())
        case 0x20:
            let from = try point(), to = try point()
            penLocation = to
            return .line(from: from, to: to)
        case 0x21:
            let to = try point()
            defer { penLocation = to }
            return .line(from: penLocation, to: to)
        case 0x22:
            let from = try point()
            let dh = Int16(Int8(bitPattern: try reader.read(UInt8.self))), dv = Int16(Int8(bitPattern: try reader.read(UInt8.self)))
            penLocation = from + Point(v: dv, h: dh)
            return .line(from: from, to: penLocation)
        case 0x23:
            let dh = Int16(Int8(bitPattern: try reader.read(UInt8.self))), dv = Int16(Int8(bitPattern: try reader.read(UInt8.self)))
            let from = penLocation
            penLocation = from + Point(v: dv, h: dh)
            return .line(from: from, to: penLocation)
        case 0x24 ... 0x27: try skipWordLength(); return nil
        case 0x28:
            textLocation = try point()
            return .text(try pascal(), location: textLocation)
        case 0x29:
            textLocation.h &+= Int16(try reader.read(UInt8.self))
            return .text(try pascal(), location: textLocation)
        case 0x2A:
            textLocation.v &+= Int16(try reader.read(UInt8.self))
            return .text(try pascal(), location: textLocation)
        case 0x2B:
            textLocation.h &+= Int16(try reader.read(UInt8.self))
            textLocation.v &+= Int16(try reader.read(UInt8.self))
            return .text(try pascal(), location: textLocation)
        case 0x2C:
            let length = Int(try reader.read(UInt16.self))
            var data = try reader.subreader(length)
            let id = Int16(bitPattern: try data.read(UInt16.self))
            let nameLength = Int(try data.read(UInt8.self))
            return .fontName(id: id, name: PascalString(bytes: try data.readBytes(min(nameLength, data.remaining))))
        case 0x2D ... 0x2F: try skipWordLength(); return nil
        case 0x30 ... 0x37:
            lastRect = try rect()
            return shape(opcode, .rect(lastRect))
        case 0x38 ... 0x3F: return shape(opcode, .rect(lastRect))
        case 0x40 ... 0x47:
            lastRoundRect = try rect()
            return shape(opcode, .roundRect(lastRoundRect, ovalWidth: ovalSize.h, ovalHeight: ovalSize.v))
        case 0x48 ... 0x4F: return shape(opcode, .roundRect(lastRoundRect, ovalWidth: ovalSize.h, ovalHeight: ovalSize.v))
        case 0x50 ... 0x57:
            lastOval = try rect()
            return shape(opcode, .oval(lastOval))
        case 0x58 ... 0x5F: return shape(opcode, .oval(lastOval))
        case 0x60 ... 0x67:
            lastArc = try rect()
            let start = Int16(bitPattern: try reader.read(UInt16.self)), extent = Int16(bitPattern: try reader.read(UInt16.self))
            return shape(opcode, .arc(lastArc, startAngle: start, arcAngle: extent))
        case 0x68 ... 0x6F:
            let start = Int16(bitPattern: try reader.read(UInt16.self)), extent = Int16(bitPattern: try reader.read(UInt16.self))
            return shape(opcode, .arc(lastArc, startAngle: start, arcAngle: extent))
        case 0x70 ... 0x77:
            lastPolygon = try polygon()
            return shape(opcode, .polygon(lastPolygon))
        case 0x78 ... 0x7F: return shape(opcode, .polygon(lastPolygon))
        case 0x80 ... 0x87:
            lastRegion = try region()
            return shape(opcode, .region(lastRegion))
        case 0x88 ... 0x8F: return shape(opcode, .region(lastRegion))
        case 0x90, 0x91, 0x98, 0x99: return try pixels(isRegion: opcode & 1 == 1, isDirect: false)
        case 0x9A, 0x9B:
            try reader.skip(4)                                          // baseAddr
            return try pixels(isRegion: opcode == 0x9B, isDirect: true)
        case 0x92 ... 0x97, 0x9C ... 0x9F: try skipWordLength(); return nil
        case 0xA0: try reader.skip(2); return nil                       // ShortComment
        case 0xA1:
            let kind = Int16(bitPattern: try reader.read(UInt16.self))
            let length = Int(try reader.read(UInt16.self))
            return .comment(kind: kind, data: Array(try reader.readBytes(length)))
        case 0xA2 ... 0xAF: try skipWordLength(); return nil
        case 0xB0 ... 0xCF: return nil
        case 0xD0 ... 0xFE: try skipLongLength(); return nil
        case 0x0C00: try reader.skip(24); return nil                    // HeaderOp
        case 0x8200: return try compressedImage()
        case 0x0100 ... 0x7FFF: try reader.skip((opcode >> 8) * 2); return nil
        case 0x8000 ... 0x80FF: return nil
        default: try skipLongLength(); return nil                       // 0x8100 and up
        }
    }

    /// The verb an opcode's low three bits say: frame, paint, erase, invert,
    /// fill; 5 to 7 are reserved and draw nothing.
    private func shape(_ opcode: Int, _ shape: PictureShape) -> Picture.Operation? {
        guard let verb = PictureVerb(rawValue: opcode & 7) else { return nil }
        return .shape(verb, shape)
    }

    /// A pixel pattern: its type, the old pattern it has for 1-bit ports,
    /// and a color pattern's pixels, which are read past. Its 1-bit pattern
    /// is drawn.
    private mutating func pixelPattern() throws -> Pattern {
        let type = try reader.read(UInt16.self)
        let pattern = try pattern()
        if type == 1 {
            _ = try PicturePixels.readPixels(&reader, try PicturePixels.readHeader(&reader, isDirect: false))
        } else if type == 2 {
            try reader.skip(6)                                          // an RGB pattern's color
        }
        return pattern
    }

    private mutating func pixels(isRegion: Bool, isDirect: Bool) throws -> Picture.Operation {
        let header = try PicturePixels.readHeader(&reader, isDirect: isDirect)
        let source = try rect(), destination = try rect()
        let mode = TransferMode(rawValue: Int16(bitPattern: try reader.read(UInt16.self)))
        let mask = isRegion ? try region() : nil
        let buffer = try PicturePixels.readPixels(&reader, header)
        return .pixels(buffer, sourceRect: source, destinationRect: destination, mode: mode, mask: mask)
    }

    /// CompressedQuickTime: its matrix's translation and scale place the
    /// image's source rectangle; its image description says the codec.
    private mutating func compressedImage() throws -> Picture.Operation? {
        let length = Int(try reader.read(UInt32.self))
        var data = try reader.subreader(length)
        try data.skip(2)                                                // version
        var matrix: [Int32] = []
        for _ in 0 ..< 9 { matrix.append(Int32(bitPattern: try data.read(UInt32.self))) }
        let matteSize = Int(try data.read(UInt32.self))
        try data.skip(8)                                                // matteRect
        let mode = TransferMode(rawValue: Int16(bitPattern: try data.read(UInt16.self)))
        let source = try PicturePixels.readRect(&data)
        try data.skip(4)                                                // accuracy
        let maskSize = Int(try data.read(UInt32.self))
        try data.skip(matteSize + maskSize)
        let descriptionStart = data.offset
        let descriptionSize = Int(try data.read(UInt32.self))
        let codec = FourCharCode(try data.read(UInt32.self))
        try data.seek(to: descriptionStart + 32)
        let width = Int(try data.read(UInt16.self)), height = Int(try data.read(UInt16.self))
        try data.seek(to: descriptionStart + 44)
        let dataSize = Int(try data.read(UInt32.self))
        try data.seek(to: descriptionStart + 82)
        let depth = Int(try data.read(UInt16.self))
        try data.seek(to: descriptionStart + descriptionSize)
        let image = Array(try data.readBytes(min(dataSize, data.remaining)))
        // The matrix's scale (Fixed) and translation (Fixed) place the
        // source rectangle.
        func fixed(_ value: Int32) -> Double { Double(value) / 65536 }
        let scaleX = fixed(matrix[0]), scaleY = fixed(matrix[4]), dx = fixed(matrix[6]), dy = fixed(matrix[7])
        let destination = Rect(
            top: Int16(clamping: Int((Double(source.top) * scaleY + dy).rounded())),
            left: Int16(clamping: Int((Double(source.left) * scaleX + dx).rounded())),
            bottom: Int16(clamping: Int((Double(source.bottom) * scaleY + dy).rounded())),
            right: Int16(clamping: Int((Double(source.right) * scaleX + dx).rounded()))
        )
        return .compressedImage(codec: codec, width: width, height: height, depth: depth, data: image, destinationRect: destination, mode: mode)
    }
}
