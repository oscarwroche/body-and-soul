import Foundation

struct ScoreLayout {
    static let height: CGFloat = 188
    static let bottomLine: CGFloat = 112
    static let step: CGFloat = 6
    static let selectionHalfWidth: CGFloat = 22

    enum Click: Equatable {
        case select(Int)
        case movePitch(Int)
        case append(Int)
    }

    struct Fragment {
        let index: Int
        var x: CGFloat
        let bar: Int
        let pitch: Int?
        let value: NoteValue
        let dotted: Bool
        let accidental: Accidental?
        let tiedFromPrevious: Bool
        let beamBeat: Int?
    }

    let meter: Meter
    let key: KeySignature
    var firstX: CGFloat { 105 + CGFloat(key.positions.count * 11) }
    var meterX: CGFloat { firstX - 32 }
    var continuesTie = false
    var fragments: [Fragment] = []
    var barlines: [CGFloat] = []
    var appendX: CGFloat
    var firstBar: Int { fragments.first?.bar ?? emptyRowBar }
    private var entryBar: Int { barlines.count + 1 }
    private var emptyRowBar = 1
    private var acceptsAppend = true

    init(_ notes: [ScoreEvent], meter: Meter = .fourFour, key: KeySignature = .c, spacing: CGFloat = 1) {
        self.meter = meter
        self.key = key
        appendX = 0
        var x = firstX
        var offset = 0
        let beatTicks = NoteValue.quarter.ticks(dotted: meter == .sixEight)
        var measureAccidentals: [Int: Accidental] = [:]
        for (index, note) in notes.enumerated() {
            var remaining = note.ticks
            while remaining > 0 {
                let continuation = remaining != note.ticks
                let available = min(remaining, meter.ticks - offset)
                let (value, dotted, ticks) = Self.duration(fitting: available)
                var symbol: Accidental?
                if let pitch = note.pitch, !continuation {
                    let signature = key.accidental(for: pitch)
                    let spelling = note.accidental ?? signature
                    let previous = measureAccidentals[pitch] ?? signature
                    symbol = spelling != previous || note.accidental == .natural ? spelling : nil
                    measureAccidentals[pitch] = spelling
                }
                let beat = note.pitch != nil && value.flags > 0 && offset % beatTicks + ticks <= beatTicks
                    ? offset / beatTicks : nil
                fragments.append(Fragment(index: index, x: x, bar: barlines.count + 1, pitch: note.pitch, value: value,
                                          dotted: dotted, accidental: symbol, tiedFromPrevious: continuation,
                                          beamBeat: beat))
                remaining -= ticks
                offset += ticks
                x += (44 + CGFloat(ticks) * 0.45) * spacing
                if offset == meter.ticks {
                    barlines.append(x - 13)
                    x += 14
                    offset = 0
                    measureAccidentals.removeAll()
                }
            }
        }
        appendX = x
    }

    func index(at x: CGFloat, entryIndex: Int? = nil) -> Int? {
        guard x >= firstX - Self.selectionHalfWidth else { return nil }
        let appendStart = fragments.last.map { $0.x + Self.selectionHalfWidth } ?? firstX - Self.selectionHalfWidth
        if let entryIndex, acceptsAppend, x >= appendStart { return entryIndex }
        return nearestEvent(to: x)
    }

    func click(at point: CGPoint, cursor: Int, entryIndex: Int) -> Click? {
        if let selected = event(at: point) { return .select(selected) }
        guard let index = index(at: point.x, entryIndex: entryIndex) else { return nil }
        let pitch = Self.pitch(at: point.y)
        if index == entryIndex { return .append(pitch) }
        if fragments.contains(where: { $0.index == cursor && $0.pitch != nil }) { return .movePitch(pitch) }
        return .select(index)
    }

    func event(at point: CGPoint) -> Int? {
        fragments.first { fragment in
            guard abs(fragment.x - point.x) <= 10 else { return false }
            if let pitch = fragment.pitch {
                return abs(Self.y(for: pitch) - point.y) < Self.step
            }
            return abs(Self.y(for: 4) - point.y) <= 20
        }?.index
    }

    private func nearestEvent(to x: CGFloat) -> Int? {
        fragments.min { abs($0.x - x) < abs($1.x - x) }?.index
    }

    var beamGroups: [Range<Int>] {
        var groups: [Range<Int>] = []
        var start = 0
        while start < fragments.count {
            let first = fragments[start]
            var end = start + 1
            if let beat = first.beamBeat {
                while end < fragments.count, fragments[end].bar == first.bar, fragments[end].beamBeat == beat {
                    end += 1
                }
                if end - start > 1 { groups.append(start..<end) }
            }
            start = end
        }
        return groups
    }

    func wrappedRows(width: CGFloat, includeEntry: Bool = false) -> [Self] {
        guard !fragments.isEmpty else { return [self] }
        var rows: [Self] = []
        var start = 0
        var bar = 0
        while start < fragments.count {
            let shift = fragments[start].x - firstX
            let right = shift + width - 37
            var end = start + 1
            while end < fragments.count, fragments[end].x <= right { end += 1 }
            if end < fragments.count {
                let fittingBars = barlines[bar...].prefix { $0 <= right && $0 < fragments[end].x }
                if let breakX = fittingBars.last,
                   let nextBar = (start + 1..<end).first(where: { fragments[$0].x > breakX }) {
                    end = nextBar
                }
            }
            var row = self
            row.fragments = fragments[start..<end].map {
                var fragment = $0
                fragment.x -= shift
                return fragment
            }
            let limit = end < fragments.count ? fragments[end].x : .infinity
            row.barlines = []
            while bar < barlines.count, barlines[bar] < limit {
                row.barlines.append(min(width - 16, barlines[bar] - shift))
                bar += 1
            }
            row.appendX = appendX - shift
            row.continuesTie = end < fragments.count && fragments[end].tiedFromPrevious
            row.acceptsAppend = end == fragments.count
            rows.append(row)
            start = end
        }
        if includeEntry, let last = rows.last, last.appendX > width - 38 {
            var entryRow = Self([], meter: meter, key: key)
            entryRow.emptyRowBar = entryBar
            rows.append(entryRow)
        }
        return rows
    }

    static func y(for pitch: Int) -> CGFloat { bottomLine - CGFloat(pitch) * step }

    static func pitch(at y: CGFloat) -> Int {
        min(ScoreEvent.pitchRange.upperBound,
            max(ScoreEvent.pitchRange.lowerBound, Int(((bottomLine - y) / step).rounded())))
    }

    static func duration(fitting ticks: Int) -> (NoteValue, Bool, Int) {
        for value in NoteValue.allCases {
            let dotted = value.ticks(dotted: true)
            if value != .sixtyFourth && dotted <= ticks { return (value, true, dotted) }
            if value.rawValue <= ticks { return (value, false, value.rawValue) }
        }
        preconditionFailure("A score fragment must contain at least one tick")
    }
}
