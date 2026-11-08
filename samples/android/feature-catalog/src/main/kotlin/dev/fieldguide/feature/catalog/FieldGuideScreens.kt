package dev.fieldguide.feature.catalog

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import dev.fieldguide.catalog.api.ArtKey

private val Pine = Color(0xFF245B45)
private val Clay = Color(0xFFA85E43)
private val Ivory = Color(0xFFF8F5EC)
private val Ink = Color(0xFF263A30)

private val Light = lightColorScheme(primary = Pine, secondary = Clay, background = Ivory,
    surface = Ivory, surfaceVariant = Color(0xFFEAE9DE), onBackground = Ink, onSurface = Ink)
private val Dark = darkColorScheme(primary = Color(0xFF9DCEAD), secondary = Color(0xFFE0A990),
    background = Color(0xFF17251D), surface = Color(0xFF1C2B22), surfaceVariant = Color(0xFF304337),
    onBackground = Color(0xFFF3F0E8), onSurface = Color(0xFFF3F0E8))

@Composable
fun FieldGuideScreens(view: FeatureView, dispatch: (FeatureAction) -> Unit) {
    MaterialTheme(colorScheme = if (androidx.compose.foundation.isSystemInDarkTheme()) Dark else Light) {
        Surface(modifier = Modifier.fillMaxSize()) {
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
    LazyColumn(
        modifier = Modifier.fillMaxSize().safeDrawingPadding().testTag("walk-list"),
        contentPadding = PaddingValues(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        item {
            Row(horizontalArrangement = Arrangement.SpaceBetween, modifier = Modifier.fillMaxWidth()) {
                Column(Modifier.weight(1f)) {
                    Text("FIELD GUIDE", color = MaterialTheme.colorScheme.secondary,
                        style = MaterialTheme.typography.labelLarge)
                    Text("Walks worth finding", style = MaterialTheme.typography.headlineMedium,
                        fontWeight = FontWeight.Bold)
                }
                TextButton(onClick = { dispatch(FeatureAction.RefreshCatalog) },
                    modifier = Modifier.testTag("refresh-walks")) { Text("Refresh walks") }
            }
        }
        item {
            Text("Choose a walk for the time you have.", style = MaterialTheme.typography.bodyLarge)
            Spacer(Modifier.height(12.dp))
            OutlinedTextField(value = view.query, onValueChange = { dispatch(FeatureAction.SetQuery(it)) },
                label = { Text("Search walks") }, singleLine = true, modifier = Modifier.fillMaxWidth().testTag("search-walks"))
        }
        item {
            Row(modifier = Modifier.horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf(15, 30, 60, 90).forEach { minutes ->
                    FilterChip(selected = view.budgetMinutes == minutes,
                        onClick = { dispatch(FeatureAction.SetBudget(minutes)) },
                        label = { Text("$minutes minutes") }, modifier = Modifier.testTag("budget-$minutes"))
                }
            }
        }
        item {
            Text(if (view.savedCount == null) "Saved walks unavailable" else
                "${view.savedCount} saved ${if (view.savedCount == 1) "walk" else "walks"}",
                style = MaterialTheme.typography.titleMedium)
            if (view.retrySavedWalksEnabled) TextButton(onClick = { dispatch(FeatureAction.RetrySavedWalks) },
                modifier = Modifier.testTag("retry-saved-walks")) { Text("Retry saved walks") }
        }
        if (view.staleWarning) item { StatusPanel("Walks may be out of date. Refresh to save a new walk.") }
        when (view.catalogKind) {
            CatalogViewKind.Loading -> item {
                LinearProgressIndicator(Modifier.fillMaxWidth().testTag("catalog-progress"))
                Text("Loading walks")
            }
            CatalogViewKind.FullError -> item {
                StatusPanel("Walks could not be loaded.")
                Button(onClick = { dispatch(FeatureAction.RetryCatalog) },
                    modifier = Modifier.testTag("retry-walks")) { Text("Retry walks") }
            }
            else -> {
                if (view.catalogKind == CatalogViewKind.RefreshingFresh ||
                    view.catalogKind == CatalogViewKind.RefreshingStale) item {
                    LinearProgressIndicator(Modifier.fillMaxWidth().testTag("catalog-progress"))
                    Text("Refreshing walks")
                }
                if (view.retryCatalogEnabled) item {
                    StatusPanel("Refresh failed. Showing the last available walks.")
                    TextButton(onClick = { dispatch(FeatureAction.RetryCatalog) },
                        modifier = Modifier.testTag("retry-walks")) { Text("Retry walks") }
                }
                if (view.list.isEmpty()) item {
                    StatusPanel("No walks match these filters.")
                    TextButton(onClick = { dispatch(FeatureAction.ClearFilters) },
                        modifier = Modifier.testTag("clear-filters")) { Text("Clear filters") }
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
    Card(modifier = Modifier.fillMaxWidth().clickable(onClick = onClick).testTag("walk-${walk.id}"),
        shape = RoundedCornerShape(22.dp), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)) {
        Column {
            LandscapeArt(walk.artKey, Modifier.fillMaxWidth().height(112.dp))
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(walk.title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
                Text("${walk.durationLabel} · ${walk.distanceLabel}")
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(if (walk.closed) "Closed" else "Open", color = MaterialTheme.colorScheme.primary)
                    if (walk.saved) Text("Saved", color = MaterialTheme.colorScheme.secondary)
                }
            }
        }
    }
}

@Composable
private fun WalkDetail(detail: DetailView, view: FeatureView, dispatch: (FeatureAction) -> Unit) {
    Column(modifier = Modifier.fillMaxSize().safeDrawingPadding().verticalScroll(rememberScrollState())
        .testTag("walk-detail"), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        TextButton(onClick = { dispatch(FeatureAction.BackToList) },
            modifier = Modifier.padding(start = 12.dp).testTag("back-to-walks")) { Text("Back to walks") }
        LandscapeArt(detail.artKey, Modifier.fillMaxWidth().height(220.dp))
        Column(Modifier.padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Text(detail.title, style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
            Text("${detail.durationLabel} · ${detail.distanceLabel} · ${detail.terrainLabel}",
                style = MaterialTheme.typography.titleMedium)
            Text(if (detail.closed) "Closed" else "Open", color = MaterialTheme.colorScheme.primary)
            if (view.staleWarning) StatusPanel("Walks may be out of date. Refresh to save a new walk.")
            Text(detail.description, style = MaterialTheme.typography.bodyLarge)
            Button(onClick = { dispatch(FeatureAction.Save) },
                enabled = detail.addEnabled || detail.removeEnabled,
                modifier = Modifier.fillMaxWidth().testTag("save-walk")) {
                Text(if (detail.saveKind == SaveViewKind.Saving) "Saving" else detail.actionLabel)
            }
            detail.disabledReason?.let { reason -> Text(when (reason) {
                DisabledReason.Closed -> "Closed walks cannot be saved."
                DisabledReason.Stale -> "Refresh walks to save this walk."
                DisabledReason.StorageUnavailable -> "Saved walks are unavailable."
                DisabledReason.Saving -> "Saving walk."
            }) }
            if (detail.saveKind == SaveViewKind.Error) {
                StatusPanel("Could not update saved walks. Your previous choice is unchanged.")
                if (detail.inlineRetryEnabled) TextButton(onClick = { dispatch(FeatureAction.RetrySave) },
                    modifier = Modifier.testTag("retry-save")) { Text("Retry save") }
            }
            if (view.retrySavedWalksEnabled) TextButton(onClick = { dispatch(FeatureAction.RetrySavedWalks) },
                modifier = Modifier.testTag("retry-saved-walks")) { Text("Retry saved walks") }
            Spacer(Modifier.height(28.dp))
        }
    }
}

@Composable
private fun UnavailableRoute(dispatch: (FeatureAction) -> Unit) {
    Column(Modifier.fillMaxSize().safeDrawingPadding().padding(24.dp).testTag("unavailable-route"),
        verticalArrangement = Arrangement.Center) {
        Text("Walk unavailable", style = MaterialTheme.typography.headlineMedium)
        Spacer(Modifier.height(12.dp))
        Text("This walk is no longer in the current guide.")
        Spacer(Modifier.height(16.dp))
        Button(onClick = { dispatch(FeatureAction.BackToList) },
            modifier = Modifier.testTag("back-to-walks")) { Text("Back to walks") }
    }
}

@Composable
private fun StatusPanel(message: String) {
    Surface(color = MaterialTheme.colorScheme.surfaceVariant, shape = RoundedCornerShape(16.dp)) {
        Text(message, modifier = Modifier.padding(16.dp), style = MaterialTheme.typography.bodyMedium)
    }
}

/** Original, locally rendered landscape shapes; no network or external image dependency. */
@Composable
private fun LandscapeArt(key: ArtKey, modifier: Modifier = Modifier) {
    val sky = when (key) {
        ArtKey.Pine -> Color(0xFFD8E5D4)
        ArtKey.Glasshouse -> Color(0xFFEBDDCB)
        ArtKey.Canal -> Color(0xFFD5E5E5)
        ArtKey.Ridge -> Color(0xFFE9D9C8)
    }
    Canvas(modifier.background(Brush.verticalGradient(listOf(sky, Color(0xFFF4F0DF))))) {
        val w = size.width; val h = size.height
        drawCircle(Color(0xFFF3C88B), radius = h * .22f, center = Offset(w * .78f, h * .31f))
        val back = Path().apply {
            moveTo(0f, h * .72f); lineTo(w * .28f, h * .40f); lineTo(w * .58f, h * .77f)
            lineTo(w, h * .49f); lineTo(w, h); lineTo(0f, h); close()
        }
        drawPath(back, Color(0xFF8DAB8D))
        val front = Path().apply {
            moveTo(0f, h * .90f); lineTo(w * .35f, h * .66f); lineTo(w * .72f, h * .86f)
            lineTo(w, h * .72f); lineTo(w, h); lineTo(0f, h); close()
        }
        drawPath(front, Color(0xFF416C52))
    }
}
