package dev.fieldguide.feature.catalog

import android.content.res.Configuration
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.addPathNodes
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.text
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp

/** Material "bookmark" path on a 24x24 viewport, built in code (no icon dependency needed). */
internal val BookmarkIcon: ImageVector = ImageVector.Builder(
    name = "Bookmark", defaultWidth = 24.dp, defaultHeight = 24.dp, viewportWidth = 24f, viewportHeight = 24f,
).addPath(
    pathData = addPathNodes("M17,3H7C5.9,3 5,3.9 5,5v16l7,-3 7,3V5C19,3.9 18.1,3 17,3z"),
    fill = SolidColor(Color.Black),
).build()

@Composable
internal fun StatusPill(closed: Boolean) {
    val scheme = MaterialTheme.colorScheme
    val container = if (closed) scheme.surfaceVariant else scheme.primaryContainer
    val content = if (closed) scheme.onSurfaceVariant else scheme.onPrimaryContainer
    Row(
        modifier = Modifier.clip(CircleShape).background(container).padding(horizontal = 12.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (!closed) {
            Box(Modifier.size(6.dp).clip(CircleShape).background(content))
            Spacer(Modifier.width(6.dp))
        }
        Text(if (closed) "Closed" else "Open", color = content, style = FieldGuideType.facts)
    }
}

@Composable
internal fun SavedMark() {
    val color = MaterialTheme.colorScheme.secondary
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        Icon(BookmarkIcon, contentDescription = null, tint = color, modifier = Modifier.size(16.dp))
        Text("Saved", color = color, style = FieldGuideType.facts)
    }
}

@Composable
private fun MessagePanel(
    message: String,
    container: Color,
    content: Color,
    icon: ImageVector,
) {
    Surface(color = container, shape = RoundedCornerShape(16.dp), modifier = Modifier.fillMaxWidth()) {
        Row(Modifier.padding(16.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Icon(icon, contentDescription = null, tint = content, modifier = Modifier.size(20.dp))
            Text(message, color = content, style = FieldGuideType.facts, modifier = Modifier.weight(1f))
        }
    }
}

@Composable
internal fun NoticePanel(message: String) = MessagePanel(
    message, MaterialTheme.colorScheme.secondaryContainer,
    MaterialTheme.colorScheme.onSecondaryContainer, Icons.Default.Info,
)

@Composable
internal fun ErrorPanel(message: String) = MessagePanel(
    message, MaterialTheme.colorScheme.errorContainer,
    MaterialTheme.colorScheme.onErrorContainer, Icons.Default.Warning,
)

@Composable
internal fun QuietMessage(message: String) {
    Text(
        message, color = MaterialTheme.colorScheme.onSurfaceVariant, style = FieldGuideType.body,
        textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(top = 32.dp),
    )
}

@Composable
private fun FactColumn(caption: String, value: String, modifier: Modifier = Modifier) {
    Column(modifier.padding(vertical = 12.dp)) {
        Text(caption, color = MaterialTheme.colorScheme.onSurfaceVariant, style = FieldGuideType.facts)
        Text(value, color = MaterialTheme.colorScheme.onSurface, style = FieldGuideType.factValue)
    }
}

/**
 * Three columns normally. Stacked caption-and-value pairs when the system font scale is 1.3 or
 * more (deterministic rule: three ~93 dp columns break words such as "Waterside" at that size).
 * Text is never truncated or shrunk. One semantics node carries the joined facts in both layouts.
 */
@Composable
internal fun FactsRow(duration: String, distance: String, terrain: String) {
    val hairline = MaterialTheme.colorScheme.outlineVariant
    val stacked = LocalDensity.current.fontScale >= 1.3f
    Column(
        Modifier.fillMaxWidth()
            .clearAndSetSemantics { text = AnnotatedString("$duration · $distance · $terrain") },
    ) {
        Box(Modifier.fillMaxWidth().height(1.dp).background(hairline))
        if (stacked) {
            FactColumn("Time", duration, Modifier.fillMaxWidth())
            Box(Modifier.fillMaxWidth().height(1.dp).background(hairline))
            FactColumn("Distance", distance, Modifier.fillMaxWidth())
            Box(Modifier.fillMaxWidth().height(1.dp).background(hairline))
            FactColumn("Terrain", terrain, Modifier.fillMaxWidth())
        } else {
            Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min)) {
                FactColumn("Time", duration, Modifier.weight(1f))
                Box(Modifier.padding(horizontal = 12.dp, vertical = 12.dp).width(1.dp).fillMaxHeight()
                    .background(hairline))
                FactColumn("Distance", distance, Modifier.weight(1f))
                Box(Modifier.padding(horizontal = 12.dp, vertical = 12.dp).width(1.dp).fillMaxHeight()
                    .background(hairline))
                FactColumn("Terrain", terrain, Modifier.weight(1f))
            }
        }
        Box(Modifier.fillMaxWidth().height(1.dp).background(hairline))
    }
}

@Composable
internal fun PlaceholderCard() {
    Box(
        Modifier.fillMaxWidth().height(240.dp).clip(RoundedCornerShape(22.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant).clearAndSetSemantics {},
    )
}

@Composable
internal fun HeroIconButton(
    onClick: () -> Unit,
    contentDescription: String,
    modifier: Modifier = Modifier,
    icon: ImageVector,
) {
    IconButton(
        onClick = onClick,
        modifier = modifier.size(40.dp).clip(CircleShape)
            .background(MaterialTheme.colorScheme.surface)
            .border(1.dp, MaterialTheme.colorScheme.outlineVariant, CircleShape),
    ) {
        Icon(icon, contentDescription = contentDescription, tint = MaterialTheme.colorScheme.onSurface)
    }
}

@Preview(name = "Open · light")
@Preview(name = "Open · dark", uiMode = Configuration.UI_MODE_NIGHT_YES)
@Composable
private fun StatusPillOpenPreview() {
    FieldGuideTheme { StatusPill(closed = false) }
}

@Preview(name = "Closed · light")
@Preview(name = "Closed · dark", uiMode = Configuration.UI_MODE_NIGHT_YES)
@Composable
private fun StatusPillClosedPreview() {
    FieldGuideTheme { StatusPill(closed = true) }
}
