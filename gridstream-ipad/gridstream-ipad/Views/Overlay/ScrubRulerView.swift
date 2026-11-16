//
//  ScrubRulerView.swift
//  gridstream-ipad
//
//  A horizontal ruler displayed at the finger's Y position during
//  precision and frame-by-frame scrubbing modes.
//

import SwiftUI

struct ScrubRulerView: View {
    let centerX: CGFloat
    let centerY: CGFloat
    let anchorTime: Double
    let currentTime: Double
    let visibleRange: Double
    let containerWidth: CGFloat
    let scrubLevel: ScrubLevel
    let frameRate: Double

    private let rulerHeight: CGFloat = 44
    private let majorTickH: CGFloat = 14
    private let midTickH: CGFloat = 9
    private let minorTickH: CGFloat = 5
    private let indicatorSize: CGFloat = 6

    private var rulerWidth: CGFloat { containerWidth * 0.82 }
    private var leftTime: Double { anchorTime - visibleRange / 2 }
    private var rightTime: Double { anchorTime + visibleRange / 2 }

    var body: some View {
        Canvas(renderer: { context, size in
            drawRuler(context: &context, size: size)
        })
        .frame(width: rulerWidth, height: rulerHeight)
        .position(x: centerX, y: centerY + 40)
    }

    // MARK: - Drawing

    private func drawRuler(context: inout GraphicsContext, size: CGSize) {
        let w: CGFloat = size.width
        let midY: CGFloat = size.height / 2

        // Background
        let bgRect = CGRect(x: 0, y: 0, width: w, height: size.height)
        context.fill(Path(roundedRect: bgRect, cornerRadius: size.height / 2), with: .color(.black.opacity(0.55)))

        guard visibleRange > 0 else { return }

        let ticks = computeTicks()
        drawTicks(ticks: ticks, context: &context, rulerWidth: w, midY: midY)
        drawCurrentIndicator(context: &context, rulerWidth: w, midY: midY)
    }

    private func drawTicks(ticks: [TickMark], context: inout GraphicsContext, rulerWidth w: CGFloat, midY: CGFloat) {
        for tick in ticks {
            let fraction: Double = (tick.time - leftTime) / visibleRange
            guard fraction >= 0, fraction <= 1 else { continue }
            let x: CGFloat = CGFloat(fraction) * w

            let h: CGFloat
            let opacity: Double
            switch tick.kind {
            case .major:  h = majorTickH;  opacity = 0.9
            case .mid:    h = midTickH;    opacity = 0.5
            case .minor:  h = minorTickH;  opacity = 0.3
            }

            let rect = CGRect(x: x - 0.5, y: midY - h / 2, width: 1, height: h)
            context.fill(Path(rect), with: .color(.white.opacity(opacity)))

            if tick.kind == .major {
                drawTickLabel(tick: tick, x: x, h: h, midY: midY, rulerWidth: w, context: &context)
            }
        }
    }

    private func drawTickLabel(tick: TickMark, x: CGFloat, h: CGFloat, midY: CGFloat, rulerWidth: CGFloat, context: inout GraphicsContext) {
        let label: String = formatTickTime(tick.time)
        let text = Text(label)
            .font(.system(size: 8, weight: .medium, design: .monospaced))
            .foregroundStyle(.white.opacity(0.7))
        let resolved = context.resolve(text)
        let textSize = resolved.measure(in: CGSize(width: 80, height: 20))
        let drawY: CGFloat = midY + h / 2 + textSize.height / 2 + 1
        // Clamp horizontally so edge labels stay within the ruler bounds
        let halfW = textSize.width / 2
        let clampedX = min(max(x, halfW + 4), rulerWidth - halfW - 4)
        context.draw(resolved, at: CGPoint(x: clampedX, y: drawY), anchor: .center)
    }

    private func drawCurrentIndicator(context: inout GraphicsContext, rulerWidth w: CGFloat, midY: CGFloat) {
        let frac: Double = (currentTime - leftTime) / visibleRange
        guard frac >= 0, frac <= 1 else { return }
        let cx: CGFloat = CGFloat(frac) * w
        let iy: CGFloat = midY - majorTickH / 2 - 3
        let s: CGFloat = indicatorSize

        var tri = Path()
        tri.move(to: CGPoint(x: cx, y: iy + s))
        tri.addLine(to: CGPoint(x: cx - s / 2, y: iy))
        tri.addLine(to: CGPoint(x: cx + s / 2, y: iy))
        tri.closeSubpath()

        let color: Color = scrubLevel == .frameByFrame ? .yellow : .accentColor
        context.fill(tri, with: .color(color))
    }

    // MARK: - Tick Computation

    private enum TickKind { case major, mid, minor }

    private struct TickMark {
        let time: Double
        let kind: TickKind
    }

    private func computeTicks() -> [TickMark] {
        switch scrubLevel {
        case .normal:
            return []
        case .precision:
            return computePrecisionTicks()
        case .frameByFrame:
            return computeFrameTicks()
        }
    }

    private func computePrecisionTicks() -> [TickMark] {
        var ticks: [TickMark] = []
        let majorInterval = chooseMajorInterval()
        let midInterval = majorInterval / 2
        let start = floor(leftTime / midInterval) * midInterval
        var t = start
        while t <= rightTime {
            let isMajor = abs(t.remainder(dividingBy: majorInterval)) < 0.001
            ticks.append(TickMark(time: t, kind: isMajor ? .major : .mid))
            t += midInterval
        }
        return ticks
    }

    private func computeFrameTicks() -> [TickMark] {
        var ticks: [TickMark] = []
        let frameDur: Double = 1.0 / max(frameRate, 1.0)

        // Major ticks at 1s
        var mt = floor(leftTime)
        while mt <= rightTime {
            ticks.append(TickMark(time: mt, kind: .major))
            mt += 1.0
        }

        // Minor ticks per frame (skip if too dense)
        let pxPerFrame = Double(rulerWidth) * frameDur / visibleRange
        guard pxPerFrame >= 3 else { return ticks }

        let frameStart = floor(leftTime / frameDur) * frameDur
        var ft = frameStart
        while ft <= rightTime {
            let nearMajor = ticks.contains { $0.kind == .major && abs($0.time - ft) < frameDur * 0.4 }
            if !nearMajor {
                ticks.append(TickMark(time: ft, kind: .minor))
            }
            ft += frameDur
        }
        return ticks
    }

    private func chooseMajorInterval() -> Double {
        let raw = visibleRange / 8.0
        let intervals: [Double] = [0.5, 1, 2, 5, 10, 15, 30, 60]
        return intervals.first { $0 >= raw } ?? 60
    }

    // MARK: - Time Formatting

    private func formatTickTime(_ time: Double) -> String {
        let clamped = max(0, time)
        let total = Int(clamped)
        let m = total / 60
        let s = total % 60
        if scrubLevel == .frameByFrame {
            let ms = Int((clamped - Double(total)) * 1000)
            return String(format: "%d:%02d.%03d", m, s, ms)
        }
        return String(format: "%d:%02d", m, s)
    }
}
