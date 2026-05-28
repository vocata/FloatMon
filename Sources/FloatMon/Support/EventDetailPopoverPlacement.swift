import CoreGraphics

enum EventDetailPopoverPlacement {
    static func frame(
        for anchor: CGPoint,
        in containerSize: CGSize,
        popoverSize: CGSize,
        margin: CGFloat,
        pointerOffset: CGSize = CGSize(width: 8, height: 8)
    ) -> CGRect {
        let center = center(
            for: anchor,
            in: containerSize,
            popoverSize: popoverSize,
            margin: margin,
            pointerOffset: pointerOffset
        )

        return CGRect(
            x: center.x - popoverSize.width / 2,
            y: center.y - popoverSize.height / 2,
            width: popoverSize.width,
            height: popoverSize.height
        )
    }

    static func center(
        for anchor: CGPoint,
        in containerSize: CGSize,
        popoverSize: CGSize,
        margin: CGFloat,
        pointerOffset: CGSize = CGSize(width: 8, height: 8)
    ) -> CGPoint {
        let maxX = max(margin, containerSize.width - popoverSize.width - margin)
        let maxY = max(margin, containerSize.height - popoverSize.height - margin)
        let origin = CGPoint(
            x: min(max(anchor.x + pointerOffset.width, margin), maxX),
            y: min(max(anchor.y + pointerOffset.height, margin), maxY)
        )

        return CGPoint(
            x: origin.x + popoverSize.width / 2,
            y: origin.y + popoverSize.height / 2
        )
    }
}
