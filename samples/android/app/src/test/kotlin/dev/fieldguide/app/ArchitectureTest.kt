package dev.fieldguide.app

import com.lemonappdev.konsist.api.Konsist
import com.lemonappdev.konsist.api.verify.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ArchitectureTest {
    @Test
    fun `features SHOULD NOT import any implementation`() {
        val features = Konsist.scopeFromProduction().files
            .filter { it.moduleName.startsWith("feature-") }
        assertTrue("Feature scope must not be empty", features.isNotEmpty())

        features.assertFalse { file ->
            file.imports.any { dependency ->
                ".impl." in dependency.name
            }
        }
    }
}
