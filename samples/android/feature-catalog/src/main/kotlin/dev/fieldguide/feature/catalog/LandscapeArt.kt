package dev.fieldguide.feature.catalog

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.semantics.clearAndSetSemantics
import dev.fieldguide.catalog.api.ArtKey
import kotlin.math.atan2
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

// Original, locally drawn walk scenes. Geometry is ported from
// project/proposals/sample-app-design-r2-art.html in its 400x220 design box.
// Layout of this file: palette, fit, shared shapes, one draw function per scene.

// ---------------------------------------------------------------------------
// Palette
// ---------------------------------------------------------------------------

/**
 * Named art colors. `cloud` and `ripple` are opaque white; their per-mode strength is
 * `cloudAlpha` and `rippleAlpha`. `shadeAlpha` is the strength of the black overlay on
 * pine and peak faces drawn with [shade].
 */
internal data class ArtPalette(
    val skyPine: Color, val skyGlasshouse: Color, val skyCanal: Color, val skyRidge: Color,
    val skyHaze: Color,
    val sun: Color, val sunHalo: Color, val cloud: Color,
    val farRange: Color, val farShade: Color,
    val warmRange1: Color, val warmShade1: Color, val warmRange2: Color, val warmShade2: Color,
    val middleGround: Color,
    val foliageLight: Color, val foliageMid: Color, val foliageDeep: Color,
    val pineFar: Color, val pineMid: Color, val pineNear: Color, val pineDeep: Color,
    val ground: Color, val groundDeep: Color, val lawn: Color, val path: Color,
    val water: Color, val waterDeep: Color,
    val glass: Color, val glassFrame: Color, val stone: Color, val stoneLine: Color,
    val snow: Color, val trunk: Color, val accent: Color, val bird: Color,
    val flowerLight: Color, val flowerWarm: Color,
    val rock: Color, val cairnLight: Color, val cairnDark: Color, val distantGround: Color,
    val shadeAlpha: Float, val cloudAlpha: Float, val rippleAlpha: Float,
)

internal val LightArtPalette = ArtPalette(
    skyPine = Color(0xFFDCE8D6), skyGlasshouse = Color(0xFFEFE1CE), skyCanal = Color(0xFFD7E7E6),
    skyRidge = Color(0xFFF1E4D2), skyHaze = Color(0xFFEBD3BF),
    sun = Color(0xFFF2BC74), sunHalo = Color(0xFFF3C88B), cloud = Color(0xFFFFFFFF),
    farRange = Color(0xFFBBD0BE), farShade = Color(0xFFA9C2AE),
    warmRange1 = Color(0xFFDDBFA8), warmShade1 = Color(0xFFCDA98F),
    warmRange2 = Color(0xFFB98A6E), warmShade2 = Color(0xFFA67859),
    middleGround = Color(0xFF8DAB8D),
    foliageLight = Color(0xFF86AC7C), foliageMid = Color(0xFF6E9468), foliageDeep = Color(0xFF5C8459),
    pineFar = Color(0xFF5E8A6B), pineMid = Color(0xFF2E6B52), pineNear = Color(0xFF245B45),
    pineDeep = Color(0xFF1D4A39),
    ground = Color(0xFF416C52), groundDeep = Color(0xFF2B5240), lawn = Color(0xFF7FA372),
    path = Color(0xFFE9E2CC), water = Color(0xFF8FC1C6), waterDeep = Color(0xFF6FA5AC),
    glass = Color(0xFFDCECE6), glassFrame = Color(0xFF4F6F60),
    stone = Color(0xFFCDBBA2), stoneLine = Color(0xFFA8957C),
    snow = Color(0xFFFBF4EA), trunk = Color(0xFF5B4332), accent = Color(0xFFA85E43),
    bird = Color(0xFF4C5A50), flowerLight = Color(0xFFF7EFE2), flowerWarm = Color(0xFFF3C88B),
    rock = Color(0xFF5D6F5F), cairnLight = Color(0xFFA3927F), cairnDark = Color(0xFF8A7A6A),
    distantGround = Color(0xFF6F7F62),
    shadeAlpha = 0.16f, cloudAlpha = 0.75f, rippleAlpha = 0.65f,
)

internal val DarkArtPalette = ArtPalette(
    skyPine = Color(0xFF1E3A33), skyGlasshouse = Color(0xFF2E3340), skyCanal = Color(0xFF1C3540),
    skyRidge = Color(0xFF33303F), skyHaze = Color(0xFF3A3444),
    sun = Color(0xFFE9E4CF), sunHalo = Color(0xFFC9CDB8), cloud = Color(0xFFFFFFFF),
    farRange = Color(0xFF3C5A50), farShade = Color(0xFF34504A),
    warmRange1 = Color(0xFF5C5566), warmShade1 = Color(0xFF4E4858),
    warmRange2 = Color(0xFF453F52), warmShade2 = Color(0xFF3A3546),
    middleGround = Color(0xFF2F4D41),
    foliageLight = Color(0xFF4A6E58), foliageMid = Color(0xFF3B5C49), foliageDeep = Color(0xFF2F4D3D),
    pineFar = Color(0xFF2D5042), pineMid = Color(0xFF1F4034), pineNear = Color(0xFF18352B),
    pineDeep = Color(0xFF122A22),
    ground = Color(0xFF1B352B), groundDeep = Color(0xFF132720), lawn = Color(0xFF2C4A3A),
    path = Color(0xFF8E8A76), water = Color(0xFF2F5C68), waterDeep = Color(0xFF244B56),
    glass = Color(0xFFF0D9A0), glassFrame = Color(0xFF1D332B),
    stone = Color(0xFF6B6558), stoneLine = Color(0xFF514C42),
    snow = Color(0xFFC9CBD6), trunk = Color(0xFF2A211B), accent = Color(0xFFB26E54),
    bird = Color(0xFF9AA79E), flowerLight = Color(0xFFBFB9A8), flowerWarm = Color(0xFFB89A68),
    rock = Color(0xFF2A3A31), cairnLight = Color(0xFF5E574D), cairnDark = Color(0xFF4A443C),
    distantGround = Color(0xFF2B3D33),
    shadeAlpha = 0.22f, cloudAlpha = 0.12f, rippleAlpha = 0.22f,
)

// ---------------------------------------------------------------------------
// Fit
// ---------------------------------------------------------------------------

private const val ART_W = 400f
private const val ART_H = 220f

internal data class ArtTransform(val scale: Float, val dx: Float, val dy: Float)

/**
 * Uniform cover scale of the 400x220 box, centered horizontally. Vertical overflow is cropped
 * evenly from the top and bottom. Empty bounds give an empty transform.
 */
internal fun artFit(width: Float, height: Float): ArtTransform {
    if (width <= 0f || height <= 0f) return ArtTransform(0f, 0f, 0f)
    val scale = max(width / ART_W, height / ART_H)
    val dx = (width - ART_W * scale) / 2f
    val overflow = ART_H * scale - height
    return ArtTransform(scale, dx, -overflow / 2f)
}

@Composable
internal fun LandscapeArt(key: ArtKey, modifier: Modifier = Modifier) {
    val palette = if (isSystemInDarkTheme()) DarkArtPalette else LightArtPalette
    Canvas(modifier.clipToBounds().clearAndSetSemantics {}) {
        val t = artFit(size.width, size.height)
        if (t.scale <= 0f) return@Canvas
        withTransform({
            translate(t.dx, t.dy)
            scale(t.scale, t.scale, Offset.Zero)
        }) {
            when (key) {
                ArtKey.Pine -> drawPineScene(palette)
                ArtKey.Glasshouse -> drawGlasshouseScene(palette)
                ArtKey.Canal -> drawCanalScene(palette)
                ArtKey.Ridge -> drawRidgeScene(palette)
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Drawing helpers
// ---------------------------------------------------------------------------

private fun DrawScope.rect(x: Float, y: Float, w: Float, h: Float, c: Color) =
    drawRect(c, Offset(x, y), Size(w, h))

private fun DrawScope.disc(cx: Float, cy: Float, r: Float, c: Color) = drawCircle(c, r, Offset(cx, cy))

private fun DrawScope.oval(cx: Float, cy: Float, rx: Float, ry: Float, c: Color) =
    drawOval(c, Offset(cx - rx, cy - ry), Size(rx * 2f, ry * 2f))

private fun DrawScope.fill(p: Path, c: Color) = drawPath(p, c)

private fun DrawScope.line(
    p: Path, c: Color, w: Float, cap: StrokeCap = StrokeCap.Butt, join: StrokeJoin = StrokeJoin.Miter,
) = drawPath(p, c, style = Stroke(width = w, cap = cap, join = join))

/** Closed polygon(s): each call of `sub` starts a new closed subpath. */
private fun Path.sub(vararg v: Float): Path {
    moveTo(v[0], v[1])
    for (i in 2 until v.size step 2) lineTo(v[i], v[i + 1])
    close()
    return this
}

private fun polygon(vararg v: Float): Path = Path().sub(*v)

private fun polyline(vararg v: Float): Path = Path().apply {
    moveTo(v[0], v[1])
    for (i in 2 until v.size step 2) lineTo(v[i], v[i + 1])
}

/** Open segments given as x0, y0, x1, y1 quadruples. */
private fun segments(vararg v: Float): Path = Path().apply {
    for (i in v.indices step 4) { moveTo(v[i], v[i + 1]); lineTo(v[i + 2], v[i + 3]) }
}

/** SVG small arc with sweep flag 1 (clockwise on screen) from the current point to (x1, y1). */
private fun Path.arcCw(x0: Float, y0: Float, x1: Float, y1: Float, r: Float) {
    val dx = x1 - x0; val dy = y1 - y0
    val half = sqrt(dx * dx + dy * dy) / 2f
    val rr = max(r, half) // SVG scales an undersized radius up to the half chord
    val h = sqrt(max(rr * rr - half * half, 0f))
    val cx = (x0 + x1) / 2f + h * (-dy) / (2f * half)
    val cy = (y0 + y1) / 2f + h * dx / (2f * half)
    val a0 = Math.toDegrees(atan2((y0 - cy).toDouble(), (x0 - cx).toDouble())).toFloat()
    val a1 = Math.toDegrees(atan2((y1 - cy).toDouble(), (x1 - cx).toDouble())).toFloat()
    var sweep = a1 - a0
    while (sweep <= 0f) sweep += 360f
    arcTo(Rect(cx - rr, cy - rr, cx + rr, cy + rr), a0, sweep, false)
}

/** Places a symbol of viewBox vw x vh in the x, y, w, h box (SVG xMidYMid meet). */
private fun DrawScope.place(
    x: Float, y: Float, w: Float, h: Float, vw: Float, vh: Float, draw: DrawScope.(Float) -> Unit,
) {
    val s = min(w / vw, h / vh)
    withTransform({
        translate(x + (w - vw * s) / 2f, y + (h - vh * s) / 2f)
        scale(s, s, Offset.Zero)
    }) { draw(s) }
}

// ---------------------------------------------------------------------------
// Shared shapes: pine (40x80), cloud (80x24), bird (16x6)
// ---------------------------------------------------------------------------

// Paths are built per draw: android.graphics.Path is unavailable to JVM unit tests at class init.
private fun pineTiers() = polygon(20f, 4f, 32f, 30f, 8f, 30f)
    .sub(20f, 18f, 35f, 48f, 5f, 48f)
    .sub(20f, 34f, 38f, 68f, 2f, 68f)

private fun pineShade() = polygon(20f, 4f, 32f, 30f, 20f, 30f)
    .sub(20f, 18f, 35f, 48f, 20f, 48f)
    .sub(20f, 34f, 38f, 68f, 20f, 68f)

private fun DrawScope.pine(p: ArtPalette, x: Float, y: Float, w: Float, h: Float, color: Color) =
    place(x, y, w, h, 40f, 80f) {
        rect(18f, 60f, 4f, 20f, p.trunk)
        fill(pineTiers(), color)
        fill(pineShade(), Color.Black.copy(alpha = p.shadeAlpha))
    }

private fun cloudShape() = Path().apply {
    moveTo(8f, 20f)
    arcCw(8f, 20f, 14f, 6f, 8f)
    arcCw(14f, 6f, 36f, 3f, 12f)
    arcCw(36f, 3f, 54f, 8f, 10f)
    arcCw(54f, 8f, 66f, 20f, 7f)
    close()
}

private fun DrawScope.cloud(p: ArtPalette, x: Float, y: Float, w: Float, h: Float) =
    place(x, y, w, h, 80f, 24f) { fill(cloudShape(), p.cloud.copy(alpha = p.cloudAlpha)) }

private fun birdShape() = Path().apply {
    moveTo(1f, 5f); quadraticTo(4.5f, 0f, 8f, 5f); quadraticTo(11.5f, 0f, 15f, 5f)
}

private fun DrawScope.bird(p: ArtPalette, x: Float, y: Float, w: Float, h: Float) =
    place(x, y, w, h, 16f, 6f) { line(birdShape(), p.bird, 1.2f, StrokeCap.Round) }

/** Sun disc with two halo rings. */
private fun DrawScope.sun(
    p: ArtPalette, cx: Float, cy: Float, r1: Float, r2: Float, r3: Float, a1: Float, a2: Float,
) {
    disc(cx, cy, r1, p.sunHalo.copy(alpha = a1))
    disc(cx, cy, r2, p.sunHalo.copy(alpha = a2))
    disc(cx, cy, r3, p.sun)
}

private fun DrawScope.tuft(x: Float, y: Float, c: Color) =
    line(segments(x, y, x - 3f, y - 8f, x, y, x + 1f, y - 10f, x, y, x + 5f, y - 7f), c, 1.5f, StrokeCap.Round)

// ---------------------------------------------------------------------------
// Scene: pine
// ---------------------------------------------------------------------------

private fun DrawScope.drawPineScene(p: ArtPalette) {
    rect(0f, 0f, ART_W, ART_H, p.skyPine)
    sun(p, 310f, 58f, 42f, 29f, 18f, 0.25f, 0.45f)
    cloud(p, 36f, 28f, 90f, 27f); cloud(p, 196f, 20f, 56f, 17f)
    bird(p, 150f, 52f, 16f, 6f); bird(p, 176f, 64f, 12f, 5f)
    fill(
        polygon(0f, 130f, 50f, 92f, 85f, 112f, 140f, 70f, 185f, 108f, 230f, 84f, 290f, 118f, 340f, 96f,
            400f, 124f, 400f, 220f, 0f, 220f), p.farRange,
    )
    fill(
        polygon(140f, 70f, 185f, 108f, 160f, 112f, 150f, 94f)
            .sub(230f, 84f, 290f, 118f, 258f, 118f, 240f, 100f)
            .sub(50f, 92f, 85f, 112f, 64f, 114f), p.farShade,
    )
    fill(
        Path().apply {
            moveTo(0f, 150f); quadraticTo(80f, 118f, 160f, 140f)
            quadraticTo(240f, 162f, 320f, 132f); quadraticTo(400f, 102f, 400f, 140f)
            lineTo(400f, 220f); lineTo(0f, 220f); close()
        }, p.middleGround,
    )
    for ((x, y, w, h) in listOf(
        listOf(8f, 106f, 18f, 36f), listOf(26f, 100f, 20f, 40f), listOf(46f, 98f, 18f, 36f),
        listOf(112f, 102f, 20f, 40f), listOf(132f, 106f, 18f, 36f), listOf(196f, 108f, 18f, 36f),
        listOf(216f, 104f, 20f, 40f), listOf(238f, 102f, 18f, 36f), listOf(372f, 100f, 20f, 40f),
    )) pine(p, x, y, w, h, p.pineFar)
    fill(
        Path().apply {
            moveTo(0f, 176f); quadraticTo(110f, 148f, 220f, 170f); quadraticTo(330f, 192f, 400f, 160f)
            lineTo(400f, 220f); lineTo(0f, 220f); close()
        }, p.ground,
    )
    fill(
        Path().apply {
            moveTo(0f, 206f); quadraticTo(200f, 192f, 400f, 208f); lineTo(400f, 220f); lineTo(0f, 220f); close()
        }, p.groundDeep,
    )
    fill(
        Path().apply {
            moveTo(146f, 220f)
            cubicTo(180f, 196f, 238f, 198f, 226f, 180f)
            cubicTo(218f, 168f, 196f, 170f, 204f, 158f)
            lineTo(210f, 158f)
            cubicTo(205f, 170f, 234f, 168f, 244f, 180f)
            cubicTo(258f, 200f, 222f, 204f, 222f, 220f)
            close()
        }, p.path,
    )
    pine(p, 246f, 124f, 36f, 72f, p.pineMid); pine(p, 124f, 130f, 30f, 60f, p.pineMid)
    pine(p, 14f, 92f, 58f, 116f, p.pineNear); pine(p, 284f, 84f, 64f, 128f, p.pineNear)
    pine(p, 62f, 118f, 44f, 88f, p.pineDeep); pine(p, 338f, 114f, 48f, 96f, p.pineDeep)
    rect(263f, 188f, 3f, 16f, p.trunk)
    drawRoundRect(p.accent, Offset(258f, 186f), Size(13f, 7f), CornerRadius(1f, 1f))
    tuft(116f, 200f, p.middleGround); tuft(186f, 208f, p.middleGround); tuft(300f, 212f, p.middleGround)
}

// ---------------------------------------------------------------------------
// Scene: glasshouse
// ---------------------------------------------------------------------------

private fun DrawScope.drawGlasshouseScene(p: ArtPalette) {
    rect(0f, 0f, ART_W, ART_H, p.skyGlasshouse)
    sun(p, 78f, 54f, 40f, 27f, 17f, 0.25f, 0.45f)
    cloud(p, 250f, 26f, 84f, 25f); cloud(p, 150f, 18f, 50f, 15f)
    bird(p, 320f, 70f, 16f, 6f)
    fill(
        Path().apply {
            moveTo(0f, 128f); quadraticTo(100f, 96f, 200f, 120f); quadraticTo(300f, 144f, 400f, 110f)
            lineTo(400f, 220f); lineTo(0f, 220f); close()
        }, p.farRange,
    )
    fill(
        Path().apply {
            moveTo(0f, 146f); quadraticTo(120f, 126f, 240f, 142f); quadraticTo(360f, 158f, 400f, 136f)
            lineTo(400f, 220f); lineTo(0f, 220f); close()
        }, p.middleGround,
    )
    rect(98f, 128f, 4f, 30f, p.trunk); rect(296f, 128f, 4f, 30f, p.trunk)
    rect(330f, 134f, 3f, 24f, p.trunk); rect(60f, 136f, 3f, 22f, p.trunk)
    disc(100f, 114f, 22f, p.foliageMid); disc(92f, 106f, 10f, p.foliageLight)
    disc(298f, 112f, 24f, p.foliageMid); disc(290f, 103f, 11f, p.foliageLight)
    disc(332f, 126f, 15f, p.foliageDeep); disc(61f, 128f, 14f, p.foliageDeep)
    fill(
        Path().apply {
            moveTo(0f, 162f); quadraticTo(200f, 152f, 400f, 162f); lineTo(400f, 220f); lineTo(0f, 220f); close()
        }, p.lawn,
    )
    // Glasshouse: dome, apex, body, inner plants, ribs, outline, plinth, door.
    fill(Path().apply { moveTo(126f, 108f); quadraticTo(200f, 50f, 274f, 108f); close() }, p.glass)
    val apex = polygon(188f, 64f, 200f, 52f, 212f, 64f)
    fill(apex, p.glass); line(apex, p.glassFrame, 2f, join = StrokeJoin.Round)
    rect(130f, 108f, 140f, 44f, p.glass)
    disc(146f, 142f, 9f, p.foliageMid.copy(alpha = 0.6f)); disc(166f, 137f, 12f, p.foliageDeep.copy(alpha = 0.55f))
    disc(238f, 138f, 12f, p.foliageMid.copy(alpha = 0.6f)); disc(258f, 143f, 8f, p.foliageDeep.copy(alpha = 0.55f))
    line(
        Path().apply {
            moveTo(178f, 150f); quadraticTo(172f, 128f, 182f, 120f)
            moveTo(224f, 150f); quadraticTo(232f, 130f, 222f, 118f)
        }, p.foliageDeep.copy(alpha = 0.6f), 3f,
    )
    line(segments(150f, 108f, 150f, 152f, 170f, 108f, 170f, 152f, 230f, 108f, 230f, 152f,
        250f, 108f, 250f, 152f, 130f, 124f, 270f, 124f), p.glassFrame, 1.5f)
    line(
        Path().apply {
            moveTo(150f, 108f); quadraticTo(160f, 84f, 180f, 70f)
            moveTo(250f, 108f); quadraticTo(240f, 84f, 220f, 70f)
            moveTo(175f, 108f); quadraticTo(180f, 84f, 192f, 68f)
            moveTo(225f, 108f); quadraticTo(220f, 84f, 208f, 68f)
            moveTo(200f, 108f); lineTo(200f, 64f)
        }, p.glassFrame, 1.5f,
    )
    line(Path().apply { moveTo(126f, 108f); quadraticTo(200f, 50f, 274f, 108f) }, p.glassFrame, 2.5f)
    line(polygon(130f, 108f, 270f, 108f, 270f, 152f, 130f, 152f), p.glassFrame, 2.5f)
    rect(126f, 150f, 148f, 12f, p.stone)
    line(segments(126f, 156f, 274f, 156f, 150f, 150f, 150f, 156f, 186f, 150f, 186f, 156f,
        222f, 150f, 222f, 156f, 258f, 150f, 258f, 156f, 168f, 156f, 168f, 162f, 240f, 156f, 240f, 162f),
        p.stoneLine, 1f)
    rect(190f, 126f, 20f, 36f, p.flowerLight)
    line(polygon(190f, 126f, 210f, 126f, 210f, 162f, 190f, 162f), p.glassFrame, 2f)
    line(segments(200f, 126f, 200f, 162f), p.glassFrame, 1.5f)
    fill(polygon(190f, 162f, 210f, 162f, 252f, 220f, 148f, 220f), p.path)
    oval(84f, 188f, 56f, 13f, p.foliageDeep); oval(316f, 188f, 56f, 13f, p.foliageDeep)
    for ((x, y) in listOf(48f to 186f, 76f to 182f, 108f to 190f, 284f to 184f, 318f to 192f, 350f to 186f))
        disc(x, y, 3f, p.accent)
    for ((x, y) in listOf(62f to 192f, 92f to 186f, 124f to 184f, 300f to 188f, 334f to 183f, 362f to 191f))
        disc(x, y, 3f, p.flowerWarm)
    for ((x, y) in listOf(38f to 191f, 100f to 194f, 270f to 190f, 340f to 194f))
        disc(x, y, 2.5f, p.flowerLight)
    rect(156f, 170f, 3f, 14f, p.trunk); rect(241f, 170f, 3f, 14f, p.trunk)
    disc(157.5f, 164f, 10f, p.pineMid); disc(242.5f, 164f, 10f, p.pineMid)
    fill(polygon(150f, 184f, 165f, 184f, 162f, 194f, 153f, 194f).sub(235f, 184f, 250f, 184f, 247f, 194f, 238f, 194f), p.accent)
    fill(
        Path().apply {
            moveTo(0f, 208f); quadraticTo(70f, 198f, 148f, 210f); lineTo(148f, 220f); lineTo(0f, 220f); close()
            moveTo(252f, 210f); quadraticTo(330f, 198f, 400f, 208f); lineTo(400f, 220f); lineTo(252f, 220f); close()
        }, p.ground,
    )
}

// ---------------------------------------------------------------------------
// Scene: canal
// ---------------------------------------------------------------------------

private fun DrawScope.drawCanalScene(p: ArtPalette) {
    rect(0f, 0f, ART_W, ART_H, p.skyCanal)
    sun(p, 300f, 50f, 38f, 25f, 16f, 0.35f, 0.6f)
    cloud(p, 60f, 24f, 96f, 29f); cloud(p, 200f, 60f, 50f, 15f)
    bird(p, 170f, 40f, 16f, 6f); bird(p, 192f, 50f, 12f, 5f)
    fill(
        Path().apply {
            moveTo(0f, 112f)
            quadraticTo(20f, 96f, 40f, 108f); quadraticTo(60f, 90f, 85f, 106f)
            quadraticTo(110f, 92f, 130f, 108f); quadraticTo(160f, 94f, 185f, 108f)
            quadraticTo(215f, 96f, 240f, 108f); quadraticTo(270f, 92f, 300f, 108f)
            quadraticTo(330f, 96f, 360f, 108f); quadraticTo(385f, 98f, 400f, 108f)
            lineTo(400f, 140f); lineTo(0f, 140f); close()
        }, p.farShade,
    )
    rect(0f, 120f, ART_W, 100f, p.middleGround)
    fill(
        Path().apply {
            moveTo(0f, 150f); quadraticTo(60f, 140f, 124f, 150f); lineTo(60f, 220f); lineTo(0f, 220f); close()
        }, p.foliageMid,
    )
    fill(polygon(184f, 122f, 216f, 122f, 332f, 220f, 68f, 220f), p.water)
    fill(polygon(184f, 122f, 191f, 122f, 112f, 220f, 68f, 220f), p.waterDeep)
    fill(
        Path().apply { moveTo(174f, 124f); quadraticTo(200f, 146f, 226f, 124f); close() },
        p.waterDeep.copy(alpha = 0.55f),
    )
    fill(
        Path().apply {
            moveTo(154f, 126f); lineTo(154f, 114f); quadraticTo(200f, 94f, 246f, 114f)
            lineTo(246f, 126f); lineTo(226f, 126f); quadraticTo(200f, 104f, 174f, 126f); close()
        }, p.stone,
    )
    line(Path().apply { moveTo(154f, 114f); quadraticTo(200f, 94f, 246f, 114f) }, p.stoneLine, 2.5f)
    line(segments(166f, 113f, 166f, 119f, 182f, 108f, 182f, 113f, 200f, 106f, 200f, 111f,
        218f, 108f, 218f, 113f, 234f, 113f, 234f, 119f), p.stoneLine, 1.2f)
    fill(polygon(222f, 124f, 234f, 124f, 400f, 196f, 400f, 220f, 346f, 220f), p.path)
    line(segments(192f, 140f, 208f, 140f, 176f, 158f, 198f, 158f, 214f, 168f, 240f, 168f,
        150f, 190f, 180f, 190f, 226f, 198f, 260f, 198f, 176f, 210f, 200f, 210f),
        p.cloud.copy(alpha = p.rippleAlpha), 1.6f, StrokeCap.Round)
    val hull = Path().apply { moveTo(146f, 178f); quadraticTo(172f, 190f, 200f, 178f) }
    fill(
        Path().apply {
            moveTo(146f, 178f); quadraticTo(172f, 190f, 200f, 178f); lineTo(195f, 186f)
            quadraticTo(172f, 194f, 152f, 186f); close()
        }, p.accent,
    )
    drawRoundRect(p.flowerLight, Offset(164f, 172f), Size(18f, 8f), CornerRadius(1.5f, 1.5f))
    line(hull, p.trunk, 1.5f)
    // Willow.
    line(Path().apply { moveTo(72f, 176f); quadraticTo(74f, 146f, 84f, 122f) }, p.trunk, 6f, StrokeCap.Round)
    line(
        Path().apply {
            moveTo(56f, 110f); quadraticTo(48f, 140f, 54f, 162f)
            moveTo(70f, 120f); quadraticTo(64f, 150f, 70f, 170f)
            moveTo(98f, 122f); quadraticTo(104f, 150f, 98f, 168f)
            moveTo(112f, 110f); quadraticTo(120f, 136f, 114f, 158f)
        }, p.foliageDeep, 7f, StrokeCap.Round,
    )
    disc(84f, 106f, 34f, p.foliageMid); disc(74f, 96f, 16f, p.foliageLight)
    line(
        Path().apply {
            moveTo(62f, 124f); quadraticTo(58f, 146f, 62f, 158f)
            moveTo(84f, 132f); quadraticTo(84f, 152f, 82f, 164f)
            moveTo(106f, 124f); quadraticTo(110f, 144f, 106f, 156f)
        }, p.pineFar, 5f, StrokeCap.Round,
    )
    // Poplars.
    rect(328f, 108f, 3f, 26f, p.trunk); rect(354f, 112f, 3f, 24f, p.trunk); rect(378f, 118f, 3f, 22f, p.trunk)
    oval(329.5f, 92f, 12f, 30f, p.foliageDeep); oval(355.5f, 100f, 10f, 25f, p.foliageMid)
    oval(379.5f, 106f, 9f, 22f, p.foliageDeep)
    for ((x, y) in listOf(286f to 138f, 310f to 146f, 346f to 152f)) disc(x, y, 2.5f, p.accent)
    for ((x, y) in listOf(298f to 142f, 330f to 148f, 366f to 158f)) disc(x, y, 2.5f, p.flowerLight)
    // Reeds.
    line(segments(96f, 220f, 94f, 194f, 104f, 220f, 107f, 190f, 112f, 220f, 111f, 198f,
        40f, 220f, 42f, 196f, 30f, 220f, 27f, 200f), p.ground, 2f, StrokeCap.Round)
    oval(94f, 191f, 2.5f, 6f, p.trunk); oval(107f, 187f, 2.5f, 6f, p.trunk); oval(42f, 193f, 2.5f, 6f, p.trunk)
}

// ---------------------------------------------------------------------------
// Scene: ridge
// ---------------------------------------------------------------------------

private fun DrawScope.drawRidgeScene(p: ArtPalette) {
    rect(0f, 0f, ART_W, ART_H, p.skyRidge)
    rect(0f, 92f, ART_W, 60f, p.skyHaze)
    sun(p, 118f, 68f, 46f, 32f, 20f, 0.25f, 0.45f)
    cloud(p, 290f, 22f, 84f, 25f); cloud(p, 16f, 22f, 52f, 16f)
    bird(p, 196f, 40f, 16f, 6f); bird(p, 218f, 30f, 12f, 5f); bird(p, 330f, 64f, 12f, 5f)
    fill(
        polygon(0f, 120f, 40f, 96f, 80f, 112f, 130f, 66f, 170f, 100f, 210f, 78f, 262f, 40f, 310f, 92f,
            350f, 74f, 400f, 104f, 400f, 220f, 0f, 220f), p.warmRange1,
    )
    fill(
        polygon(262f, 40f, 310f, 92f, 282f, 98f, 266f, 70f)
            .sub(130f, 66f, 170f, 100f, 146f, 104f, 134f, 84f)
            .sub(350f, 74f, 400f, 104f, 372f, 106f, 354f, 90f), p.warmShade1,
    )
    fill(
        polygon(262f, 40f, 278f, 57f, 270f, 54f, 263f, 63f, 255f, 53f, 246f, 52f)
            .sub(130f, 66f, 140f, 75f, 134f, 73f, 129f, 80f, 125f, 73f, 120f, 75f), p.snow,
    )
    fill(
        polygon(0f, 150f, 60f, 118f, 110f, 140f, 170f, 104f, 230f, 138f, 290f, 112f, 350f, 136f, 400f, 118f,
            400f, 220f, 0f, 220f), p.warmRange2,
    )
    fill(
        polygon(170f, 104f, 230f, 138f, 196f, 142f, 176f, 122f)
            .sub(290f, 112f, 350f, 136f, 316f, 140f, 296f, 124f)
            .sub(60f, 118f, 110f, 140f, 82f, 144f, 66f, 130f), p.warmShade2,
    )
    fill(
        Path().apply {
            moveTo(0f, 176f); quadraticTo(60f, 150f, 120f, 164f); quadraticTo(180f, 178f, 250f, 150f)
            quadraticTo(320f, 122f, 400f, 160f); lineTo(400f, 220f); lineTo(0f, 220f); close()
        }, p.distantGround,
    )
    fill(polygon(0f, 220f, 0f, 196f, 120f, 180f, 250f, 150f, 300f, 158f, 400f, 190f, 400f, 220f), p.ground)
    fill(polygon(250f, 150f, 300f, 158f, 400f, 190f, 400f, 220f, 290f, 220f), p.groundDeep)
    line(
        polyline(56f, 220f, 132f, 200f, 88f, 192f, 192f, 175f, 160f, 169f, 246f, 152f),
        p.path, 3.5f, StrokeCap.Round, StrokeJoin.Round,
    )
    oval(252f, 148f, 8f, 3.5f, p.cairnDark); oval(252f, 143f, 6f, 3f, p.cairnLight)
    oval(252f, 138.5f, 4f, 2.5f, p.cairnDark); oval(252f, 135f, 2.5f, 2f, p.cairnLight)
    pine(p, 316f, 138f, 28f, 56f, p.pineDeep); pine(p, 344f, 156f, 24f, 48f, p.pineDeep)
    pine(p, 14f, 158f, 26f, 52f, p.pineDeep)
    fill(
        polygon(150f, 206f, 160f, 198f, 172f, 202f, 176f, 210f)
            .sub(216f, 188f, 224f, 182f, 234f, 185f, 236f, 191f)
            .sub(374f, 208f, 382f, 201f, 392f, 205f, 392f, 210f), p.rock,
    )
    tuft(100f, 212f, p.distantGround); tuft(270f, 200f, p.distantGround)
}
