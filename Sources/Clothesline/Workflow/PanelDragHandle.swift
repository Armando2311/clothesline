import AppKit
import SwiftUI

struct PanelDragHandle: NSViewRepresentable {
    var move: (CGFloat) -> Void
    func makeNSView(context: Context) -> VerticalGrip { VerticalGrip(move: move) }
    func updateNSView(_ view: VerticalGrip,context: Context) { view.move = move }
}
final class VerticalGrip: NSView {
    var move: (CGFloat) -> Void
    private var lastY: CGFloat?
    init(move: @escaping (CGFloat) -> Void) {
        self.move = move
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Move clothesline vertically")
        setAccessibilityHelp("Drag up or down to uncover files behind the line")
    }
    required init?(coder: NSCoder) { fatalError("not supported") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds,cursor: .resizeUpDown) }
    override func draw(_ dirtyRect: NSRect) {
        let image = NSImage(systemSymbolName: "arrow.up.and.down",accessibilityDescription: nil)
        image?.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.labelColor]))?.draw(in: bounds.insetBy(dx: 5,dy: 4))
    }
    private func screenY(_ event: NSEvent) -> CGFloat {
        window?.convertPoint(toScreen: event.locationInWindow).y ?? event.locationInWindow.y
    }
    override func mouseDown(with event: NSEvent) { lastY = screenY(event) }
    override func mouseDragged(with event: NSEvent) {
        let y = screenY(event)
        if let lastY { move(y-lastY) }
        lastY = y
    }
    override func mouseUp(with event: NSEvent) { lastY = nil }
}
