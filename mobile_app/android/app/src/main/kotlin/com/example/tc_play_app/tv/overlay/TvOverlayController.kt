package com.example.tc_play_app.tv.overlay

import android.app.Activity
import android.graphics.Color
import android.util.Log
import android.view.Gravity
import android.view.TextureView
import android.view.View
import android.widget.FrameLayout
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory

class TvOverlayController(
    private val activity: Activity
) {

    companion object {
        private const val TAG = "TCPLAY_OVERLAY"
    }

    private var container: FrameLayout? = null
    private var textureView: TextureView? = null
    private var player: ExoPlayer? = null

    private var currentUrl: String? = null

    fun showPlayer(
        url: String,
        x: Int,
        y: Int,
        width: Int,
        height: Int
    ) {
        activity.runOnUiThread {

            val decorView =
                activity.window.decorView as? FrameLayout

            if (decorView == null) {
                Log.e(
                    TAG,
                    "No se pudo obtener decorView como FrameLayout"
                )
                return@runOnUiThread
            }

            ensurePlayerCreated(decorView)

            val params = FrameLayout.LayoutParams(
                width,
                height
            ).apply {
                gravity = Gravity.TOP or Gravity.START
                leftMargin = x
                topMargin = y
            }

            container?.layoutParams = params
            container?.visibility = View.VISIBLE

            Log.i(
                TAG,
                "Player mostrado x=$x y=$y width=$width height=$height"
            )

            if (currentUrl != url) {
                play(url)
            }
        }
    }

    private fun ensurePlayerCreated(
        decorView: FrameLayout
    ) {
        if (container != null &&
            textureView != null &&
            player != null
        ) {
            return
        }

        Log.i(
            TAG,
            "Creando overlay TextureView + ExoPlayer"
        )

        val nativeContainer = FrameLayout(activity).apply {
            setBackgroundColor(Color.BLACK)

            // No queremos que este overlay robe el foco al D-pad.
            isFocusable = false
            isFocusableInTouchMode = false
            isClickable = false
        }

        val nativeTextureView = TextureView(activity).apply {
            isOpaque = true
            isFocusable = false
            isClickable = false
        }

        nativeContainer.addView(
            nativeTextureView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        )

        decorView.addView(nativeContainer)

        val httpFactory =
            DefaultHttpDataSource.Factory()
                .setUserAgent(
                    "Mozilla/5.0 (Android TV) " +
                        "AppleWebKit/537.36 TCPlay/2.0"
                )
                .setDefaultRequestProperties(
                    mapOf(
                        "Accept" to "*/*",
                        "Connection" to "keep-alive"
                    )
                )

        val exoPlayer =
            ExoPlayer.Builder(activity)
                .setMediaSourceFactory(
                    DefaultMediaSourceFactory(
                        httpFactory
                    )
                )
                .build()

        exoPlayer.setVideoTextureView(
            nativeTextureView
        )

        exoPlayer.addListener(
            object : Player.Listener {

                override fun onPlaybackStateChanged(
                    playbackState: Int
                ) {
                    val state = when (playbackState) {
                        Player.STATE_IDLE -> "IDLE"
                        Player.STATE_BUFFERING ->
                            "BUFFERING"

                        Player.STATE_READY -> "READY"
                        Player.STATE_ENDED -> "ENDED"
                        else -> "UNKNOWN"
                    }

                    Log.i(
                        TAG,
                        "Estado=$state " +
                            "playWhenReady=" +
                            exoPlayer.playWhenReady
                    )
                }

                override fun onVideoSizeChanged(
                    videoSize: VideoSize
                ) {
                    Log.i(
                        TAG,
                        "VideoSize=" +
                            "${videoSize.width}x" +
                            "${videoSize.height}"
                    )
                }

                override fun onRenderedFirstFrame() {
                    Log.i(
                        TAG,
                        "***** PRIMER FRAME OVERLAY NATIVO *****"
                    )
                }

                override fun onPlayerError(
                    error: PlaybackException
                ) {
                    Log.e(
                        TAG,
                        "ERROR=${error.errorCodeName}",
                        error
                    )
                }
            }
        )

        container = nativeContainer
        textureView = nativeTextureView
        player = exoPlayer

        Log.i(
            TAG,
            "Overlay TextureView + ExoPlayer creado"
        )
    }

    private fun play(url: String) {
        val exoPlayer = player ?: return

        Log.i(
            TAG,
            "Reproduciendo URL en overlay nativo"
        )

        currentUrl = url

        val mediaItem =
            MediaItem.Builder()
                .setUri(url)
                .setMimeType(
                    MimeTypes.APPLICATION_M3U8
                )
                .build()

        exoPlayer.setMediaItem(mediaItem)
        exoPlayer.prepare()
        exoPlayer.playWhenReady = true
    }

    fun hide() {
        activity.runOnUiThread {
            container?.visibility = View.GONE

            player?.pause()

            Log.i(
                TAG,
                "Overlay ocultado"
            )
        }
    }

    fun dispose() {
        activity.runOnUiThread {

            Log.i(
                TAG,
                "Liberando overlay nativo"
            )

            val currentPlayer = player
            val currentTexture = textureView

            if (
                currentPlayer != null &&
                currentTexture != null
            ) {
                currentPlayer.clearVideoTextureView(
                    currentTexture
                )
            }

            currentPlayer?.release()

            container?.let { view ->
                (view.parent as? FrameLayout)
                    ?.removeView(view)
            }

            player = null
            textureView = null
            container = null
            currentUrl = null
        }
    }
}