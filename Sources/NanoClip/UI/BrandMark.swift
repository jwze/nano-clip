// nano-clip — 轻量 macOS 剪贴板历史
// Copyright © 2026 jvz <them@live.cn>. All rights reserved.
// Watermark: jvz·NanoClip — 电子水印，请勿移除本署名头。

import AppKit

/// The NanoClip mark, drawn from one piece of geometry so the app icon, the menu-bar glyph and the
/// in-app brand chip can never drift apart.
///
/// Shape: a pointy-top hexagon (the "container") holding an N built from three strokes, with two
/// circuit nodes at the stroke ends. It reads as a clipboard tile at 16pt and as a technical
/// instrument mark at 1024pt.
enum BrandMark {
    /// Normalized outline of the hexagon, pointy top, radius 0.42 around (0.5, 0.5).
    static func hexagon(in rect: NSRect) -> NSBezierPath {
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let radius = rect.width * 0.42
        let path = NSBezierPath()
        for index in 0..<6 {
            let angle = (90.0 + Double(index) * 60.0) * .pi / 180.0
            let point = NSPoint(
                x: center.x + CGFloat(cos(angle)) * radius,
                y: center.y + CGFloat(sin(angle)) * radius
            )
            if index == 0 { path.move(to: point) } else { path.line(to: point) }
        }
        path.close()
        return path
    }

    /// The N: left stem, diagonal, right stem — plus its two nodes.
    static func letterN(in rect: NSRect) -> (strokes: NSBezierPath, nodes: [NSRect]) {
        func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            NSPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        let leftBottom = point(0.335, 0.315)
        let leftTop = point(0.335, 0.640)
        let rightBottom = point(0.665, 0.315)
        let rightTop = point(0.665, 0.685)

        let strokes = NSBezierPath()
        strokes.lineCapStyle = .round
        strokes.lineJoinStyle = .round
        strokes.move(to: leftBottom)
        strokes.line(to: leftTop)
        strokes.line(to: rightBottom)
        strokes.line(to: rightTop)

        let nodeSide = rect.width * 0.075
        let nodes = [
            NSRect(
                x: leftBottom.x - nodeSide / 2,
                y: leftBottom.y - nodeSide / 2,
                width: nodeSide,
                height: nodeSide
            ),
            NSRect(
                x: rightTop.x - nodeSide / 2,
                y: rightTop.y - nodeSide / 2,
                width: nodeSide,
                height: nodeSide
            ),
        ]
        return (strokes, nodes)
    }

    /// Monochrome mark for the menu bar. Template images must carry alpha only, so the glyph is
    /// drawn solid black and handed to AppKit as a template.
    static func menuBarImage(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let markRect = rect.insetBy(dx: size * 0.06, dy: size * 0.06)
            drawMark(
                in: markRect,
                color: .black,
                hexLineWidth: max(1.0, size * 0.048),
                strokeLineWidth: max(1.3, size * 0.075),
                glow: 0,
                drawsNodes: true
            )
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Cyan mark with a soft glow, for in-app brand chips.
    static func neonImage(size: CGFloat = 18, color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            drawMark(
                in: rect,
                color: color,
                hexLineWidth: max(1, size * 0.05),
                strokeLineWidth: max(1.2, size * 0.075),
                glow: size * 0.06,
                drawsNodes: true
            )
            return true
        }
        image.isTemplate = false
        return image
    }

    static func drawMark(
        in rect: NSRect,
        color: NSColor,
        hexLineWidth: CGFloat,
        strokeLineWidth: CGFloat,
        glow: CGFloat,
        drawsNodes: Bool
    ) {
        let context = NSGraphicsContext.current
        context?.saveGraphicsState()

        if glow > 0 {
            let shadow = NSShadow()
            shadow.shadowColor = color.withAlphaComponent(0.55)
            shadow.shadowBlurRadius = glow
            shadow.shadowOffset = .zero
            shadow.set()
        }

        color.setStroke()
        let hex = hexagon(in: rect)
        hex.lineWidth = hexLineWidth
        hex.stroke()

        let glyph = letterN(in: rect)
        glyph.strokes.lineWidth = strokeLineWidth
        glyph.strokes.stroke()

        color.setFill()
        if drawsNodes {
            for node in glyph.nodes {
                NSBezierPath(ovalIn: node).fill()
            }
        }

        context?.restoreGraphicsState()
    }
}

/// Renders the full-colour application icon: a dark HUD squircle with the neon mark on a faint grid.
enum BrandIcon {
    static func draw(in rect: NSRect) {
        let scale = rect.width / 1024.0
        func p(_ value: CGFloat) -> CGFloat { value * scale }

        NSGraphicsContext.current?.shouldAntialias = true

        // Squircle body with a near-black vertical gradient.
        let body = NSBezierPath(
            roundedRect: rect.insetBy(dx: p(44), dy: p(44)),
            xRadius: p(210),
            yRadius: p(210)
        )
        let gradient = NSGradient(colors: [
            NSColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),
            NSColor(srgbRed: 0.898, green: 0.937, blue: 0.961, alpha: 1.0),
        ])
        gradient?.draw(in: body, angle: -90)

        let context = NSGraphicsContext.current
        context?.saveGraphicsState()
        body.addClip()

        // Engineering grid, aligned to the icon's own rhythm.
        let grid = NSBezierPath()
        grid.lineWidth = p(1.5)
        let spacing = p(64)
        var offset = p(44)
        while offset < rect.width {
            grid.move(to: NSPoint(x: offset, y: p(44)))
            grid.line(to: NSPoint(x: offset, y: rect.height - p(44)))
            grid.move(to: NSPoint(x: p(44), y: offset))
            grid.line(to: NSPoint(x: rect.width - p(44), y: offset))
            offset += spacing
        }
        NSColor(srgbRed: 0.055, green: 0.647, blue: 0.718, alpha: 0.11).setStroke()
        grid.stroke()

        // Top scan glow.
        let glow = NSGradient(colors: [
            NSColor(srgbRed: 0.133, green: 0.827, blue: 0.933, alpha: 0.20),
            NSColor(srgbRed: 0.133, green: 0.827, blue: 0.933, alpha: 0.0),
        ])
        glow?.draw(
            in: NSBezierPath(rect: NSRect(x: p(44), y: p(760), width: rect.width - p(88), height: p(220))),
            angle: -90
        )
        context?.restoreGraphicsState()

        // Neon mark, sized to sit comfortably inside the squircle.
        let markRect = rect.insetBy(dx: p(196), dy: p(196))
        BrandMark.drawMark(
            in: markRect,
            color: NSColor(srgbRed: 0.055, green: 0.647, blue: 0.718, alpha: 1.0),
            hexLineWidth: p(24),
            strokeLineWidth: p(42),
            glow: p(26),
            drawsNodes: true
        )

        // Hairline rim keeps the tile from melting into a dark desktop.
        let rim = NSBezierPath(
            roundedRect: rect.insetBy(dx: p(44.5), dy: p(44.5)),
            xRadius: p(210),
            yRadius: p(210)
        )
        NSColor(srgbRed: 0.055, green: 0.647, blue: 0.718, alpha: 0.22).setStroke()
        rim.lineWidth = p(2)
        rim.stroke()
    }
}