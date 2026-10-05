import SwiftUI

struct BoardLayout {
    var size: CGSize
    var bottom: Side
    var padding: CGFloat { min(17, size.width * 0.048) }
    var unit: CGFloat { min((size.width - padding * 2) / 8, (size.height - padding * 2) / 9) }
    var origin: CGPoint { CGPoint(x: (size.width - unit * 8) / 2, y: (size.height - unit * 9) / 2) }
    func point(_ square: BoardSquare) -> CGPoint {
        CGPoint(x: origin.x + CGFloat(bottom == .red ? square.file : 8 - square.file) * unit,
                y: origin.y + CGFloat(bottom == .red ? 9 - square.rank : square.rank) * unit)
    }
    func square(_ point: CGPoint) -> BoardSquare? {
        let file = Int(((point.x - origin.x) / unit).rounded())
        let row = Int(((point.y - origin.y) / unit).rounded())
        guard (0...8).contains(file), (0...9).contains(row) else { return nil }
        return BoardSquare(file: bottom == .red ? file : 8 - file, rank: bottom == .red ? 9 - row : row)
    }
}

struct PieceFace: View {
    var piece: ChessPiece
    var diameter: CGFloat
    var selected = false
    var landing = false
    var light: Color?
    var checked = false
    var body: some View {
        let ink = piece.side == .red ? Palette.red : Palette.ink
        ZStack {
            Circle().fill(Color(hex: 0xB18A57)).offset(y: diameter * 0.045)
            Circle().fill(LinearGradient(colors: [Color(hex: 0xFFF5DB), Color(hex: 0xE9CEA2)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().strokeBorder(Color.white.opacity(0.6), lineWidth: diameter * 0.045)
            Circle().inset(by: diameter * 0.1).stroke(ink.opacity(0.6), lineWidth: max(0.8, diameter * 0.025))
            Text(piece.kind.glyph(piece.side)).font(.custom("STKaiti", size: diameter * 0.63))
                .fontWeight(.semibold).foregroundStyle(ink).offset(y: -diameter * 0.02)
            if selected || landing || checked {
                Circle().strokeBorder(checked ? Palette.red : selected ? Palette.teal : Palette.teal.opacity(0.6), lineWidth: 2.5)
                    .padding(-3)
            }
            if let light {
                Circle().fill(light).frame(width: diameter * 0.21, height: diameter * 0.21)
                    .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                    .offset(x: diameter * 0.35, y: -diameter * 0.35)
            }
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: Color(hex: 0x6B472B).opacity(0.2), radius: selected ? 4 : 1.5, x: 0, y: selected ? 4 : 2)
        .scaleEffect(selected ? 1.055 : 1)
    }
}

struct BoardView: View {
    var pieces: [ChessPiece]
    var bottom: Side = .red
    var selected: BoardSquare?
    var destinations: Set<BoardSquare> = []
    var lastMove: ChessMove?
    var recommendation: ChessMove?
    var captures: [SafeCapture] = []
    var checkedSide: Side?
    var interactive = true
    var onTap: (BoardSquare) -> Void = { _ in }
    var onDrag: (BoardSquare, BoardSquare) -> Void = { _, _ in }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draggingID: UUID?
    @State private var translation = CGSize.zero

    var body: some View {
        GeometryReader { geometry in
            let layout = BoardLayout(size: geometry.size, bottom: bottom)
            ZStack {
                RoundedRectangle(cornerRadius: min(15, layout.unit * 0.4))
                    .fill(LinearGradient(colors: [Color(hex: 0xF2DEBA), Palette.wood, Color(hex: 0xE7C799)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(RoundedRectangle(cornerRadius: min(15, layout.unit * 0.4)).strokeBorder(Color(hex: 0xC9A577).opacity(0.6), lineWidth: 1))
                Canvas { context, size in drawBoard(context: &context, layout: layout) }
                    .contentShape(Rectangle()).onTapGesture { point in
                        if interactive, let square = layout.square(point) { onTap(square) }
                    }
                if let lastMove {
                    Circle().fill(Palette.teal.opacity(0.35)).frame(width: layout.unit * 0.23, height: layout.unit * 0.23)
                        .position(layout.point(lastMove.from)).allowsHitTesting(false)
                    RoundedRectangle(cornerRadius: 6).stroke(Palette.teal.opacity(0.65), lineWidth: 1.5)
                        .frame(width: layout.unit * 0.88, height: layout.unit * 0.88)
                        .position(layout.point(lastMove.to)).allowsHitTesting(false)
                }
                ForEach(Array(destinations).sorted { $0.uci < $1.uci }) { square in
                    if !pieces.contains(where: { $0.square == square }) {
                        Circle().fill(Palette.teal.opacity(0.45)).frame(width: layout.unit * 0.2, height: layout.unit * 0.2)
                            .position(layout.point(square)).allowsHitTesting(false)
                    }
                }
                ForEach(pieces) { piece in
                    Button { onTap(piece.square) } label: {
                        PieceFace(piece: piece, diameter: layout.unit * 0.81,
                                  selected: selected == piece.square,
                                  landing: destinations.contains(piece.square), light: light(for: piece),
                                  checked: piece.kind == .king && piece.side == checkedSide)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(piece.side.title)\(piece.kind.glyph(piece.side))")
                    .position(layout.point(piece.square))
                    .offset(draggingID == piece.id ? translation : .zero)
                    .zIndex(draggingID == piece.id ? 3 : selected == piece.square ? 2 : 1)
                    .gesture(DragGesture(minimumDistance: 7, coordinateSpace: .named("chessboard"))
                        .onChanged { value in
                            guard interactive else { return }
                            draggingID = piece.id; translation = value.translation
                        }.onEnded { value in
                            draggingID = nil; translation = .zero
                            if interactive, let target = layout.square(value.location), target != piece.square {
                                onDrag(piece.square, target)
                            }
                        })
                    .allowsHitTesting(interactive)
                }
                if let recommendation {
                    Canvas { context, _ in drawArrow(context: &context, move: recommendation, layout: layout) }
                        .allowsHitTesting(false).zIndex(4)
                }
            }
            .coordinateSpace(name: "chessboard")
            .animation(reduceMotion || draggingID != nil ? nil : .spring(response: 0.26, dampingFraction: 0.86), value: pieces)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: selected)
        }
        .aspectRatio(0.9, contentMode: .fit)
    }
    private func light(for piece: ChessPiece) -> Color? {
        let matches = captures.filter { $0.move.to == piece.square }
        if piece.side == bottom {
            return matches.contains(where: { $0.side != bottom }) ? Palette.red : nil
        }
        return matches.contains(where: { $0.side == bottom && (selected == nil || $0.move.from == selected) }) ? Palette.green : nil
    }
    private func drawBoard(context: inout GraphicsContext, layout: BoardLayout) {
        var grain = Path()
        for index in 0..<70 {
            let y = CGFloat(index) * layout.size.height / 70
            grain.move(to: CGPoint(x: 8, y: y)); grain.addLine(to: CGPoint(x: layout.size.width - 8, y: y + 2))
        }
        context.stroke(grain, with: .color(Color.white.opacity(0.06)), lineWidth: 1)
        func line(_ from: BoardSquare, _ to: BoardSquare, path: inout Path) {
            path.move(to: layout.point(from)); path.addLine(to: layout.point(to))
        }
        var grid = Path()
        for rank in 0...9 { line(BoardSquare(file: 0, rank: rank), BoardSquare(file: 8, rank: rank), path: &grid) }
        for file in 0...8 {
            if file == 0 || file == 8 { line(BoardSquare(file: file, rank: 0), BoardSquare(file: file, rank: 9), path: &grid) }
            else {
                line(BoardSquare(file: file, rank: 0), BoardSquare(file: file, rank: 4), path: &grid)
                line(BoardSquare(file: file, rank: 5), BoardSquare(file: file, rank: 9), path: &grid)
            }
        }
        for rank in [0, 7] {
            line(BoardSquare(file: 3, rank: rank), BoardSquare(file: 5, rank: rank + 2), path: &grid)
            line(BoardSquare(file: 5, rank: rank), BoardSquare(file: 3, rank: rank + 2), path: &grid)
        }
        context.stroke(grid, with: .color(Palette.boardInk.opacity(0.75)), lineWidth: 0.8)
        let board = CGRect(x: layout.origin.x - 3, y: layout.origin.y - 3, width: layout.unit * 8 + 6, height: layout.unit * 9 + 6)
        context.stroke(Path(roundedRect: board, cornerRadius: 1), with: .color(Palette.boardInk.opacity(0.65)), lineWidth: 1.1)
        let left = bottom == .red ? "楚 河" : "汉 界"
        let right = bottom == .red ? "汉 界" : "楚 河"
        for (title, file) in [(left, 2.0), (right, 6.0)] {
            let point = CGPoint(x: layout.origin.x + file * layout.unit, y: layout.origin.y + 4.5 * layout.unit)
            context.draw(Text(title).font(.custom("STKaiti", size: layout.unit * 0.4)).foregroundStyle(Palette.boardInk.opacity(0.85)), at: point)
        }
        var marks = Path()
        for square in [BoardSquare(file: 1, rank: 2), BoardSquare(file: 7, rank: 2), BoardSquare(file: 1, rank: 7), BoardSquare(file: 7, rank: 7)]
            + [3, 6].flatMap({ rank in [0, 2, 4, 6, 8].map { BoardSquare(file: $0, rank: rank) } }) {
            let point = layout.point(square)
            for x in [-1.0, 1.0] where !(square.file == 0 && (bottom == .red ? x < 0 : x > 0)) && !(square.file == 8 && (bottom == .red ? x > 0 : x < 0)) {
                for y in [-1.0, 1.0] {
                    let gap = layout.unit * 0.065, length = layout.unit * 0.12
                    marks.move(to: CGPoint(x: point.x + x * (gap + length), y: point.y + y * gap))
                    marks.addLine(to: CGPoint(x: point.x + x * gap, y: point.y + y * gap))
                    marks.addLine(to: CGPoint(x: point.x + x * gap, y: point.y + y * (gap + length)))
                }
            }
        }
        context.stroke(marks, with: .color(Palette.boardInk.opacity(0.65)), lineWidth: 0.7)
    }
    private func drawArrow(context: inout GraphicsContext, move: ChessMove, layout: BoardLayout) {
        let from = layout.point(move.from), to = layout.point(move.to)
        let angle = atan2(to.y - from.y, to.x - from.x)
        let end = CGPoint(x: to.x - cos(angle) * layout.unit * 0.22, y: to.y - sin(angle) * layout.unit * 0.22)
        var shaft = Path(); shaft.move(to: from); shaft.addLine(to: end)
        context.stroke(shaft, with: .color(Palette.teal.opacity(0.82)), style: StrokeStyle(lineWidth: layout.unit * 0.085, lineCap: .round))
        var tip = Path(); tip.move(to: end)
        for offset in [-0.6, 0.6] {
            tip.addLine(to: CGPoint(x: end.x - cos(angle + offset) * layout.unit * 0.3,
                                   y: end.y - sin(angle + offset) * layout.unit * 0.3))
        }
        tip.closeSubpath(); context.fill(tip, with: .color(Palette.teal.opacity(0.9)))
    }
}
