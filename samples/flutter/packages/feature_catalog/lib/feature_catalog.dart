import 'dart:async';

import 'package:catalog_api/catalog_api.dart';
import 'package:flutter/material.dart';

import 'src/components.dart';
import 'src/field_guide_theme.dart';
import 'src/landscape_art.dart';

export 'src/components.dart'
    show
        StatusPill,
        SavedMark,
        NoticePanel,
        ErrorPanel,
        QuietMessage,
        FactsRow,
        PlaceholderCard,
        HeroIconButton;
export 'src/field_guide_theme.dart'
    show
        fieldGuideColors,
        fieldGuideTheme,
        contrastRatio,
        FieldGuideType,
        fieldGuideSerifFamily,
        fieldGuideSerifPackage;
export 'src/landscape_art.dart'
    show LandscapeArt, ArtPalette, ArtTransform, artFit, paintScene;

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
  Widget build(BuildContext context) => Theme(
    data: fieldGuideTheme(Theme.of(context).brightness),
    child: ListenableBuilder(
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
              ? WalkListScreen(
                  state: state,
                  dispatch: widget.controller.dispatch,
                )
              : WalkDetailScreen(
                  state: state,
                  dispatch: widget.controller.dispatch,
                ),
        );
      },
    ),
  );
}

typedef DispatchCatalog = Future<void> Function(CatalogAction);

class _StatusMessages extends StatelessWidget {
  const _StatusMessages({required this.state, required this.dispatch});
  final FeatureState state;
  final DispatchCatalog dispatch;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (state.catalog.refreshing && state.catalog.snapshot != null)
        const LinearProgressIndicator(semanticsLabel: 'Refreshing walks'),
      if (state.stale)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: NoticePanel(
            message: 'These walks need a refresh before saving.',
          ),
        ),
      if (state.catalog.catalogError != null)
        _InlineRetry(
          message: state.catalog.catalogError!,
          headline: state.catalogStatus == 'full-error'
              ? 'Walks are unavailable right now.'
              : null,
          error: state.catalog.snapshot == null,
          label: 'Retry walks',
          onPressed: () => dispatch(const RefreshCatalog()),
        ),
      if (state.catalog.storageStatus == StorageStatus.loading)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Loading saved walks…',
            style: FieldGuideType.facts.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      if (state.catalog.storageError != null)
        _InlineRetry(
          message: state.catalog.storageError!,
          error: false,
          label: 'Retry saved walks',
          onPressed: () => dispatch(const RetrySavedWalks()),
        ),
    ],
  );
}

/// A message panel with its retry text button directly beneath it.
class _InlineRetry extends StatelessWidget {
  const _InlineRetry({
    required this.message,
    required this.error,
    required this.label,
    required this.onPressed,
    this.headline,
  });
  final String message, label;
  final String? headline;
  final bool error;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: error
              ? ErrorPanel(message: message, headline: headline)
              : NoticePanel(message: message),
        ),
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
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        // A plain scroll view builds every card, so each stays findable and
        // reachable with ensureVisible however tall the cards are.
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'FIELD GUIDE',
                      style: FieldGuideType.eyebrow.copyWith(
                        color: scheme.secondary,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh walks',
                    onPressed: () => widget.dispatch(const RefreshCatalog()),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              Text(
                'Walks worth finding',
                style: FieldGuideType.pageTitle.copyWith(
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('walk-search'),
                controller: _search,
                onChanged: (text) => widget.dispatch(SetQuery(text)),
                decoration: InputDecoration(
                  labelText: 'Search walks',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: scheme.surfaceContainerHighest,
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(28)),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: const BorderRadius.all(Radius.circular(28)),
                    borderSide: BorderSide(color: scheme.primary, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final minutes in [15, 30, 60, 90])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          key: ValueKey('budget-$minutes'),
                          label: Text('$minutes min'),
                          selected: state.budgetMinutes == minutes,
                          showCheckmark: false,
                          backgroundColor: Colors.transparent,
                          selectedColor: scheme.primary,
                          shape: const StadiumBorder(),
                          side: BorderSide(
                            color: state.budgetMinutes == minutes
                                ? scheme.primary
                                : scheme.outlineVariant,
                          ),
                          labelStyle: FieldGuideType.button.copyWith(
                            color: state.budgetMinutes == minutes
                                ? scheme.onPrimary
                                : scheme.onSurface,
                          ),
                          onSelected: (_) =>
                              widget.dispatch(SetBudget(minutes)),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  ExcludeSemantics(
                    child: Icon(
                      Icons.bookmark,
                      size: 16,
                      color: scheme.secondary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      state.savedCount == null
                          ? 'Saved walks unavailable'
                          : '${state.savedCount} saved ${state.savedCount == 1 ? 'walk' : 'walks'}',
                      style: FieldGuideType.facts.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _StatusMessages(state: state, dispatch: widget.dispatch),
              if (state.catalog.snapshot == null &&
                  state.catalog.refreshing) ...[
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: CircularProgressIndicator(
                      semanticsLabel: 'Loading walks',
                    ),
                  ),
                ),
                const ExcludeSemantics(
                  child: Column(
                    children: [
                      PlaceholderCard(),
                      SizedBox(height: 16),
                      PlaceholderCard(),
                    ],
                  ),
                ),
              ],
              if (state.catalog.snapshot != null && state.walks.isEmpty)
                Column(
                  children: [
                    const QuietMessage(message: 'No walks match your filters.'),
                    Center(
                      child: TextButton(
                        onPressed: () => widget.dispatch(const ClearFilters()),
                        child: const Text('Clear filters'),
                      ),
                    ),
                  ],
                ),
              for (final route in state.walks)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: _WalkCard(
                    route: route,
                    onTap: () => widget.dispatch(OpenDetail(route.walk.id)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WalkCard extends StatelessWidget {
  const _WalkCard({required this.route, required this.onTap});
  final WalkPresentation route;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLowest,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: InkWell(
        key: ValueKey('route-${route.walk.id}'),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 160,
              child: LandscapeArt(artKey: route.walk.artKey),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    route.walk.title,
                    style: FieldGuideType.cardTitle.copyWith(
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${route.duration} · ${route.distance}',
                    style: FieldGuideType.facts.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      StatusPill(
                        closed: route.walk.availability == Availability.closed,
                      ),
                      const Spacer(),
                      if (route.saved) const SavedMark(),
                    ],
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
    final scheme = Theme.of(context).colorScheme;
    if (detail == null) {
      return Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Back to walks',
                    onPressed: () => dispatch(const BackToList()),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Refresh walks',
                    onPressed: () => dispatch(const RefreshCatalog()),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              const QuietMessage(message: 'This walk is unavailable.'),
              TextButton(
                onPressed: () => dispatch(const BackToList()),
                child: const Text('Back to walks'),
              ),
            ],
          ),
        ),
      );
    }
    final terrain = detail.walk.terrain.name;
    return Scaffold(
      body: Stack(
        children: [
          ListView(
            padding: EdgeInsets.only(
              bottom: 28 + MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              SizedBox(
                height: 220,
                child: LandscapeArt(artKey: detail.walk.artKey),
              ),
              SafeArea(
                top: false,
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        detail.walk.title,
                        key: const ValueKey('detail-title'),
                        style: FieldGuideType.detailTitle.copyWith(
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 16),
                      FactsRow(
                        duration: detail.duration,
                        distance: detail.distance,
                        terrain:
                            '${terrain[0].toUpperCase()}${terrain.substring(1)}',
                      ),
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: StatusPill(
                          closed:
                              detail.walk.availability == Availability.closed,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _StatusMessages(state: state, dispatch: dispatch),
                      Text(
                        detail.walk.description,
                        style: FieldGuideType.body.copyWith(
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        key: const ValueKey('bookmark-action'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                          shape: const StadiumBorder(),
                          textStyle: FieldGuideType.button,
                        ),
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
                      if (state.disabledReason == 'closed')
                        const _Reason(
                          'This walk is closed. You can save it when it reopens.',
                        ),
                      if (state.disabledReason == 'stale')
                        const _Reason('Refresh walks before saving.'),
                      if (state.disabledReason == 'storage-unavailable')
                        const _Reason(
                          'Saved walks must load before you can make changes.',
                        ),
                      if (state.catalog.bookmarkError != null &&
                          state.catalog.bookmarkErrorId == detail.walk.id)
                        _InlineRetry(
                          message: state.catalog.bookmarkError!,
                          error: true,
                          label: 'Retry save',
                          onPressed: state.addEnabled || state.removeEnabled
                              ? () => dispatch(const RetryBookmark())
                              : null,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          // Pinned so back and refresh stay reachable while content scrolls.
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Align(
                alignment: Alignment.topCenter,
                child: Row(
                  children: [
                    HeroIconButton(
                      tooltip: 'Back to walks',
                      onPressed: () => dispatch(const BackToList()),
                      icon: Icons.arrow_back,
                    ),
                    const Spacer(),
                    HeroIconButton(
                      tooltip: 'Refresh walks',
                      onPressed: () => dispatch(const RefreshCatalog()),
                      icon: Icons.refresh,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Reason extends StatelessWidget {
  const _Reason(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: FieldGuideType.facts.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}
