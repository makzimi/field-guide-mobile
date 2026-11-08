package dev.fieldguide.catalog.impl

import com.google.gson.JsonObject
import com.google.gson.JsonParser
import com.google.gson.Strictness
import com.google.gson.stream.JsonReader
import java.nio.file.Files
import java.nio.file.Path
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Checks fixture reading only. These assertions never execute sample behavior. */
class SharedContractSmokeTest {
    private val contract = SharedContract.load()

    @Test
    fun readsAllSharedCatalogsAndSeventeenScenarioIds() {
        assertEquals(16, contract.catalogs.size)
        contract.catalogs.forEach { (id, catalog) ->
            assertEquals(id, catalog["fixtureId"].asString)
            assertEquals("catalog", catalog["kind"].asString)
            assertTrue("$id walks must be an array", catalog["walks"].isJsonArray)
        }
        val expectedIds = (1..8).map { "CAT-%02d".format(it) } +
            (1..6).map { "SAVE-%02d".format(it) } + listOf("NAV-01", "CLOCK-01", "VIEW-01")
        assertEquals(expectedIds, contract.scenarios["scenarioIds"].stringList())
        assertEquals(expectedIds, contract.scenarios["scenarios"].asJsonArray.map { it.asJsonObject["id"].asString })
        assertEquals(17, expectedIds.distinct().size)
        println("Fixture-reading smoke: 16 shared catalogs, 17 shared scenario IDs; source=${contract.directory}")
    }

    @Test
    fun readsInclusiveSixtyAndExclusiveSixtyOneMinuteInputsAndOracle() {
        val catalog = contract.catalogs.getValue("catalog-boundary")
        val durations = catalog["walks"].asJsonArray.associate {
            it.asJsonObject["id"].asString to it.asJsonObject["durationMinutes"].asInt
        }
        assertEquals(mapOf("exact-hour" to 60, "over-hour" to 61), durations)
        val scenario = contract.scenario("CAT-02")
        assertEquals("catalog-boundary", scenario["initial"].asJsonObject["catalogFixture"].asString)
        assertEquals(60, scenario["initial"].asJsonObject["budgetMinutes"].asInt)
        val sixty = scenario.step("sixty")["expect"].asJsonObject
        assertEquals(listOf("exact-hour"), sixty["listIds"].stringList())
        assertEquals("exact-hour", sixty["includedId"].asString)
        assertEquals("over-hour", sixty["excludedId"].asString)
        val ninety = scenario.step("ninety")
        assertEquals(90, ninety["minutes"].asInt)
        assertEquals(listOf("exact-hour", "over-hour"), ninety["expect"].asJsonObject["listIds"].stringList())
    }

    @Test
    fun readsExactFreshAndStaleClockInputsAndOracle() {
        assertEquals(300000L, contract.scenarios["ttlMs"].asLong)
        val scenario = contract.scenario("CLOCK-01")
        assertEquals(1000000L, scenario["initial"].asJsonObject["fetchedAtMs"].asLong)
        val before = scenario.step("beforeTtl")
        assertEquals(1299999L, before["clockMs"].asLong)
        val fresh = before["expect"].asJsonObject
        assertEquals(299999L, fresh["ageMs"].asLong)
        assertTrue(fresh["fresh"].asBoolean)
        assertTrue(fresh["addEnabled"].asBoolean)
        assertFalse(fresh["staleWarning"].asBoolean)
        val at = scenario.step("atTtl")
        assertEquals(1300000L, at["clockMs"].asLong)
        val stale = at["expect"].asJsonObject
        assertEquals(300000L, stale["ageMs"].asLong)
        assertFalse(stale["fresh"].asBoolean)
        assertFalse(stale["addEnabled"].asBoolean)
        assertEquals("stale", stale["disabledReason"].asString)
        assertTrue(stale["staleWarning"].asBoolean)
        assertEquals("rejected-stale", scenario.step("useCaseBypass")["expect"].asJsonObject["result"].asString)
    }
}

/** Raw test data, intentionally separate from the future production DTO mapper. */
private data class SharedContract(
    val directory: Path,
    val catalogs: Map<String, JsonObject>,
    val scenarios: JsonObject,
) {
    fun scenario(id: String): JsonObject = scenarios["scenarios"].asJsonArray
        .single { it.asJsonObject["id"].asString == id }.asJsonObject

    companion object {
        fun load(): SharedContract {
            val directory = Path.of(checkNotNull(System.getProperty("fieldGuide.contractDirectory")) {
                "Gradle must pass the shared samples/contract source directory"
            })
            check(Files.isDirectory(directory)) { "Shared contract directory missing: $directory" }
            val catalogs = Files.list(directory).use { files ->
                files.filter { it.fileName.toString().startsWith("catalog-") && it.fileName.toString().endsWith(".json") }
                    .sorted().toList().associate { file ->
                        file.fileName.toString().removeSuffix(".json") to readObject(file)
                    }
            }
            return SharedContract(directory, catalogs, readObject(directory.resolve("scenarios.json")))
        }

        private fun readObject(path: Path): JsonObject = Files.newBufferedReader(path).use { input ->
            JsonReader(input).use { reader ->
                reader.strictness = Strictness.STRICT
                JsonParser.parseReader(reader).asJsonObject
            }
        }
    }
}

private fun com.google.gson.JsonElement.stringList(): List<String> = asJsonArray.map { it.asString }

private fun JsonObject.step(id: String): JsonObject = getAsJsonArray("steps")
    .single { it.asJsonObject["id"].asString == id }.asJsonObject
