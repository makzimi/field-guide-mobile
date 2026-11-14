package dev.fieldguide.feature.catalog

import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex

@Composable
fun FieldGuideScreens(view: FeatureView, dispatch: (FeatureAction) -> Unit) {
    FieldGuideTheme {
        Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
            when (view.screen) {
                ScreenKind.List -> WalkList(view, dispatch)
                ScreenKind.Detail -> WalkDetail(checkNotNull(view.detail), view, dispatch)
                ScreenKind.Unavailable -> UnavailableRoute(dispatch)
            }
        }
    }
}

@Composable
private fun WalkList(view: FeatureView, dispatch: (FeatureAction) -> Unit) {
    val scheme = MaterialTheme.colorScheme
    LazyColumn(
        modifier = Modifier.fillMaxSize().safeDrawingPadding().testTag("walk-list"),
        contentPadding = PaddingValues(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        item {
            Column {
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                    Text("FIELD GUIDE", color = scheme.secondary, style = FieldGuideType.eyebrow,
                        modifier = Modifier.weight(1f))
                    TextButton(onClick = { dispatch(FeatureAction.RefreshCatalog) },
                        modifier = Modifier.testTag("refresh-walks")) {
                        Icon(Icons.Default.Refresh, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("Refresh walks", style = FieldGuideType.button)
                    }
                }
                Text("Walks worth finding", color = scheme.onBackground, style = FieldGuideType.pageTitle)
            }
        }
        item {
            Text("Choose a walk for the time you have.", color = scheme.onSurfaceVariant,
                style = FieldGuideType.body)
            Spacer(Modifier.height(12.dp))
            OutlinedTextField(value = view.query, onValueChange = { dispatch(FeatureAction.SetQuery(it)) },
                label = { Text("Search walks") }, singleLine = true,
                leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
                shape = CircleShape,
                colors = OutlinedTextFieldDefaults.colors(
                    unfocusedContainerColor = scheme.surfaceVariant,
                    focusedContainerColor = scheme.surfaceVariant,
                    unfocusedBorderColor = Color.Transparent,
                    focusedBorderColor = scheme.primary,
                ),
                modifier = Modifier.fillMaxWidth().testTag("search-walks"))
        }
        item {
            Row(modifier = Modifier.horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf(15, 30, 60, 90).forEach { minutes ->
                    val selected = view.budgetMinutes == minutes
                    FilterChip(selected = selected,
                        onClick = { dispatch(FeatureAction.SetBudget(minutes)) },
                        label = { Text("$minutes minutes", style = FieldGuideType.button) },
                        shape = CircleShape,
                        colors = FilterChipDefaults.filterChipColors(
                            containerColor = Color.Transparent,
                            labelColor = scheme.onSurface,
                            selectedContainerColor = scheme.primary,
                            selectedLabelColor = scheme.onPrimary,
                        ),
                        border = FilterChipDefaults.filterChipBorder(
                            enabled = true, selected = selected,
                            borderColor = scheme.outlineVariant, selectedBorderColor = scheme.primary,
                        ),
                        modifier = Modifier.testTag("budget-$minutes"))
                }
            }
        }
        item {
            Column {
                Row(verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Icon(BookmarkIcon, contentDescription = null, tint = scheme.secondary,
                        modifier = Modifier.size(16.dp))
                    Text(if (view.savedCount == null) "Saved walks unavailable" else
                        "${view.savedCount} saved ${if (view.savedCount == 1) "walk" else "walks"}",
                        color = scheme.onSurfaceVariant, style = FieldGuideType.facts)
                }
                if (view.retrySavedWalksEnabled) TextButton(onClick = { dispatch(FeatureAction.RetrySavedWalks) },
                    modifier = Modifier.testTag("retry-saved-walks")) { Text("Retry saved walks", style = FieldGuideType.button) }
            }
        }
        if (view.staleWarning) item { NoticePanel("Walks may be out of date. Refresh to save a new walk.") }
        when (view.catalogKind) {
            CatalogViewKind.Loading -> item {
                Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    Column {
                        LinearProgressIndicator(Modifier.fillMaxWidth().testTag("catalog-progress"))
                        Spacer(Modifier.height(8.dp))
                        Text("Loading walks", color = scheme.onSurfaceVariant, style = FieldGuideType.facts)
                    }
                    PlaceholderCard()
                    PlaceholderCard()
                }
            }
            CatalogViewKind.FullError -> item {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    ErrorPanel("Walks could not be loaded.")
                    Button(onClick = { dispatch(FeatureAction.RetryCatalog) },
                        modifier = Modifier.testTag("retry-walks")) { Text("Retry walks", style = FieldGuideType.button) }
                }
            }
            else -> {
                if (view.catalogKind == CatalogViewKind.RefreshingFresh ||
                    view.catalogKind == CatalogViewKind.RefreshingStale) item {
                    Column {
                        LinearProgressIndicator(Modifier.fillMaxWidth().testTag("catalog-progress"))
                        Spacer(Modifier.height(8.dp))
                        Text("Refreshing walks", color = scheme.onSurfaceVariant, style = FieldGuideType.facts)
                    }
                }
                if (view.retryCatalogEnabled) item {
                    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        NoticePanel("Refresh failed. Showing the last available walks.")
                        TextButton(onClick = { dispatch(FeatureAction.RetryCatalog) },
                            modifier = Modifier.testTag("retry-walks")) { Text("Retry walks", style = FieldGuideType.button) }
                    }
                }
                if (view.list.isEmpty()) item {
                    Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
                        QuietMessage("No walks match these filters.")
                        TextButton(onClick = { dispatch(FeatureAction.ClearFilters) },
                            modifier = Modifier.testTag("clear-filters")) { Text("Clear filters", style = FieldGuideType.button) }
                    }
                }
                items(view.list, key = { it.id }) { walk -> WalkCard(walk) {
                    dispatch(FeatureAction.OpenDetail(walk.id))
                } }
            }
        }
    }
}

@Composable
private fun WalkCard(walk: WalkCardView, onClick: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    Card(modifier = Modifier.fillMaxWidth().clickable(onClick = onClick).testTag("walk-${walk.id}"),
        shape = RoundedCornerShape(22.dp),
        colors = CardDefaults.cardColors(containerColor = scheme.surfaceContainerLowest)) {
        Column {
            LandscapeArt(walk.artKey, Modifier.fillMaxWidth().height(160.dp))
            Column(Modifier.padding(16.dp)) {
                Text(walk.title, color = scheme.onSurface, style = FieldGuideType.cardTitle)
                Spacer(Modifier.height(4.dp))
                Text("${walk.durationLabel} · ${walk.distanceLabel}", color = scheme.onSurfaceVariant,
                    style = FieldGuideType.facts)
                Spacer(Modifier.height(12.dp))
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically) {
                    StatusPill(walk.closed)
                    if (walk.saved) SavedMark()
                }
            }
        }
    }
}

@Composable
private fun WalkDetail(detail: DetailView, view: FeatureView, dispatch: (FeatureAction) -> Unit) {
    val scheme = MaterialTheme.colorScheme
    Box(Modifier.fillMaxSize()) {
        // Pinned above the scrolling content; declared first so it is read first.
        HeroIconButton(onClick = { dispatch(FeatureAction.BackToList) },
            contentDescription = "Back to walks",
            icon = Icons.AutoMirrored.Filled.ArrowBack,
            modifier = Modifier.zIndex(1f)
                .windowInsetsPadding(WindowInsets.safeDrawing.only(
                    WindowInsetsSides.Top + WindowInsetsSides.Start))
                .padding(horizontal = 12.dp, vertical = 8.dp).testTag("back-to-walks"))
        Column(modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState())
            .testTag("walk-detail")) {
            LandscapeArt(detail.artKey, Modifier.fillMaxWidth().height(220.dp))
            Column(Modifier.windowInsetsPadding(WindowInsets.safeDrawing.only(
                    WindowInsetsSides.Horizontal + WindowInsetsSides.Bottom))
                    .padding(start = 20.dp, end = 20.dp, top = 20.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp)) {
                Text(detail.title, color = scheme.onSurface, style = FieldGuideType.detailTitle)
                FactsRow(detail.durationLabel, detail.distanceLabel, detail.terrainLabel)
                StatusPill(detail.closed)
                if (view.staleWarning) NoticePanel("Walks may be out of date. Refresh to save a new walk.")
                Text(detail.description, color = scheme.onSurface, style = FieldGuideType.body)
                Button(onClick = { dispatch(FeatureAction.Save) },
                    enabled = detail.addEnabled || detail.removeEnabled,
                    shape = CircleShape,
                    modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp).testTag("save-walk")) {
                    Text(if (detail.saveKind == SaveViewKind.Saving) "Saving" else detail.actionLabel,
                        style = FieldGuideType.button)
                }
                detail.disabledReason?.let { reason -> Text(when (reason) {
                    DisabledReason.Closed -> "Closed walks cannot be saved."
                    DisabledReason.Stale -> "Refresh walks to save this walk."
                    DisabledReason.StorageUnavailable -> "Saved walks are unavailable."
                    DisabledReason.Saving -> "Saving walk."
                }, color = scheme.onSurfaceVariant, style = FieldGuideType.facts, textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth()) }
                if (detail.saveKind == SaveViewKind.Error) {
                    ErrorPanel("Could not update saved walks. Your previous choice is unchanged.")
                    if (detail.inlineRetryEnabled) TextButton(onClick = { dispatch(FeatureAction.RetrySave) },
                        modifier = Modifier.testTag("retry-save")) { Text("Retry save", style = FieldGuideType.button) }
                }
                if (view.retrySavedWalksEnabled) TextButton(onClick = { dispatch(FeatureAction.RetrySavedWalks) },
                    modifier = Modifier.testTag("retry-saved-walks")) { Text("Retry saved walks", style = FieldGuideType.button) }
                Spacer(Modifier.height(28.dp))
            }
        }
    }
}

@Composable
private fun UnavailableRoute(dispatch: (FeatureAction) -> Unit) {
    Column(Modifier.fillMaxSize().safeDrawingPadding().padding(24.dp).testTag("unavailable-route"),
        verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
        Text("Walk unavailable", color = MaterialTheme.colorScheme.onSurface, style = FieldGuideType.detailTitle,
            textAlign = TextAlign.Center)
        QuietMessage("This walk is no longer in the current guide.")
        Spacer(Modifier.height(16.dp))
        Button(onClick = { dispatch(FeatureAction.BackToList) },
            modifier = Modifier.testTag("back-to-walks")) { Text("Back to walks", style = FieldGuideType.button) }
    }
}
