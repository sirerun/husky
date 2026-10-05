import CoreGraphics

struct HuskyPanelScreenArea {
    let frame: CGRect
    let visibleFrame: CGRect
}

enum HuskyPanelGeometry {
    struct Restoration {
        let frame: CGRect
        let screenIndex: Int
        let usedFallbackScreen: Bool
    }

    static func initialFrame(
        in visibleFrame: CGRect,
        desiredSize: CGSize = CGSize(width: 560, height: 680),
        inset: CGFloat = 24
    ) -> CGRect {
        let size = fit(desiredSize, in: visibleFrame, inset: inset)
        return CGRect(
            x: visibleFrame.minX + inset,
            y: visibleFrame.minY + inset,
            width: size.width,
            height: size.height
        )
    }

    static func restore(
        savedFrame: CGRect,
        screens: [HuskyPanelScreenArea],
        activeScreenIndex: Int?,
        inset: CGFloat = 24
    ) -> Restoration? {
        // Prefer the display that currently hosts the saved rectangle. The pointer's
        // display is only a fallback when the saved display is no longer connected.
        let host = screens.enumerated()
            .map { index, screen in
                (index, screen, overlapArea(savedFrame, screen.frame))
            }
            .filter { $0.2 > 0 }
            .max { $0.2 < $1.2 }

        if let (screenIndex, screen, _) = host {
            let frame = screen.visibleFrame.contains(savedFrame)
                ? savedFrame
                : clamp(savedFrame, to: screen.visibleFrame, inset: inset)
            return Restoration(frame: frame, screenIndex: screenIndex, usedFallbackScreen: false)
        }

        guard let activeScreenIndex, screens.indices.contains(activeScreenIndex) else { return nil }
        let activeScreen = screens[activeScreenIndex]
        let frame = initialFrame(in: activeScreen.visibleFrame, inset: inset)
        return Restoration(frame: frame, screenIndex: activeScreenIndex, usedFallbackScreen: true)
    }

    private static func clamp(_ frame: CGRect, to visibleFrame: CGRect, inset: CGFloat) -> CGRect {
        let size = fit(frame.size, in: visibleFrame, inset: inset)
        let minimumX = visibleFrame.minX + inset
        let minimumY = visibleFrame.minY + inset
        let maximumX = max(minimumX, visibleFrame.maxX - inset - size.width)
        let maximumY = max(minimumY, visibleFrame.maxY - inset - size.height)

        return CGRect(
            x: min(max(frame.minX, minimumX), maximumX),
            y: min(max(frame.minY, minimumY), maximumY),
            width: size.width,
            height: size.height
        )
    }

    private static func fit(_ size: CGSize, in visibleFrame: CGRect, inset: CGFloat) -> CGSize {
        let availableWidth = max(1, visibleFrame.width - inset * 2)
        let availableHeight = max(1, visibleFrame.height - inset * 2)
        return CGSize(
            width: min(size.width, availableWidth),
            height: min(size.height, availableHeight)
        )
    }

    private static func overlapArea(_ first: CGRect, _ second: CGRect) -> CGFloat {
        let overlap = first.intersection(second)
        guard !overlap.isNull, !overlap.isEmpty else { return 0 }
        return overlap.width * overlap.height
    }
}
