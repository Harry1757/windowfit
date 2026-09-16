import Foundation
import CoreGraphics

enum Layout: Int, CaseIterable {
    case left, right, top, bottom, topLeft, topRight, bottomLeft, bottomRight, maximize, center, restore

    var title: String {
        ["왼쪽 절반", "오른쪽 절반", "위쪽 절반", "아래쪽 절반", "왼쪽 위", "오른쪽 위", "왼쪽 아래", "오른쪽 아래", "화면에 맞추기", "가운데로", "원래 크기로"][rawValue]
    }
    var key: String { ["←", "→", "↑", "↓", "U", "I", "J", "K", "↩", "C", "⌫"][rawValue] }
    var keyCode: UInt32 { [123, 124, 126, 125, 32, 34, 38, 40, 36, 8, 51][rawValue] }

    // All geometry uses Accessibility coordinates (origin at the primary display's top left).
    func rect(in area: CGRect, current: CGRect) -> CGRect {
        let x = area.minX, y = area.minY, w = area.width, h = area.height
        let halfW = floor(w / 2), halfH = floor(h / 2)
        switch self {
        case .left: return CGRect(x: x, y: y, width: halfW, height: h)
        case .right: return CGRect(x: x + halfW, y: y, width: w - halfW, height: h)
        case .top: return CGRect(x: x, y: y, width: w, height: halfH)
        case .bottom: return CGRect(x: x, y: y + halfH, width: w, height: h - halfH)
        case .topLeft: return CGRect(x: x, y: y, width: halfW, height: halfH)
        case .topRight: return CGRect(x: x + halfW, y: y, width: w - halfW, height: halfH)
        case .bottomLeft: return CGRect(x: x, y: y + halfH, width: halfW, height: h - halfH)
        case .bottomRight: return CGRect(x: x + halfW, y: y + halfH, width: w - halfW, height: h - halfH)
        case .maximize: return area
        case .center:
            let size = CGSize(width: min(current.width, w), height: min(current.height, h))
            return CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height)
        case .restore: return current
        }
    }
    static func edge(at p: CGPoint, in screen: CGRect) -> Layout? {
        guard screen.insetBy(dx: -1, dy: -1).contains(p) else { return nil }
        let left = p.x <= screen.minX + 18, right = p.x >= screen.maxX - 18
        let top = p.y <= screen.minY + 18, bottom = p.y >= screen.maxY - 18
        let cornerTop = p.y <= screen.minY + 90, cornerBottom = p.y >= screen.maxY - 90
        if left && cornerTop || top && p.x <= screen.minX + 90 { return .topLeft }
        if right && cornerTop || top && p.x >= screen.maxX - 90 { return .topRight }
        if left && cornerBottom || bottom && p.x <= screen.minX + 90 { return .bottomLeft }
        if right && cornerBottom || bottom && p.x >= screen.maxX - 90 { return .bottomRight }
        if left { return .left }; if right { return .right }
        if top { return .maximize }; if bottom { return .bottom }
        return nil
    }
}
