package dev.fieldguide.feature.catalog

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.compositeOver
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import kotlin.math.pow

internal val FieldGuideSerif: FontFamily = FontFamily(Font(R.font.source_serif_4_semibold, FontWeight.SemiBold))

internal val FieldGuideLightColors: ColorScheme = lightColorScheme(
    background = Color(0xFFF8F5EC),
    surface = Color(0xFFF8F5EC),
    surfaceContainerLowest = Color(0xFFFFFFFF),
    surfaceVariant = Color(0xFFEAE9DE),
    onBackground = Color(0xFF263A30),
    onSurface = Color(0xFF263A30),
    onSurfaceVariant = Color(0xFF5C6B61),
    outlineVariant = Color(0xFFDCDCCF),
    primary = Color(0xFF245B45),
    onPrimary = Color(0xFFFFFFFF),
    primaryContainer = Color(0xFFD8E5D4),
    onPrimaryContainer = Color(0xFF1D4A39),
    secondary = Color(0xFFA35A40),
    secondaryContainer = Color(0xFFF3E0D6),
    onSecondaryContainer = Color(0xFF6E3A27),
    errorContainer = Color(0xFFF6DDD6),
    onErrorContainer = Color(0xFF7A2E1E),
)

internal val FieldGuideDarkColors: ColorScheme = darkColorScheme(
    background = Color(0xFF17251D),
    surface = Color(0xFF1C2B22),
    surfaceContainerLowest = Color(0xFF22332A),
    surfaceVariant = Color(0xFF304337),
    onBackground = Color(0xFFF3F0E8),
    onSurface = Color(0xFFF3F0E8),
    onSurfaceVariant = Color(0xFFB9C4BB),
    outlineVariant = Color(0xFF3A4D41),
    primary = Color(0xFF9DCEAD),
    onPrimary = Color(0xFF12301F),
    primaryContainer = Color(0xFF2E4A3A),
    onPrimaryContainer = Color(0xFFCFE8D6),
    secondary = Color(0xFFE0A990),
    secondaryContainer = Color(0xFF5A3A2C),
    onSecondaryContainer = Color(0xFFF5D9CB),
    errorContainer = Color(0xFF5C2B22),
    onErrorContainer = Color(0xFFF8D8D0),
)

/** WCAG 2 contrast ratio of two opaque colors. */
internal fun contrastRatio(foreground: Color, background: Color): Double {
    val fg = relativeLuminance(foreground.compositeOver(background))
    val bg = relativeLuminance(background)
    return (maxOf(fg, bg) + 0.05) / (minOf(fg, bg) + 0.05)
}

private fun relativeLuminance(color: Color): Double {
    fun channel(value: Float): Double {
        val v = value.toDouble()
        return if (v <= 0.03928) v / 12.92 else ((v + 0.055) / 1.055).pow(2.4)
    }
    return 0.2126 * channel(color.red) + 0.7152 * channel(color.green) + 0.0722 * channel(color.blue)
}

internal object FieldGuideType {
    val pageTitle = TextStyle(fontFamily = FieldGuideSerif, fontWeight = FontWeight.SemiBold,
        fontSize = 30.sp, lineHeight = 36.sp)
    val detailTitle = TextStyle(fontFamily = FieldGuideSerif, fontWeight = FontWeight.SemiBold,
        fontSize = 28.sp, lineHeight = 34.sp)
    val cardTitle = TextStyle(fontFamily = FieldGuideSerif, fontWeight = FontWeight.SemiBold,
        fontSize = 20.sp, lineHeight = 26.sp)
    val eyebrow = TextStyle(fontWeight = FontWeight.Medium, fontSize = 12.sp, lineHeight = 16.sp,
        letterSpacing = 0.08.em)
    val body = TextStyle(fontWeight = FontWeight.Normal, fontSize = 16.sp, lineHeight = 24.sp)
    val facts = TextStyle(fontWeight = FontWeight.Normal, fontSize = 14.sp, lineHeight = 20.sp)
    val factValue = TextStyle(fontWeight = FontWeight.Medium, fontSize = 16.sp, lineHeight = 22.sp)
    val button = TextStyle(fontWeight = FontWeight.Medium, fontSize = 14.sp, lineHeight = 20.sp)
}

@Composable
internal fun FieldGuideTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = if (isSystemInDarkTheme()) FieldGuideDarkColors else FieldGuideLightColors,
        content = content,
    )
}
