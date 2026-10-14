import 'package:flutter/material.dart';

import '../data/notes_db.dart';
import '../logic/dates.dart';
import '../logic/settings.dart';
import 'day_screen.dart';
import 'export_screen.dart';
import 'widgets.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  // Page _base is the current month; pages to the left and right are older and newer months.
  static const _base = 1200;
  final _pages = PageController(initialPage: _base);
  final _thisMonth = DateTime(DateTime.now().year, DateTime.now().month);
  int _page = _base;

  // yyyymm -> (day key -> note count), loaded per month only when that month is shown.
  final _counts = <int, Map<int, int>>{};
  int _generation = 0;

  bool _selecting = false;
  final _selected = <int>{};

  @override
  void initState() {
    super.initState();
    NotesDb.revision.addListener(_invalidate);
  }

  @override
  void dispose() {
    NotesDb.revision.removeListener(_invalidate);
    _pages.dispose();
    super.dispose();
  }

  void _invalidate() => setState(() {
    _counts.clear();
    _generation++;
  });

  DateTime _monthAt(int page) => DateTime(_thisMonth.year, _thisMonth.month + page - _base);

  Map<int, int> _countsFor(DateTime month) {
    final key = month.year * 100 + month.month;
    final cached = _counts[key];
    if (cached != null) return cached;
    _counts[key] = const {}; // marks it as loading
    final generation = _generation;
    NotesDb.countsBetween(dayKey(month), dayKey(DateTime(month.year, month.month + 1, 0))).then((counts) {
      if (mounted && generation == _generation) setState(() => _counts[key] = counts);
    });
    return const {};
  }

  void _goToMonth(int page) =>
      _pages.animateToPage(page, duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic);

  void _tapDay(int key) {
    if (_selecting) {
      setState(() => _selected.contains(key) ? _selected.remove(key) : _selected.add(key));
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (_) => DayScreen(day: key)));
    }
  }

  void _selectRange(DateTime first, int days) {
    setState(
      () => _selected.addAll([for (var i = 0; i < days; i++) dayKey(DateTime(first.year, first.month, first.day + i))]),
    );
    _goToMonth(_base);
  }

  void _stopSelecting() => setState(() {
    _selecting = false;
    _selected.clear();
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final weekStart = Settings.current.value.weekStart;
    final month = _monthAt(_page);
    final now = DateTime.now();
    return PopScope(
      canPop: !_selecting, // Back leaves selection mode first
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _stopSelecting();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: _selecting
              ? IconButton(icon: const Icon(Icons.close), tooltip: 'Cancel selection', onPressed: _stopSelecting)
              : null,
          title: Text(_selecting ? 'Select days to export' : 'Calendar'),
          actions: [
            if (!_selecting)
              TextButton.icon(
                onPressed: () => setState(() => _selecting = true),
                icon: const Icon(Icons.ios_share, size: 18),
                label: const Text('Export'),
              ),
            const SizedBox(width: 8),
          ],
        ),
        body: readable(
          ListView(
            // Runs under the navigation bar, padded so the content ends above it.
            padding: EdgeInsets.fromLTRB(20, 8, 20, 16 + MediaQuery.viewPaddingOf(context).bottom),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        text: '${monthLong[month.month - 1]} ',
                        children: [
                          TextSpan(
                            text: '${month.year}',
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                      style: tt.titleLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_page != _base) TextButton(onPressed: () => _goToMonth(_base), child: const Text('Today')),
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    tooltip: 'Previous month',
                    onPressed: () => _goToMonth(_page - 1),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    tooltip: 'Next month',
                    onPressed: () => _goToMonth(_page + 1),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  for (final d in weekdaysFrom(weekStart))
                    Expanded(
                      child: Text(
                        d.substring(0, 1),
                        semanticsLabel: weekdayLong[weekdayShort.indexOf(d)],
                        textAlign: TextAlign.center,
                        style: tt.labelSmall!.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 6 * 50,
                child: PageView.builder(
                  controller: _pages,
                  onPageChanged: (p) => setState(() => _page = p),
                  itemBuilder: (context, page) => _MonthGrid(
                    month: _monthAt(page),
                    weekStart: weekStart,
                    counts: _countsFor(_monthAt(page)),
                    selected: _selected,
                    onTap: _tapDay,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (_selecting)
                Wrap(
                  spacing: 8,
                  children: [
                    ActionChip(
                      label: const Text('This week'),
                      onPressed: () => _selectRange(startOfWeek(now, weekStart), 7),
                    ),
                    ActionChip(
                      label: const Text('This month'),
                      onPressed: () =>
                          _selectRange(DateTime(now.year, now.month), DateTime(now.year, now.month + 1, 0).day),
                    ),
                    if (_selected.isNotEmpty)
                      ActionChip(label: const Text('Clear'), onPressed: () => setState(_selected.clear)),
                  ],
                )
              else
                Text(
                  'Tap a day to see or add its notes.',
                  textAlign: TextAlign.center,
                  style: tt.bodySmall!.copyWith(color: cs.onSurfaceVariant),
                ),
            ],
          ),
        ),
        bottomNavigationBar: _selecting
            ? SafeArea(
                child: readable(
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 16, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${_selected.length} ${_selected.length == 1 ? 'day' : 'days'} selected',
                            style: tt.titleSmall,
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: _selected.isEmpty
                              ? null
                              : () => Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => ExportScreen(days: Set.of(_selected))),
                                ),
                          icon: const Icon(Icons.description_outlined, size: 18),
                          label: const Text('Export'),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            : null,
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.weekStart,
    required this.counts,
    required this.selected,
    required this.onTap,
  });

  final DateTime month;
  final int weekStart;
  final Map<int, int> counts;
  final Set<int> selected;
  final void Function(int dayKey) onTap;

  @override
  Widget build(BuildContext context) {
    final lead = (month.weekday - weekStart) % 7;
    final days = DateTime(month.year, month.month + 1, 0).day;
    final today = todayKey();
    return Column(
      children: [
        for (var row = 0; row < 6; row++)
          Expanded(
            child: Row(
              children: [
                for (var col = 0; col < 7; col++)
                  Expanded(child: _cell(context, row * 7 + col - lead + 1, col, days, today)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _cell(BuildContext context, int d, int col, int days, int today) {
    if (d < 1 || d > days) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final key = month.year * 10000 + month.month * 100 + d;
    final isToday = key == today;
    final picked = selected.contains(key);
    final hasNotes = (counts[key] ?? 0) > 0;
    // Selected neighbours in the same week row join into one calm band, as Material's range picker draws it;
    // only the ends of a run get a filled disc.
    final joinLeft = picked && col > 0 && d > 1 && selected.contains(key - 1);
    final joinRight = picked && col < 6 && d < days && selected.contains(key + 1);
    final end = picked && !(joinLeft && joinRight);
    final band = cs.primaryContainer;
    final fg = end ? cs.onPrimary : (picked || isToday ? cs.primary : cs.onSurface);
    return Semantics(
      button: true,
      selected: picked,
      label:
          '${longDay(DateTime(month.year, month.month, d))}${isToday ? ', today' : ''}${hasNotes ? ', has notes' : ''}',
      excludeSemantics: true,
      child: InkResponse(
        onTap: () => onTap(key),
        radius: 24,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (picked)
              Row(
                children: [
                  Expanded(child: Container(height: 42, color: joinLeft ? band : null)),
                  Expanded(child: Container(height: 42, color: joinRight ? band : null)),
                ],
              ),
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: end ? cs.primary : (picked ? band : null),
                border: isToday && !end ? Border.all(color: cs.primary, width: 1.5) : null,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Text(
                    '$d',
                    style: Theme.of(context).textTheme.bodyMedium!
                        .copyWith(color: fg, fontWeight: isToday || picked ? FontWeight.w700 : null),
                  ),
                  if (hasNotes)
                    Positioned(
                      bottom: 6,
                      child: Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: end ? cs.onPrimary : cs.primary),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
