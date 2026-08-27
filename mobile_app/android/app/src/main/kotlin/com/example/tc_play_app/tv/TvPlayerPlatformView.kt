package com.example.tc_play_app.tv

import android.content.Context
import android.graphics.Color
import android.util.Log
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
import io.flutter.plugin.platform.PlatformView

class TvPlayerPlatformView(
    context: Context,
    id: Int,
    creationParams: Map<String, Any>?
) : PlatformView {

    companion object {
        private const val TAG = "TCPLAY_EXOPLAYER"
    }

    private val container: FrameLayout
    private val textureView: TextureView
    private val player: ExoPlayer

    init {
        Log.i(TAG, "========================================")
        Log.i(TAG, "Creando TvPlayerPlatformView TEXTUREVIEW")
        Log.i(TAG, "id=$id")
        Log.i(TAG, "========================================")

        container = FrameLayout(context).apply {
            setBackgroundColor(Color.BLACK)
        }

        textureView = TextureView(context).apply {
            isOpaque = true
        }

        container.addView(
            textureView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        )

        val httpFactory = DefaultHttpDataSource.Factory()
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

        player = ExoPlayer.Builder(context)
            .setMediaSourceFactory(
                DefaultMediaSourceFactory(httpFactory)
            )
            .build()

        //
        // CAMBIO CLAVE:
        // Ya no usamos SurfaceView.
        //
        player.setVideoTextureView(textureView)

        Log.i(TAG, "TextureView conectado a ExoPlayer")

        player.addListener(
            object : Player.Listener {

                override fun onPlaybackStateChanged(
                    playbackState: Int
                ) {
                    val state = when (playbackState) {
                        Player.STATE_IDLE -> "IDLE"
                        Player.STATE_BUFFERING -> "BUFFERING"
                        Player.STATE_READY -> "READY"
                        Player.STATE_ENDED -> "ENDED"
                        else -> "UNKNOWN"
                    }

                    Log.i(
                        TAG,
                        "Estado=$state " +
                            "playWhenReady=${player.playWhenReady}"
                    )
                }

                override fun onVideoSizeChanged(
                    videoSize: VideoSize
                ) {
                    Log.i(
                        TAG,
                        "VideoSize=${videoSize.width}x${videoSize.height}"
                    )
                }

                override fun onRenderedFirstFrame() {
                    Log.i(
                        TAG,
                        "***** PRIMER FRAME TEXTUREVIEW EMBEBIDO *****"
                    )
                }

                override fun onPlayerError(
                    error: PlaybackException
                ) {
                    Log.e(
                        TAG,
                        "ERROR EXOPLAYER=${error.errorCodeName}",
                        error
                    )
                }
            }
        )

        val url = creationParams?.get("url") as? String

        Log.i(
            TAG,
            "URL recibida=${if (url.isNullOrBlank()) "VACIA" else "OK"}"
        )

        if (!url.isNullOrBlank()) {

            val mediaItem = MediaItem.Builder()
                .setUri(url)
                .setMimeType(MimeTypes.APPLICATION_M3U8)
                .build()

            player.setMediaItem(mediaItem)
            player.prepare()
            player.playWhenReady = true

        } else {

            Log.e(TAG, "URL vacía o nula")
        }
    }

    override fun getView(): View {
        return container
    }

    override fun dispose() {
        Log.i(TAG, "Liberando TvPlayerPlatformView TEXTUREVIEW")

        player.clearVideoTextureView(textureView)
        player.release()
    }
}