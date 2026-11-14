package dev.fieldguide.feature.catalog

import androidx.compose.material3.ColorScheme
import androidx.compose.ui.graphics.Color
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class DesignTokensTest {
    private val pairs: List<(ColorScheme) -> Pair<Color, Color>> = listOf(
        { it.onSurface to it.background }, { it.onSurface to it.surfaceContainerLowest },
        { it.onSurfaceVariant to it.background }, { it.onSurfaceVariant to it.surfaceContainerLowest },
        { it.onSurfaceVariant to it.surfaceVariant }, { it.onPrimary to it.primary },
        { it.onPrimaryContainer to it.primaryContainer }, { it.secondary to it.background },
        { it.secondary to it.surfaceContainerLowest },
        { it.onSecondaryContainer to it.secondaryContainer }, { it.onErrorContainer to it.errorContainer },
    )

    @Test fun contrastOfBlackOnWhiteIs21() =
        assertEquals(21.0, contrastRatio(Color.Black, Color.White), 0.01)

    @Test fun everyLightTextPairingReaches4_5() = pairs.forEach { pair ->
        val (fg, bg) = pair(FieldGuideLightColors)
        assertTrue("$fg on $bg", contrastRatio(fg, bg) >= 4.5)
    }

    @Test fun everyDarkTextPairingReaches4_5() = pairs.forEach { pair ->
        val (fg, bg) = pair(FieldGuideDarkColors)
        assertTrue("$fg on $bg", contrastRatio(fg, bg) >= 4.5)
    }

    @Test fun existingRolesKeepTheirR1Values() {
        assertEquals(Color(0xFF245B45), FieldGuideLightColors.primary)
        assertEquals(Color(0xFFA35A40), FieldGuideLightColors.secondary)
        assertEquals(Color(0xFFF8F5EC), FieldGuideLightColors.background)
        assertEquals(Color(0xFF17251D), FieldGuideDarkColors.background)
        assertEquals(Color(0xFF1C2B22), FieldGuideDarkColors.surface)
    }

    @Test fun lightArtPaletteMatchesBoard() {
        assertEquals(Color(0xFFDCE8D6), LightArtPalette.skyPine)
        assertEquals(Color(0xFF245B45), LightArtPalette.pineNear)
        assertEquals(Color(0xFF8FC1C6), LightArtPalette.water)
        assertEquals(Color(0xFFFBF4EA), LightArtPalette.snow)
    }

    @Test fun darkArtKeepsForegroundDarkerThanSky() {
        fun lum(c: Color) = contrastRatio(c, Color.Black)
        assertTrue(lum(DarkArtPalette.groundDeep) < lum(DarkArtPalette.skyPine))
        assertTrue(lum(DarkArtPalette.sun) > lum(DarkArtPalette.skyRidge))
    }
}
