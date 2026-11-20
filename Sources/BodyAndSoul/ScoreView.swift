import SwiftUI
import UniformTypeIdentifiers

struct ScoreView: View {
    @Binding var notes: [ScoreEvent]
    @Binding var meter: Meter
    @Binding var key: KeySignature
    @Binding var instrument: String
    let title: String
    let pdfTitle: String
    @State private var exportError: String?
    @State private var confirmingClear = false
    @State private var cursor = 0
    @State private var zoom = 100
    @State private var entry = ScoreEvent(pitch: ScoreEvent.middleB)
    @FocusState private var focused: Bool

    private var scale: CGFloat { CGFloat(zoom) / 100 }
    private var selected: ScoreEvent { cursor < notes.count ? notes[cursor] : entry }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Transcription").font(.headline)
                TextField("Instrument (optional)", text: $instrument)
                    .frame(width: 170)
                    .help("Label this project and its PDF exports")
                Spacer()
                Button("Clear Score…") { confirmingClear = true }
                    .disabled(notes.isEmpty)
                    .alert("Clear all notes and rests?", isPresented: $confirmingClear) {
                        Button("Cancel", role: .cancel) {}
                        Button("Clear Score", role: .destructive, action: clearScore)
                    } message: {
                        Text("Your recording, loop, speed, key, and meter will stay in the project. Press ⌘Z to undo.")
                    }
                Button("Export PDF…", action: exportPDF)
                    .disabled(notes.isEmpty)
                Text(cursor < notes.count ? "\(cursor + 1) / \(notes.count)  ·  \(selected.pitchLabel(in: key))" :
                     "Next  ·  \(entry.pitchLabel(in: key))")
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            scoreSettings
            controls
            staff
            Text("Click past the last note to add one. Click within the written staff to move a selected note. End returns to note entry. A–G writes or edits, ↑↓ moves pitch, ←→ selects, Return inserts.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onChange(of: notes.count) { _, count in cursor = min(cursor, count) }
        .alert("Couldn’t Export PDF", isPresented: Binding(
            get: { exportError != nil }, set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Picker("Duration", selection: Binding(get: { selected.value }, set: { setValue($0) })) {
                ForEach(Array(NoteValue.inputValues.enumerated()), id: \.element) { index, value in
                    Text("\(value.label)   \(index + 1)").tag(value)
                }
            }
            .fixedSize()
            Toggle("Dot", isOn: Binding(get: { selected.dotted }, set: { setDotted($0) }))
                .toggleStyle(.button)
                .help("Toggle dotted rhythm (.)")
            Button("Rest", action: writeOrToggleRest)
                .help("Insert a rest or toggle the selected event (R)")
            Divider().frame(height: 18)
            Picker("Accidental", selection: Binding(
                get: { selected.accidental?.rawValue ?? "" },
                set: { setAccidental(Accidental(rawValue: $0)) }
            )) {
                Text("None").tag("")
                ForEach(Accidental.allCases, id: \.self) { accidental in
                    Text(accidental.rawValue).tag(accidental.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .disabled(selected.pitch == nil)
            Spacer()
            Button("Insert") { insert(entry) }.help("Insert at the cursor (Return)")
            Button(role: .destructive, action: delete) { Image(systemName: "trash") }
                .disabled(notes.isEmpty)
                .help("Delete the selected event or last event (Delete)")
                .accessibilityLabel("Delete event")
        }
        .controlSize(.small)
    }

    private var scoreSettings: some View {
        HStack(spacing: 10) {
            Picker("Key", selection: $key) {
                ForEach(KeySignature.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .help("Key signature for the written part")
            .fixedSize()
            Picker("Meter", selection: $meter) {
                ForEach(Meter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .fixedSize()
            Divider().frame(height: 18)
            Picker("Score Zoom", selection: $zoom) {
                ForEach([75, 100, 125, 150, 175], id: \.self) { percent in
                    Text("\(percent)%").tag(percent)
                }
            }
            .fixedSize()
        }
        .controlSize(.small)
    }

    private func exportPDF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = title + ".pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let pdf = try ScorePDF.render(notes, meter: meter, key: key, title: pdfTitle, instrument: instrument)
            try pdf.write(to: url, options: .atomic)
        } catch {
            exportError = error.localizedDescription
        }
    }

    private var staff: some View {
        GeometryReader { geometry in
            let rowWidth = max(1, geometry.size.width - 24) / scale
            let layout = ScoreLayout(notes, meter: meter, key: key, spacing: 0.84)
            let rows = layout.wrappedRows(width: rowWidth, includeEntry: true)
            let selectedRow = rows.firstIndex { row in row.fragments.contains { $0.index == cursor } }
            let activeRow = selectedRow ?? rows.count - 1

            ScrollViewReader { scroll in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(rows.indices, id: \.self) { index in
                            let row = rows[index]
                            VStack(alignment: .leading, spacing: 0) {
                                Text("Bar \(row.firstBar)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 16 * scale)
                                    .accessibilityHidden(true)
                                editableStaff(row, width: rowWidth, isLast: index == rows.count - 1)
                            }
                            .id(index)
                        }
                    }
                    .padding(12)
                }
                .onChange(of: cursor) { scroll.scrollTo(activeRow) }
            }
            .background(.background, in: RoundedRectangle(cornerRadius: 8))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(focused ? Color.accentColor.opacity(0.6) : .secondary.opacity(0.2), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
        .frame(minHeight: 160)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress { handle($0) }
        .defaultFocus($focused, true)
    }

    private func editableStaff(_ row: ScoreLayout, width: CGFloat, isLast: Bool) -> some View {
        let height: CGFloat = 160
        return StaffDrawing(layout: row, cursor: cursor, showEntry: isLast && cursor == notes.count)
            .frame(width: width, height: height)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: width * scale, height: height * scale, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { tap in
                let point = CGPoint(x: tap.location.x / scale, y: tap.location.y / scale)
                clickStaff(at: point, in: row)
            })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Bar \(row.firstBar), treble clef, \(meter.numerator) over \(meter.denominator)")
            .accessibilityValue(row.fragments.contains { $0.index == cursor } || (isLast && cursor == notes.count)
                ? "Selected: \(selected.pitchLabel(in: key))" : "")
            .accessibilityHint("Use the arrow keys to select or change pitch. Press Return to insert.")
    }

    private func clickStaff(at point: CGPoint, in row: ScoreLayout) {
        focused = true
        switch row.click(at: point, cursor: cursor, entryIndex: notes.count) {
        case .select(let index):
            cursor = index
        case .movePitch(let pitch):
            writePitch(pitch)
        case .append(let pitch):
            cursor = notes.count
            writePitch(pitch)
        case nil:
            break
        }
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        guard press.modifiers.intersection([.command, .control, .option]).isEmpty else { return .ignored }
        switch press.key {
        case .leftArrow: cursor = max(0, cursor - 1)
        case .rightArrow: cursor = min(notes.count, cursor + 1)
        case .home: cursor = 0
        case .end: cursor = notes.count
        case .upArrow: movePitch(1)
        case .downArrow: movePitch(-1)
        case .return: insert(entry)
        case .delete, .deleteForward: delete()
        default:
            let key = press.characters.lowercased()
            if let number = Int(key), NoteValue.inputValues.indices.contains(number - 1) {
                setValue(NoteValue.inputValues[number - 1])
            } else if let letter = key.first, key.count == 1,
                      let pitch = ScoreEvent.nearestPitch(letter: letter, to: selected.pitch ?? entry.pitch ?? ScoreEvent.middleB) {
                writePitch(pitch)
            } else {
                switch key {
                case "r": writeOrToggleRest()
                case ".": setDotted(!selected.dotted)
                case "[": setAccidental(.flat)
                case "]": setAccidental(.sharp)
                case "\\": setAccidental(.natural)
                default: return .ignored
                }
            }
        }
        return .handled
    }

    private func edit(_ change: (inout ScoreEvent) -> Void) {
        if cursor < notes.count { change(&notes[cursor]) } else { change(&entry) }
    }

    private func setValue(_ value: NoteValue) {
        edit { $0.value = value }
        entry.value = value
        focused = true
    }

    private func setDotted(_ dotted: Bool) {
        edit { $0.dotted = dotted }
        entry.dotted = dotted
        focused = true
    }

    private func setAccidental(_ accidental: Accidental?) {
        guard selected.pitch != nil else { return }
        edit { $0.accidental = accidental }
        focused = true
    }

    private func movePitch(_ offset: Int) {
        let pitch = (selected.pitch ?? entry.pitch ?? ScoreEvent.middleB) + offset
        guard ScoreEvent.pitchRange.contains(pitch) else { return }
        edit {
            $0.pitch = pitch
            $0.accidental = nil
        }
    }

    private func writePitch(_ pitch: Int) {
        if cursor == notes.count {
            let note = ScoreEvent(pitch: pitch, value: entry.value, dotted: entry.dotted,
                                  accidental: entry.accidental)
            insert(note)
        } else {
            edit {
                if $0.pitch != pitch { $0.accidental = nil }
                $0.pitch = pitch
            }
            entry.pitch = pitch
        }
    }

    private func writeOrToggleRest() {
        if cursor == notes.count {
            insert(ScoreEvent(pitch: nil, value: entry.value, dotted: entry.dotted))
        } else {
            edit {
                $0.pitch = $0.pitch == nil ? entry.pitch : nil
                $0.accidental = nil
            }
        }
        focused = true
    }

    private func insert(_ note: ScoreEvent) {
        notes.insert(note, at: cursor)
        cursor += 1
        if let pitch = note.pitch { entry.pitch = pitch }
        entry.accidental = nil
        focused = true
    }

    private func delete() {
        guard !notes.isEmpty else { return }
        let index = min(cursor, notes.count - 1)
        notes.remove(at: index)
        cursor = index
        focused = true
    }

    private func clearScore() {
        notes.removeAll()
        cursor = 0
        entry = ScoreEvent(pitch: ScoreEvent.middleB)
        focused = true
    }
}

struct StaffDrawing: View {
    let layout: ScoreLayout
    let cursor: Int?
    var showEntry = false

    private struct Beam {
        let direction: CGFloat
        let x: CGFloat
        let y: CGFloat
        let slope: CGFloat

        init?(_ notes: ArraySlice<ScoreLayout.Fragment>, height: CGFloat) {
            let positions = notes.compactMap { note in note.pitch.map { (note.x, ScoreLayout.y(for: $0)) } }
            let heights = positions.map { $0.1 }
            guard let first = positions.first, let last = positions.last, last.0 > first.0,
                  let top = heights.min(), let bottom = heights.max() else { return nil }
            let middle = ScoreLayout.y(for: ScoreEvent.middleB)
            direction = bottom - middle > middle - top ? -1 : 1
            x = first.0
            let tilt = min(12, max(-12, last.1 - first.1))
            let slope = tilt / (last.0 - first.0)
            self.slope = slope
            let heightsAtStart = positions.map { $0.1 - ($0.0 - first.0) * slope }
            let stemBase = direction < 0 ? heightsAtStart.min() ?? first.1 : heightsAtStart.max() ?? first.1
            let stemLength: CGFloat = notes.contains { $0.value.flags > 2 } ? 39 : 32
            y = min(height - 5 - max(0, tilt), max(5 - min(0, tilt), stemBase + direction * stemLength))
        }

        func point(at noteX: CGFloat, level: Int = 0) -> CGPoint {
            CGPoint(x: noteX - direction * 5.5, y: y + (noteX - x) * slope - direction * CGFloat(6 * level))
        }
    }

    var body: some View {
        Canvas { context, size in
            for pitch in stride(from: 0, through: 8, by: 2) {
                let y = ScoreLayout.y(for: pitch)
                line(in: context, from: CGPoint(x: 16, y: y), to: CGPoint(x: size.width - 16, y: y), color: .secondary)
            }
            for x in layout.barlines {
                line(in: context, from: CGPoint(x: x, y: ScoreLayout.y(for: 8)),
                     to: CGPoint(x: x, y: ScoreLayout.bottomLine))
            }
            glyph("𝄞", x: 37, y: 98, size: 90, in: context, color: .primary)
            for (index, pitch) in layout.key.positions.enumerated() {
                glyph(layout.key.symbol.rawValue, x: 64 + CGFloat(index * 11), y: ScoreLayout.y(for: pitch),
                      size: 19, in: context, color: .primary)
            }
            glyph(String(layout.meter.numerator), x: layout.meterX, y: 77, size: 24, in: context, color: .primary)
            glyph(String(layout.meter.denominator), x: layout.meterX, y: 101, size: 24, in: context, color: .primary)

            let groups = layout.beamGroups
            var beams: [Int: Beam] = [:]
            for group in groups {
                guard let beam = Beam(layout.fragments[group], height: size.height) else { continue }
                for index in group { beams[index] = beam }
            }
            var previous: ScoreLayout.Fragment?
            for (index, fragment) in layout.fragments.enumerated() {
                let color: Color = fragment.index == cursor ? .accentColor : .primary
                if fragment.index == cursor { highlight(fragment.x, height: size.height, in: context) }
                draw(fragment, beam: beams[index], in: context, color: color)
                if fragment.tiedFromPrevious, let pitch = fragment.pitch {
                    tie(from: previous.map { $0.x + 7 } ?? fragment.x - 22, to: fragment.x - 7,
                        pitch: pitch, in: context, color: color)
                }
                previous = fragment
            }
            for group in groups {
                if let beam = beams[group.lowerBound] { drawBeams(for: group, using: beam, in: context) }
            }
            if layout.continuesTie, let previous, let pitch = previous.pitch {
                tie(from: previous.x + 7, to: min(previous.x + 23, size.width - 12),
                    pitch: pitch, in: context, color: .primary)
            }
            if showEntry {
                highlight(layout.appendX, height: size.height, in: context)
                line(in: context, from: CGPoint(x: layout.appendX, y: 60),
                     to: CGPoint(x: layout.appendX, y: 116), color: .accentColor)
            }
        }
    }

    private func tie(from start: CGFloat, to end: CGFloat, pitch: Int, in context: GraphicsContext, color: Color) {
        let side: CGFloat = pitch >= 4 ? -1 : 1
        let y = ScoreLayout.y(for: pitch) + side * 7
        var path = Path()
        path.move(to: CGPoint(x: start, y: y))
        path.addQuadCurve(to: CGPoint(x: end, y: y),
                          control: CGPoint(x: (start + end) / 2, y: y + side * min(19, (end - start) / 3)))
        context.stroke(path, with: .color(color), lineWidth: 1.3)
    }

    private func highlight(_ x: CGFloat, height: CGFloat, in context: GraphicsContext) {
        let halfWidth = ScoreLayout.selectionHalfWidth
        let rect = CGRect(x: x - halfWidth, y: 5, width: halfWidth * 2, height: height - 10)
        context.fill(Path(roundedRect: rect, cornerRadius: 5), with: .color(.accentColor.opacity(0.10)))
    }

    private func draw(_ note: ScoreLayout.Fragment, beam: Beam?, in context: GraphicsContext, color: Color) {
        let x = note.x
        guard let pitch = note.pitch else {
            drawRest(note, in: context, color: color)
            return
        }
        let y = ScoreLayout.y(for: pitch)
        if pitch <= -2 {
            for step in stride(from: -2, through: pitch, by: -2) { ledger(step, x, in: context, color: color) }
        } else if pitch >= 10 {
            for step in stride(from: 10, through: pitch, by: 2) { ledger(step, x, in: context, color: color) }
        }
        let hollow = note.value == .whole || note.value == .half
        let headWidth: CGFloat = note.value == .whole ? 16 : 13
        var headContext = context
        headContext.translateBy(x: x, y: y)
        headContext.rotate(by: .degrees(note.value == .whole ? 0 : -17))
        let head = Path(ellipseIn: CGRect(x: -headWidth / 2, y: -4.4, width: headWidth, height: 8.8))
        if hollow {
            headContext.fill(head, with: .style(.background))
            headContext.stroke(head, with: .color(color), lineWidth: 1.7)
        } else {
            headContext.fill(head, with: .color(color))
        }

        if let beam {
            let tip = beam.point(at: x)
            line(in: context, from: CGPoint(x: tip.x, y: y), to: tip, color: color)
        } else if note.value != .whole {
            let direction: CGFloat = pitch >= 4 ? 1 : -1
            let stemX = x - direction * 5.5
            let tip = y + direction * (note.value.flags > 2 ? 39 : 32)
            line(in: context, from: CGPoint(x: stemX, y: y), to: CGPoint(x: stemX, y: tip), color: color)
            for flag in 0..<note.value.flags {
                let flagY = tip - direction * CGFloat(6 * flag)
                var curve = Path()
                curve.move(to: CGPoint(x: stemX, y: flagY))
                curve.addQuadCurve(to: CGPoint(x: stemX + 9, y: flagY - direction * 14),
                                   control: CGPoint(x: stemX + 12, y: flagY - direction * 7))
                context.stroke(curve, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
        if let accidental = note.accidental {
            glyph(accidental.rawValue, x: x - 16, y: y, size: 19, in: context, color: color)
        }
        if note.dotted { dot(x + 13, y: pitch.isMultiple(of: 2) ? y - 6 : y, in: context, color: color) }
    }

    private func drawBeams(for group: Range<Int>, using beam: Beam, in context: GraphicsContext) {
        let notes = layout.fragments
        let first = group.lowerBound
        let last = group.upperBound - 1
        func drawSegment(from start: CGFloat, to end: CGFloat, level: Int) {
            var path = Path()
            path.move(to: beam.point(at: start, level: level))
            path.addLine(to: beam.point(at: end, level: level))
            context.stroke(path, with: .color(.primary), lineWidth: 4)
        }
        drawSegment(from: notes[first].x, to: notes[last].x, level: 0)
        for index in group {
            let note = notes[index]
            for level in 1..<note.value.flags {
                if index < last, notes[index + 1].value.flags > level {
                    drawSegment(from: note.x, to: notes[index + 1].x, level: level)
                } else if index == first || notes[index - 1].value.flags <= level {
                    let hook: CGFloat = index == last ? -12 : 12
                    drawSegment(from: note.x, to: note.x + hook, level: level)
                }
            }
        }
    }

    private func drawRest(_ note: ScoreLayout.Fragment, in context: GraphicsContext, color: Color) {
        let y = ScoreLayout.y(for: 4)
        if note.value == .whole || note.value == .half {
            let top = note.value == .whole ? ScoreLayout.y(for: 6) : y - 5
            context.fill(Path(CGRect(x: note.x - 7, y: top, width: 14, height: 5)), with: .color(color))
        } else if note.value == .quarter {
            var rest = Path()
            rest.move(to: CGPoint(x: note.x - 4, y: y - 17))
            rest.addLine(to: CGPoint(x: note.x + 4, y: y - 7))
            rest.addLine(to: CGPoint(x: note.x - 2, y: y - 1))
            rest.addLine(to: CGPoint(x: note.x + 5, y: y + 8))
            rest.addQuadCurve(to: CGPoint(x: note.x - 3, y: y + 14), control: CGPoint(x: note.x - 10, y: y + 6))
            rest.addQuadCurve(to: CGPoint(x: note.x + 1, y: y + 18), control: CGPoint(x: note.x - 3, y: y + 17))
            context.stroke(rest, with: .color(color), style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
        } else {
            let flags = note.value.flags
            let top = y - 6 - CGFloat(flags - 1) * 4
            let start = CGPoint(x: note.x + 7, y: top)
            let end = CGPoint(x: note.x + 1 - CGFloat(flags - 1) * 2, y: top + 16 + CGFloat(flags - 1) * 7)
            line(in: context, from: start, to: end, color: color)
            for flag in 0..<flags {
                let flagY = top + CGFloat(flag) * 7
                let flagX = note.x + 7 - CGFloat(flag) * 2.2
                let head = CGRect(x: flagX - 11, y: flagY - 3, width: 5, height: 5)
                context.fill(Path(ellipseIn: head), with: .color(color))
                var hook = Path()
                hook.move(to: CGPoint(x: head.midX, y: head.midY + 1))
                hook.addQuadCurve(to: CGPoint(x: flagX, y: flagY),
                                  control: CGPoint(x: flagX - 4, y: flagY + 5))
                context.stroke(hook, with: .color(color), lineWidth: 1.4)
            }
        }
        if note.dotted { dot(note.x + 14, y: y - 6, in: context, color: color) }
    }

    private func ledger(_ pitch: Int, _ x: CGFloat, in context: GraphicsContext, color: Color) {
        let y = ScoreLayout.y(for: pitch)
        line(in: context, from: CGPoint(x: x - 11, y: y), to: CGPoint(x: x + 11, y: y), color: color)
    }

    private func line(in context: GraphicsContext, from: CGPoint, to: CGPoint, color: Color = .primary) {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        context.stroke(path, with: .color(color), lineWidth: 1.2)
    }

    private func glyph(_ symbol: String, x: CGFloat, y: CGFloat, size: CGFloat, in context: GraphicsContext, color: Color) {
        context.draw(Text(symbol).font(.custom("Apple Symbols", size: size)).foregroundStyle(color),
                     at: CGPoint(x: x, y: y))
    }

    private func dot(_ x: CGFloat, y: CGFloat, in context: GraphicsContext, color: Color) {
        context.fill(Path(ellipseIn: CGRect(x: x - 1.7, y: y - 1.7, width: 3.4, height: 3.4)), with: .color(color))
    }
}
