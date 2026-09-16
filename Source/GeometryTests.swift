import Foundation
import CoreGraphics

@main enum GeometryTests {
    static func main() {
        for area in [CGRect(x: 0, y: 25, width: 1513, height: 899), CGRect(x: -1920, y: -1000, width: 1920, height: 1080)] {
            let current = CGRect(x: 100, y: 100, width: 640, height: 480)
            let left = Layout.left.rect(in: area, current: current)
            let right = Layout.right.rect(in: area, current: current)
            assert(left.maxX == right.minX && left.width + right.width == area.width)
            for layout in Layout.allCases where layout != .restore {
                assert(area.contains(layout.rect(in: area, current: current)))
            }
            let quarters = [Layout.topLeft, .topRight, .bottomLeft, .bottomRight].map { $0.rect(in: area, current: current) }
            assert(quarters.reduce(0) { $0 + $1.width * $1.height } == area.width * area.height)
            assert(Layout.edge(at: CGPoint(x: area.minX, y: area.minY), in: area) == .topLeft)
            assert(Layout.edge(at: CGPoint(x: area.maxX, y: area.maxY), in: area) == .bottomRight)
            assert(Layout.edge(at: CGPoint(x: area.midX, y: area.minY), in: area) == .maximize)
            assert(Layout.edge(at: CGPoint(x: area.midX, y: area.midY), in: area) == nil)
            assert(Layout.edge(at: CGPoint(x: area.maxX + 100, y: area.midY), in: area) == nil)
        }
        print("PASS: halves, quarters, odd pixels, negative display coordinates, containment, edge detection")
    }
}
