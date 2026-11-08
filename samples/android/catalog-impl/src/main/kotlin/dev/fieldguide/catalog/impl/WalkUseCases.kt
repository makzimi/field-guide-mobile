package dev.fieldguide.catalog.impl

import dev.fieldguide.catalog.api.*
import java.util.Locale
import java.util.concurrent.CompletableFuture

class QueryWalks : WalkQuery {
    override fun normalize(value: String): String = value.trim().replace(Regex("\\s+"), " ").lowercase(Locale.ROOT)

    override fun run(walks: List<Walk>, query: String, budgetMinutes: Int): List<Walk> {
        require(budgetMinutes in setOf(15, 30, 60, 90)) { "Unsupported budget" }
        val needle = normalize(query)
        return walks.asSequence()
            .filter { it.durationMinutes <= budgetMinutes && normalize(it.title).contains(needle) }
            .sortedWith(compareBy<Walk> { it.durationMinutes }.thenBy { normalize(it.title) }.thenBy { it.id })
            .toList()
    }
}

class AddBookmark(private val repository: WalkRepository) : AddBookmarkUseCase {
    override fun run(id: String): CompletableFuture<BookmarkResult> = repository.addBookmark(id)
}

class RemoveBookmark(private val repository: WalkRepository) : RemoveBookmarkUseCase {
    override fun run(id: String): CompletableFuture<BookmarkResult> = repository.removeBookmark(id)
}
