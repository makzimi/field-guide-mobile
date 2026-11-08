package dev.fieldguide.app

import androidx.test.platform.app.InstrumentationRegistry
import org.junit.runner.Description
import org.junit.runner.Result
import org.junit.runner.notification.Failure
import org.junit.runner.notification.RunListener
import java.io.File

/** Records actual runner callbacks, not inferred test results. */
class EvidenceXmlListener : RunListener() {
    private data class Case(val description: Description, val start: Long,
        var elapsed: Long = 0, var failure: Failure? = null)
    private val cases = mutableListOf<Case>()
    override fun testStarted(description: Description) { cases += Case(description, System.nanoTime()) }
    override fun testFailure(failure: Failure) { cases.lastOrNull()?.failure = failure }
    override fun testFinished(description: Description) {
        cases.lastOrNull()?.let { it.elapsed = System.nanoTime() - it.start }
    }
    override fun testRunFinished(result: Result) {
        val args = InstrumentationRegistry.getArguments()
        val target = InstrumentationRegistry.getInstrumentation().targetContext
        val name = args.getString("captureSet") ?: "light-1.0"
        val method = cases.firstOrNull()?.description?.methodName ?: "run"
        val file = File(target.filesDir, "device-evidence/junit/$name-$method.xml")
        file.parentFile!!.mkdirs()
        file.outputStream().use { output ->
            val xml = android.util.Xml.newSerializer(); xml.setOutput(output, "UTF-8")
            xml.startDocument("UTF-8", true)
            xml.startTag(null, "testsuite").attribute(null, "name", "DeviceEvidenceTest")
                .attribute(null, "tests", result.runCount.toString())
                .attribute(null, "failures", result.failureCount.toString())
                .attribute(null, "errors", "0").attribute(null, "skipped", result.ignoreCount.toString())
                .attribute(null, "time", (result.runTime / 1000.0).toString())
            cases.forEach { case ->
                xml.startTag(null, "testcase").attribute(null, "name", case.description.methodName)
                    .attribute(null, "classname", case.description.className)
                    .attribute(null, "time", (case.elapsed / 1e9).toString())
                case.failure?.let { failure ->
                    xml.startTag(null, "failure").attribute(null, "message", failure.message ?: "Failure")
                        .text(failure.trace).endTag(null, "failure")
                }
                xml.endTag(null, "testcase")
            }
            xml.endTag(null, "testsuite"); xml.endDocument()
        }
    }
}
