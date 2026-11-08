package dev.fieldguide.feature.catalog

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel

/** Activity-scoped lifecycle adapter. The state holder has no Android dependency. */
class CatalogViewModel(private val feature: CatalogFeature) : ViewModel() {
    var view by mutableStateOf(feature.view)
        private set

    init {
        feature.observe { view = it }
        feature.start()
    }

    fun dispatch(action: FeatureAction) = feature.dispatch(action)
    fun onForeground() = feature.dispatch(FeatureAction.Foreground)

    override fun onCleared() {
        feature.close()
        super.onCleared()
    }
}
