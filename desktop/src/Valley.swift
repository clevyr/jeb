// Where the stage goes, in scene pixels (bottom-left origin): one strip on the road
// above the Dock, which is the whole place on show (the homestead, a camp, or the
// road between). Inside the safe area: above the Dock, below the menu bar, clear of
// a side Dock.

import AppKit

struct Valley: Equatable {
    let layout: Layout
    let farmX: Int, farmWidth: Int, road: Int   // the stage strip
    let left: Int                                // the safe area's left edge

    init(layout: Layout) {
        self.layout = layout
        let avail = layout.width - layout.left - layout.right
        farmWidth = min(460, avail - 4)
        farmX = layout.left + (avail - farmWidth) / 2
        road = layout.bottom
        left = layout.left
    }
}
