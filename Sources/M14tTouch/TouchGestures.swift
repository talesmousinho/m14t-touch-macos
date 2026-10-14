import CoreGraphics

struct TouchContact: Equatable {
    let id: Int
    let point: CGPoint
}

enum TouchAction: Equatable {
    case move(CGPoint)
    case down(CGPoint)
    case drag(CGPoint)
    case up(CGPoint)
    case scroll(at: CGPoint, dx: Double, dy: Double)
}

struct TouchGestures {
    private enum State {
        case idle
        case pending(first: TouchContact, latest: CGPoint, began: Double)
        case dragging(id: Int, last: CGPoint)
        case scrolling(ids: Set<Int>, previous: CGPoint, anchor: CGPoint)
        case suppressed
    }
    private var state: State = .idle
    private let chordDelay = 0.12
    private let dragThreshold = 1.5

    var isPending: Bool {
        if case .pending = state { return true }
        return false
    }

    mutating func update(_ contacts: [TouchContact], at time: Double, inputEnabled: Bool = true) -> [TouchAction] {
        // While video is unavailable, still acknowledge releases from USB HID.
        // No new gestures may start, but a completed lift permits the next one.
        guard inputEnabled else {
            let actions = interrupt()
            if contacts.isEmpty { state = .idle }
            return actions
        }
        let ids = Set(contacts.map(\.id))
        guard contacts.count <= 2, ids.count == contacts.count else {
            let actions = cancel()
            state = .suppressed
            return actions
        }
        if contacts.isEmpty {
            let actions: [TouchAction]
            switch state {
            case .pending(_, let latest, _): actions = [.down(latest), .up(latest)]
            case .dragging(_, let last): actions = [.up(last)]
            default: actions = []
            }
            state = .idle
            return actions
        }
        if case .suppressed = state { return [] }

        if contacts.count == 2 {
            let center = CGPoint(x: (contacts[0].point.x + contacts[1].point.x) / 2,
                                 y: (contacts[0].point.y + contacts[1].point.y) / 2)
            if case .scrolling(let previousIDs, let previous, let anchor) = state {
                guard previousIDs == ids else { state = .suppressed; return [] }
                state = .scrolling(ids: ids, previous: center, anchor: anchor)
                let dx = center.x - previous.x
                let dy = center.y - previous.y
                return dx == 0 && dy == 0 ? [] : [.scroll(at: anchor, dx: dx, dy: dy)]
            }
            var actions: [TouchAction] = []
            if case .dragging(_, let last) = state { actions.append(.up(last)) }
            state = .scrolling(ids: ids, previous: center, anchor: center)
            actions.append(.move(center))
            return actions
        }

        let contact = contacts[0]
        switch state {
        case .idle:
            state = .pending(first: contact, latest: contact.point, began: time)
            return [.move(contact.point)]
        case .pending(let first, _, let began):
            guard first.id == contact.id else { state = .suppressed; return [] }
            guard time - began >= chordDelay else {
                state = .pending(first: first, latest: contact.point, began: began)
                return []
            }
            state = .dragging(id: contact.id, last: first.point)
            return [.down(first.point)] + update(contacts, at: time)
        case .dragging(let id, let last):
            guard id == contact.id else { state = .suppressed; return [.up(last)] }
            guard abs(contact.point.x - last.x) > dragThreshold || abs(contact.point.y - last.y) > dragThreshold else { return [] }
            state = .dragging(id: id, last: contact.point)
            return [.drag(contact.point)]
        case .scrolling:
            // A scroll never becomes a click when one finger is lifted first.
            state = .suppressed
            return []
        case .suppressed:
            return []
        }
    }

    mutating func cancel() -> [TouchAction] {
        defer { state = .idle }
        if case .dragging(_, let last) = state { return [.up(last)] }
        return []
    }

    /// After a bad frame, contact state is unknown. Release any button and wait
    /// for a valid all-fingers-up frame before allowing another click or drag.
    mutating func interrupt() -> [TouchAction] {
        let actions = cancel()
        state = .suppressed
        return actions
    }
}
