package dev.fieldguide.catalog.impl

import dev.fieldguide.catalog.api.*
import org.junit.Assert.assertEquals
import org.junit.Test

/** Pure query examples: no mapper, repository, storage or UI is involved. */
class QueryWalksTeachingTest {
    private fun walk(minutes: Int) = Walk(
        id = "walk-$minutes",
        title = "$minutes minute walk",
        description = "An open route",
        durationMinutes = minutes,
        distanceMetres = 1000,
        terrain = Terrain.Garden,
        availability = Availability.Open,
        artKey = ArtKey.Glasshouse,
    )

    @Test
    fun `run WHEN budget is 60 SHOULD keep only 60`() {
        val oneHour = walk(minutes = 60)
        val tooLong = walk(minutes = 61)
        val sut = QueryWalks()

        val visible = sut.run(listOf(oneHour, tooLong), "", 60)

        assertEquals(listOf(oneHour), visible)
    }
}
