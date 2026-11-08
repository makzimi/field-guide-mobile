package dev.fieldguide.catalog.impl

import com.google.gson.JsonElement
import com.google.gson.JsonObject
import com.google.gson.JsonParser
import dev.fieldguide.catalog.api.*

/** Maps one complete walks array. Any bad row rejects the whole snapshot. */
class CatalogMapper {
    fun mapWalks(json: String): List<Walk> {
        val array = try { JsonParser.parseString(json).asJsonArray } catch (e: RuntimeException) {
            throw IllegalArgumentException("Invalid walks array", e)
        }
        val ids = mutableSetOf<String>()
        return array.map { element ->
            val row = try { element.asJsonObject } catch (e: RuntimeException) {
                throw IllegalArgumentException("Invalid walk row", e)
            }
            val dto = WalkDto(
                row.text("id"), row.text("title"), row.text("description"),
                row.positiveInt("durationMinutes"), row.positiveInt("distanceMetres"),
                row.text("terrain"), row.text("availability"), row.text("artKey"),
            )
            require(ids.add(dto.id)) { "Duplicate walk ID" }
            dto.toDomain()
        }
    }

    private fun JsonObject.text(key: String): String {
        val value = get(key)
        require(value != null && value.isJsonPrimitive && value.asJsonPrimitive.isString) { "Invalid $key" }
        return value.asString
    }

    private fun JsonObject.positiveInt(key: String): Int {
        val value: JsonElement? = get(key)
        require(value != null && value.isJsonPrimitive && value.asJsonPrimitive.isNumber) { "Invalid $key" }
        val raw = value.asString
        require(raw.matches(Regex("[0-9]+"))) { "Invalid $key" }
        val result = raw.toIntOrNull()
        require(result != null && result > 0) { "Invalid $key" }
        return result
    }

}

/** A parsed source row, kept inside the implementation boundary. */
private data class WalkDto(
    val id: String,
    val title: String,
    val description: String,
    val durationMinutes: Int,
    val distanceMetres: Int,
    val terrain: String,
    val availability: String,
    val artKey: String,
) {
    fun toDomain(): Walk {
        require(id.isNotBlank() && title.isNotBlank()) { "Blank ID or title" }
        return Walk(
            id, title, description, durationMinutes, distanceMetres,
            terrainMap[terrain] ?: throw IllegalArgumentException("Unknown terrain"),
            availabilityMap[availability] ?: throw IllegalArgumentException("Unknown availability"),
            artMap[artKey] ?: throw IllegalArgumentException("Unknown artKey"),
        )
    }

    companion object {
        private val terrainMap = mapOf("woodland" to Terrain.Woodland, "garden" to Terrain.Garden,
            "waterside" to Terrain.Waterside, "ridge" to Terrain.Ridge)
        private val availabilityMap = mapOf("open" to Availability.Open, "closed" to Availability.Closed)
        private val artMap = mapOf("pine" to ArtKey.Pine, "glasshouse" to ArtKey.Glasshouse,
            "canal" to ArtKey.Canal, "ridge" to ArtKey.Ridge)
    }
}
