import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models.dart';

/// Geometry of the board for a given space (DESIGN_MANIFEST «Board»): one row
/// per category, a fixed name column, value cells left → right. Pure, so it is
/// unit-testable.
class BoardLayout {
  const BoardLayout({
    required this.nameWidth,
    required this.cellWidth,
    required this.rowHeight,
    required this.scrollX,
    required this.scrollY,
  });

  static const gap = 6.0;
  static const padding = 12.0;

  /// Below this a 4-digit value stops being legible on a phone.
  static const minCellWidthPhone = 72.0;
  static const minCellWidth = 56.0;
  static const minRowHeight = 44.0;
  static const maxRowHeight = 120.0;

  final double nameWidth;
  final double cellWidth;
  final double rowHeight;

  /// Value cells scroll horizontally (the name column stays fixed).
  final bool scrollX;

  /// Rows do not fit the height even at [minRowHeight].
  final bool scrollY;

  factory BoardLayout.of(Size space, {required int rows, required int cells}) {
    final w = space.width - 2 * padding;
    final phone = space.width < 600;
    final nameWidth = phone ? 104.0 : (w * 0.2).clamp(120.0, 240.0);
    final c = math.max(1, cells);
    final r = math.max(1, rows);
    final cellsArea = w - nameWidth - gap;
    var cellWidth = (cellsArea - gap * (c - 1)) / c;
    final minW = phone ? minCellWidthPhone : minCellWidth;
    final scrollX = cellWidth < minW;
    if (scrollX) cellWidth = minW;
    double rowHeight;
    var scrollY = false;
    if (space.height.isFinite) {
      final h = space.height - 2 * padding;
      rowHeight = (h - gap * (r - 1)) / r;
      if (rowHeight < minRowHeight) {
        rowHeight = minRowHeight;
        scrollY = true;
      }
      rowHeight = math.min(rowHeight, maxRowHeight);
    } else {
      rowHeight = 64;
      scrollY = true;
    }
    return BoardLayout(
      nameWidth: nameWidth,
      cellWidth: cellWidth,
      rowHeight: rowHeight,
      scrollX: scrollX,
      scrollY: scrollY,
    );
  }
}

/// The game board, rotated: one row per category (name on the left), value
/// cells ascending to the right. Rows share the height; values shrink to fit
/// their cell instead of overflowing.
class GameBoard extends StatelessWidget {
  const GameBoard({super.key, required this.board, this.onSelect});

  final List<BoardCategory> board;

  /// Null = read-only board.
  final void Function(BoardQuestion q)? onSelect;

  int get _maxCells => board.fold(0, (m, cat) => math.max(m, cat.questions.length));

  @override
  Widget build(BuildContext context) {
    if (board.isEmpty) {
      return Center(child: Text('В раунде нет вопросов', style: AppText.muted(14)));
    }
    return LayoutBuilder(builder: (context, c) {
      final cells = _maxCells;
      final l = BoardLayout.of(Size(c.maxWidth, c.maxHeight), rows: board.length, cells: cells);
      const gap = BoardLayout.gap;
      final names = Column(children: [
        for (final (i, cat) in board.indexed)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : gap),
            child: SizedBox(
              width: l.nameWidth,
              height: l.rowHeight,
              child: _Header(name: cat.name, wide: c.maxWidth >= 600),
            ),
          ),
      ]);
      final values = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final (i, cat) in board.indexed)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : gap),
            child: Row(children: [
              for (var j = 0; j < cells; j++)
                Padding(
                  padding: EdgeInsets.only(left: j == 0 ? 0 : gap),
                  child: SizedBox(
                    width: l.cellWidth,
                    height: l.rowHeight,
                    child: j < cat.questions.length
                        ? _Cell(q: cat.questions[j], onSelect: onSelect)
                        : const SizedBox.shrink(),
                  ),
                ),
            ]),
          ),
      ]);
      final grid = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        names,
        const SizedBox(width: gap),
        Expanded(
          child: l.scrollX ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: values) : values,
        ),
      ]);
      return Padding(
        padding: const EdgeInsets.all(BoardLayout.padding),
        child: l.scrollY ? SingleChildScrollView(child: grid) : grid,
      );
    });
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.name, required this.wide});

  final String name;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        name.toUpperCase(),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: AppText.body(wide ? 14 : 12, weight: FontWeight.w600),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.q, required this.onSelect});

  final BoardQuestion q;
  final void Function(BoardQuestion q)? onSelect;

  @override
  Widget build(BuildContext context) {
    if (q.played) {
      return Container(decoration: BoxDecoration(color: AppColors.cellPlayed, borderRadius: BorderRadius.circular(12)));
    }
    final enabled = onSelect != null;
    return Material(
      type: MaterialType.transparency,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.cellTop, AppColors.cellBottom],
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          hoverColor: AppColors.cellHover,
          focusColor: AppColors.cellHover,
          splashColor: AppColors.cellHover,
          onTap: enabled ? () => onSelect!(q) : null,
          child: LayoutBuilder(builder: (context, c) {
            // ≤ 45 % of the cell height, never wider than the cell minus padding.
            final h = c.maxHeight * 0.45;
            return Center(
              child: SizedBox(
                width: math.max(0, c.maxWidth - 12),
                height: h,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '${q.value}',
                    maxLines: 1,
                    style: AppText.display(math.min(h, 48), color: AppColors.gold).copyWith(height: 1),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
