package dev.fieldguide.feature.catalog

import org.junit.Assert.assertEquals
import org.junit.Test

class ArtFitTest {
    private fun assertFit(w: Float, h: Float, scale: Float, dx: Float, dy: Float) {
        val t = artFit(w, h)
        assertEquals(scale, t.scale, 0.001f); assertEquals(dx, t.dx, 0.01f); assertEquals(dy, t.dy, 0.01f)
    }
    @Test fun heroShowsNearlyWholeScene() = assertFit(393f, 220f, 1f, -3.5f, 0f)
    @Test fun cardCropsEvenly() = assertFit(353f, 160f, 0.8825f, 0f, -17.075f)
    @Test fun wideBoundsCropVertically() = assertFit(900f, 220f, 2.25f, 0f, -137.5f)
    @Test fun exactAspectIsIdentity() = assertFit(400f, 220f, 1f, 0f, 0f)
    @Test fun zeroHeightIsEmptyTransform() = assertFit(353f, 0f, 0f, 0f, 0f)
    @Test fun zeroWidthIsEmptyTransform() = assertFit(0f, 160f, 0f, 0f, 0f)
}
