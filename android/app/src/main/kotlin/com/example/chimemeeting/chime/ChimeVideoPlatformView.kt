package com.example.chimemeeting.chime

import android.content.Context
import android.view.View
import com.amazonaws.services.chime.sdk.meetings.audiovideo.video.DefaultVideoRenderView
import io.flutter.plugin.platform.PlatformView

/** Flutter-owned native Chime rendering surface with no meeting business logic. */
internal class ChimeVideoPlatformView(
    context: Context,
    private val role: ChimeVideoRole,
    private val controller: ChimeSessionController,
    private val onDisposed: (ChimeVideoPlatformView) -> Unit,
) : PlatformView {
    private var disposed = false
    private val renderView = DefaultVideoRenderView(context).also { view ->
        controller.attachVideoView(role, view)
    }

    /** Returns the Chime render surface embedded by Flutter. */
    override fun getView(): View = renderView

    /** Detaches the video tile and releases the native render surface exactly once. */
    override fun dispose() {
        if (disposed) return
        disposed = true
        controller.detachVideoView(role, renderView)
        renderView.release()
        onDisposed(this)
    }
}
