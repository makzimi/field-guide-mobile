import 'dart:async';

import 'package:catalog_api/catalog_api.dart';
import 'package:flutter/material.dart';

typedef CancelExpiry = void Function();

abstract interface class ExpiryScheduler {
  CancelExpiry schedule(int delayMs, void Function() callback);
}

sealed class CatalogAction {
  const CatalogAction();
}

final class OpenList extends CatalogAction {
  const OpenList();
}

final class RefreshCatalog extends CatalogAction {
  const RefreshCatalog();
}

final class SetQuery extends CatalogAction {
  const SetQuery(this.text);
  final String text;
}

final class SetBudget extends CatalogAction {
  const SetBudget(this.minutes);
  final int minutes;
}

final class ClearFilters extends CatalogAction {
  const ClearFilters();
}

final class OpenDetail extends CatalogAction {
  const OpenDetail(this.id);
  final String id;
}

final class BackToList extends CatalogAction {
  const BackToList();
}

final class ToggleBookmark extends CatalogAction {
  const ToggleBookmark();
}

final class RetryBookmark extends CatalogAction {
  const RetryBookmark();
}

final class RetrySavedWalks extends CatalogAction {
  const RetrySavedWalks();
}

final class Foreground extends CatalogAction {
  const Foreground();
}

final class WalkPresentation {
  const WalkPresentation({
    required this.walk,
    required this.distance,
    required this.duration,
    required this.saved,
  });
  final Walk walk;
  final String distance, duration;
  final bool saved;
}

final class FeatureState {
  FeatureState({
    required this.catalog,
    this.query = '',
    this.budgetMinutes = 60,
    this.selectedId,
    List<WalkPresentation> walks = const [],
    this.detail,
    this.fresh = false,
    this.stale = false,
    this.savedCount,
    this.addEnabled = false,
    this.removeEnabled = false,
    this.disabledReason,
    this.catalogStatus = 'loading',
  }) : walks = List.unmodifiable(walks);
  final CatalogState catalog;
  final String query, catalogStatus;
  final int budgetMinutes;
  final String? selectedId, disabledReason;
  final List<WalkPresentation> walks;
  final WalkPresentation? detail;
  final bool fresh, stale, addEnabled, removeEnabled;
  final int? savedCount;
}

final class CatalogPresentationMapper {
  FeatureState map(
    CatalogState catalog,
    QueryWalks queryWalks,
    int nowMs, {
    String query = '',
    int budgetMinutes = 60,
    String? selectedId,
  }) {
    final snapshot = catalog.snapshot;
    final fresh = snapshot?.isFresh(nowMs) ?? false;
    final stale = snapshot != null && !fresh;
    final ready = catalog.storageStatus == StorageStatus.loaded;
    WalkPresentation present(Walk walk) => WalkPresentation(
      walk: walk,
      distance: '${(walk.distanceMetres / 1000).toStringAsFixed(1)} km',
      duration:
          '${walk.durationMinutes} ${walk.durationMinutes == 1 ? 'minute' : 'minutes'}',
      saved: ready && catalog.savedIds.contains(walk.id),
    );
    final walks = queryWalks(
      snapshot?.walks ?? const [],
      query: query,
      budgetMinutes: budgetMinutes,
    ).map(present).toList();
    final selected = selectedId == null ? null : snapshot?.find(selectedId);
    final detail = selected == null ? null : present(selected);
    String? reason;
    if (detail != null) {
      if (!ready) {
        reason = 'storage-unavailable';
      } else if (catalog.pendingId != null) {
        reason = 'saving';
      } else if (!detail.saved) {
        if (selected!.availability == Availability.closed) {
          reason = 'closed';
        } else if (!fresh) {
          reason = 'stale';
        }
      }
    }
    final status = snapshot == null
        ? (catalog.catalogError != null && !catalog.refreshing
              ? 'full-error'
              : 'loading')
        : catalog.refreshing
        ? (stale ? 'refreshing-stale' : 'refreshing-fresh')
        : catalog.catalogError != null
        ? (stale ? 'stale-error' : 'content-error')
        : walks.isEmpty
        ? 'empty'
        : 'content';
    return FeatureState(
      catalog: catalog,
      query: query,
      budgetMinutes: budgetMinutes,
      selectedId: selectedId,
      walks: walks,
      detail: detail,
      fresh: fresh,
      stale: stale,
      savedCount: ready
          ? snapshot?.walks
                    .where((w) => catalog.savedIds.contains(w.id))
                    .length ??
                0
          : null,
      addEnabled: detail != null && !detail.saved && reason == null,
      removeEnabled: detail != null && detail.saved && reason == null,
      disabledReason: reason,
      catalogStatus: status,
    );
  }
}

final class TimerExpiryScheduler implements ExpiryScheduler {
  @override
  CancelExpiry schedule(int delayMs, void Function() callback) {
    final timer = Timer(Duration(milliseconds: delayMs), callback);
    return timer.cancel;
  }
}

/// Immutable published state plus a disposal-safe SDK notification adapter.
final class CatalogController extends ChangeNotifier {
  CatalogController({
    required this.repository,
    required this.queryWalks,
    required this.bookmarks,
    required this.clock,
    ExpiryScheduler? scheduler,
  }) : scheduler = scheduler ?? TimerExpiryScheduler() {
    _rebuild(notify: false);
    _subscription = repository.changes.listen((_) => _rebuild());
  }
  final CatalogRepository repository;
  final QueryWalks queryWalks;
  final ChangeBookmark bookmarks;
  final MonotonicClock clock;
  final ExpiryScheduler scheduler;
  final _mapper = CatalogPresentationMapper();
  late FeatureState _state;
  late final StreamSubscription<CatalogState> _subscription;
  bool _disposed = false, _started = false;
  String _query = '';
  int _budget = 60;
  String? _selectedId;
  ({String id, bool save})? _failedIntent;
  CancelExpiry? _cancelExpiry;
  FeatureState get state => _state;
  void _rebuild({bool notify = true}) {
    if (_disposed) return;
    _state = _mapper.map(
      repository.state,
      queryWalks,
      clock.nowMs,
      query: _query,
      budgetMinutes: _budget,
      selectedId: _selectedId,
    );
    _cancelExpiry?.call();
    _cancelExpiry = null;
    final snapshot = repository.state.snapshot;
    if (snapshot != null && _state.fresh) {
      _cancelExpiry = scheduler.schedule(
        snapshot.fetchedAtMs + CatalogSnapshot.ttlMs - clock.nowMs,
        _rebuild,
      );
    }
    if (notify) notifyListeners();
  }

  Future<void> start() async {
    if (_disposed || _started) return;
    _started = true;
    await Future.wait([repository.open(), repository.loadBookmarks()]);
  }

  Future<void> _bookmark(String id, bool save) async {
    if (repository.state.pendingId != null) return;
    final result = await bookmarks(id, save: save);
    if (_disposed) return;
    if (result == BookmarkResult.failed) {
      _failedIntent = (id: id, save: save);
    } else if (result == BookmarkResult.saved ||
        result == BookmarkResult.removed) {
      _failedIntent = null;
    }
    // Policy rejection preserves the existing retry intent and inline error.
    _rebuild();
  }

  Future<void> dispatch(CatalogAction action) async {
    if (_disposed) return;
    switch (action) {
      case OpenList():
        _selectedId = null;
        _rebuild();
        await repository.open();
      case RefreshCatalog():
        await repository.refresh();
      case SetQuery(:final text):
        _query = text;
        _rebuild();
      case SetBudget(:final minutes):
        if (![15, 30, 60, 90].contains(minutes)) {
          throw ArgumentError.value(minutes, 'minutes');
        }
        _budget = minutes;
        _rebuild();
      case ClearFilters():
        _query = '';
        _budget = 60;
        _rebuild();
      case OpenDetail(:final id):
        _selectedId = id;
        _rebuild();
      case BackToList():
        _selectedId = null;
        _rebuild();
        await repository.open();
      case ToggleBookmark():
        final detail = _state.detail;
        if (detail != null) await _bookmark(detail.walk.id, !detail.saved);
      case RetryBookmark():
        final intent = _failedIntent;
        if (intent != null) await _bookmark(intent.id, intent.save);
      case RetrySavedWalks():
        await repository.loadBookmarks();
      case Foreground():
        _rebuild();
        await repository.open();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cancelExpiry?.call();
    unawaited(_subscription.cancel());
    super.dispose();
  }
}

class CatalogFeature extends StatefulWidget {
  const CatalogFeature({required this.controller, super.key});
  final CatalogController controller;
  @override
  State<CatalogFeature> createState() => _CatalogFeatureState();
}

class _CatalogFeatureState extends State<CatalogFeature>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.controller.dispatch(const Foreground()));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final state = widget.controller.state;
      return PopScope(
        canPop: state.selectedId == null,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && state.selectedId != null) {
            unawaited(widget.controller.dispatch(const BackToList()));
          }
        },
        child: state.selectedId == null
            ? WalkListScreen(state: state, dispatch: widget.controller.dispatch)
            : WalkDetailScreen(
                state: state,
                dispatch: widget.controller.dispatch,
              ),
      );
    },
  );
}

typedef DispatchCatalog = Future<void> Function(CatalogAction);

class _StatusMessages extends StatelessWidget {
  const _StatusMessages({required this.state, required this.dispatch});
  final FeatureState state;
  final DispatchCatalog dispatch;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (state.catalog.refreshing && state.catalog.snapshot != null)
        const LinearProgressIndicator(semanticsLabel: 'Refreshing walks'),
      if (state.stale)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('These walks need a refresh before saving.'),
        ),
      if (state.catalog.catalogError != null)
        _InlineRetry(
          message: state.catalog.catalogError!,
          label: 'Retry walks',
          onPressed: () => dispatch(const RefreshCatalog()),
        ),
      if (state.catalog.storageStatus == StorageStatus.loading)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('Loading saved walks…'),
        ),
      if (state.catalog.storageError != null)
        _InlineRetry(
          message: state.catalog.storageError!,
          label: 'Retry saved walks',
          onPressed: () => dispatch(const RetrySavedWalks()),
        ),
    ],
  );
}

class _InlineRetry extends StatelessWidget {
  const _InlineRetry({
    required this.message,
    required this.label,
    required this.onPressed,
  });
  final String message, label;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message),
        TextButton(onPressed: onPressed, child: Text(label)),
      ],
    ),
  );
}

class WalkListScreen extends StatefulWidget {
  const WalkListScreen({
    required this.state,
    required this.dispatch,
    super.key,
  });
  final FeatureState state;
  final DispatchCatalog dispatch;
  @override
  State<WalkListScreen> createState() => _WalkListScreenState();
}

class _WalkListScreenState extends State<WalkListScreen> {
  late final TextEditingController _search;
  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: widget.state.query);
  }

  @override
  void didUpdateWidget(WalkListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_search.text != widget.state.query) {
      _search.value = TextEditingValue(
        text: widget.state.query,
        selection: TextSelection.collapsed(offset: widget.state.query.length),
      );
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Field Guide'),
        actions: [
          IconButton(
            tooltip: 'Refresh walks',
            onPressed: () => widget.dispatch(const RefreshCatalog()),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Walks worth finding',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              state.savedCount == null
                  ? 'Saved walks unavailable'
                  : '${state.savedCount} saved ${state.savedCount == 1 ? 'walk' : 'walks'}',
            ),
            const SizedBox(height: 20),
            TextField(
              key: const ValueKey('walk-search'),
              controller: _search,
              onChanged: (text) => widget.dispatch(SetQuery(text)),
              decoration: const InputDecoration(
                labelText: 'Search walks',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final minutes in [15, 30, 60, 90])
                  ChoiceChip(
                    key: ValueKey('budget-$minutes'),
                    label: Text('$minutes min'),
                    selected: state.budgetMinutes == minutes,
                    onSelected: (_) => widget.dispatch(SetBudget(minutes)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _StatusMessages(state: state, dispatch: widget.dispatch),
            if (state.catalog.snapshot == null && state.catalog.refreshing)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(
                  child: CircularProgressIndicator(
                    semanticsLabel: 'Loading walks',
                  ),
                ),
              ),
            if (state.catalogStatus == 'full-error')
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('Walks are unavailable right now.'),
              ),
            if (state.catalog.snapshot != null && state.walks.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    const Text('No walks match your filters.'),
                    TextButton(
                      onPressed: () => widget.dispatch(const ClearFilters()),
                      child: const Text('Clear filters'),
                    ),
                  ],
                ),
              ),
            for (final route in state.walks)
              Card(
                clipBehavior: Clip.antiAlias,
                margin: const EdgeInsets.only(top: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                child: InkWell(
                  key: ValueKey('route-${route.walk.id}'),
                  onTap: () => widget.dispatch(OpenDetail(route.walk.id)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 64,
                          height: 72,
                          child: LandscapeArt(artKey: route.walk.artKey),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                route.walk.title,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 6),
                              Text('${route.duration} · ${route.distance}'),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 12,
                                children: [
                                  Text(
                                    route.walk.availability ==
                                            Availability.closed
                                        ? 'Closed'
                                        : 'Open',
                                  ),
                                  if (route.saved) const Text('Saved'),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class WalkDetailScreen extends StatelessWidget {
  const WalkDetailScreen({
    required this.state,
    required this.dispatch,
    super.key,
  });
  final FeatureState state;
  final DispatchCatalog dispatch;
  @override
  Widget build(BuildContext context) {
    final detail = state.detail;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back to walks',
          onPressed: () => dispatch(const BackToList()),
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('Walk details'),
        actions: [
          IconButton(
            tooltip: 'Refresh walks',
            onPressed: () => dispatch(const RefreshCatalog()),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: detail == null
            ? ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  const Text('This walk is unavailable.'),
                  TextButton(
                    onPressed: () => dispatch(const BackToList()),
                    child: const Text('Back to walks'),
                  ),
                ],
              )
            : ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  SizedBox(
                    height: 200,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: LandscapeArt(artKey: detail.walk.artKey),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    detail.walk.title,
                    key: const ValueKey('detail-title'),
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 24,
                    runSpacing: 8,
                    children: [
                      Text(detail.duration),
                      Text(detail.distance),
                      Text(
                        '${detail.walk.terrain.name[0].toUpperCase()}${detail.walk.terrain.name.substring(1)}',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    detail.walk.availability == Availability.closed
                        ? 'Closed'
                        : 'Open',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  Text(detail.walk.description),
                  const SizedBox(height: 20),
                  _StatusMessages(state: state, dispatch: dispatch),
                  if (state.disabledReason == 'closed')
                    const Text(
                      'This walk is closed. You can save it when it reopens.',
                    ),
                  if (state.disabledReason == 'stale')
                    const Text('Refresh walks before saving.'),
                  if (state.disabledReason == 'storage-unavailable')
                    const Text(
                      'Saved walks must load before you can make changes.',
                    ),
                  const SizedBox(height: 16),
                  FilledButton(
                    key: const ValueKey('bookmark-action'),
                    onPressed: state.addEnabled || state.removeEnabled
                        ? () => dispatch(const ToggleBookmark())
                        : null,
                    child: Text(
                      state.catalog.pendingId == detail.walk.id
                          ? 'Saving…'
                          : detail.saved
                          ? 'Remove saved walk'
                          : 'Save walk',
                    ),
                  ),
                  if (state.catalog.bookmarkError != null &&
                      state.catalog.bookmarkErrorId == detail.walk.id)
                    _InlineRetry(
                      message: state.catalog.bookmarkError!,
                      label: 'Retry save',
                      onPressed: state.addEnabled || state.removeEnabled
                          ? () => dispatch(const RetryBookmark())
                          : null,
                    ),
                ],
              ),
      ),
    );
  }
}

/// Original vector landscape, rendered locally without network assets.
class LandscapeArt extends StatelessWidget {
  const LandscapeArt({required this.artKey, super.key});
  final ArtKey artKey;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      painter: _LandscapePainter(artKey, Theme.of(context).colorScheme),
      child: const SizedBox.expand(),
    ),
  );
}

class _LandscapePainter extends CustomPainter {
  _LandscapePainter(this.artKey, this.colors);
  final ArtKey artKey;
  final ColorScheme colors;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = colors.primaryContainer;
    canvas.drawRect(Offset.zero & size, paint);
    paint.color = colors.tertiaryContainer;
    canvas.drawCircle(
      Offset(size.width * .76, size.height * .25),
      size.shortestSide * .13,
      paint,
    );
    paint.color = colors.secondary;
    final hills = Path()
      ..moveTo(0, size.height * .65)
      ..quadraticBezierTo(
        size.width * .3,
        size.height * .2,
        size.width * .6,
        size.height * .6,
      )
      ..quadraticBezierTo(
        size.width * .85,
        size.height * .4,
        size.width,
        size.height * .5,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(hills, paint);
    paint.color = colors.primary;
    final foreground = Path()
      ..moveTo(0, size.height * .85)
      ..quadraticBezierTo(
        size.width * .5,
        size.height * .55,
        size.width,
        size.height * .85,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(foreground, paint);
    if (artKey == ArtKey.canal) {
      paint.color = colors.surface;
      final water = Path()
        ..moveTo(size.width * .6, size.height * .58)
        ..lineTo(size.width * .72, size.height * .58)
        ..lineTo(size.width * .45, size.height)
        ..lineTo(size.width * .15, size.height)
        ..close();
      canvas.drawPath(water, paint);
    } else if (artKey == ArtKey.pine) {
      paint.color = colors.onPrimaryContainer;
      for (final x in [.2, .4, .6]) {
        final tree = Path()
          ..moveTo(size.width * x, size.height * .3)
          ..lineTo(size.width * (x + .12), size.height * .72)
          ..lineTo(size.width * (x - .12), size.height * .72)
          ..close();
        canvas.drawPath(tree, paint);
      }
    } else if (artKey == ArtKey.glasshouse) {
      paint.color = colors.surface;
      final house = Path()
        ..moveTo(size.width * .2, size.height * .7)
        ..lineTo(size.width * .2, size.height * .48)
        ..lineTo(size.width * .45, size.height * .3)
        ..lineTo(size.width * .7, size.height * .48)
        ..lineTo(size.width * .7, size.height * .7)
        ..close();
      canvas.drawPath(house, paint);
    }
  }

  @override
  bool shouldRepaint(_LandscapePainter oldDelegate) =>
      oldDelegate.artKey != artKey || oldDelegate.colors != colors;
}
