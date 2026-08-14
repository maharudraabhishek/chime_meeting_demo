package com.example.chimemeeting.chime

import android.content.Context
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/** Creates local or remote native render surfaces from validated view arguments. */
internal class ChimeVideoViewFactory(
    private val controller: ChimeSessionController,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    private val activeViews = mutableSetOf<ChimeVideoPlatformView>()

    /** Creates and tracks one validated local or remote native render view. */
    @Synchronized
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val platformView = ChimeVideoPlatformView(
            context,
            ChimeVideoRole.fromCreationArguments(args),
            controller,
            ::forgetView,
        )
        activeViews.add(platformView)
        return platformView
    }

    /** Releases any views still retained when the Flutter engine is torn down. */
    @Synchronized
    fun disposeAll() {
        activeViews.toList().forEach(ChimeVideoPlatformView::dispose)
        activeViews.clear()
    }

    /** Removes a PlatformView after it has completed its own cleanup. */
    @Synchronized
    private fun forgetView(view: ChimeVideoPlatformView) {
        activeViews.remove(view)
    }
}
