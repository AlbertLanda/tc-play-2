package com.example.tc_play_app.tv

import android.graphics.Color
import android.os.Bundle
import android.util.Log
import android.view.TextureView
import android.widget.FrameLayout
import androidx.activity.ComponentActivity
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory

class TvNativeTestActivity : ComponentActivity() {

    companion object {
        private const val TAG = "TCPLAY_NATIVE_TEST"
    }

    private var player: ExoPlayer? = null
    private lateinit var textureView: TextureView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        Log.i(TAG, "========================================")
        Log.i(TAG, "ACTIVIDAD NATIVA TEXTUREVIEW INICIADA")
        Log.i(TAG, "========================================")

        val url = intent.getStringExtra("url")

        Log.i(
            TAG,
            "URL recibida=${if (url.isNullOrBlank()) "VACIA" else url}"
        )

        val container = FrameLayout(this).apply {
            setBackgroundColor(Color.BLACK)
        }

        textureView = TextureView(this).apply {
            isOpaque = true
        }

        container.addView(
            textureView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        )

        setContentView(container)

        if (url.isNullOrBlank()) {
            Log.e(TAG, "No se recibió URL")
            return
        }

        val httpFactory = DefaultHttpDataSource.Factory()
            .setUserAgent(
                "Mozilla/5.0 (Android TV) AppleWebKit/537.36 TCPlay/2.0"
            )
            .setDefaultRequestProperties(
                mapOf(
                    "Accept" to "*/*",
                    "Connection" to "keep-alive"
                )
            )

        val exoPlayer = ExoPlayer.Builder(this)
            .setMediaSourceFactory(
                DefaultMediaSourceFactory(httpFactory)
            )
            .build()

        player = exoPlayer

        //
        // PRUEBA CLAVE:
        // Ya NO usamos SurfaceView.
        //
        exoPlayer.setVideoTextureView(textureView)

        Log.i(TAG, "TextureView conectado a ExoPlayer")

        exoPlayer.addListener(
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
                            "playWhenReady=${exoPlayer.playWhenReady}"
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
                        "***** PRIMER FRAME TEXTUREVIEW *****"
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

        val mediaItem = MediaItem.Builder()
            .setUri(url)
            .setMimeType(MimeTypes.APPLICATION_M3U8)
            .build()

        exoPlayer.setMediaItem(mediaItem)
        exoPlayer.prepare()
        exoPlayer.playWhenReady = true
    }

    override fun onDestroy() {
        Log.i(TAG, "Liberando reproductor TextureView")

        player?.clearVideoTextureView(textureView)
        player?.release()
        player = null

        super.onDestroy()
    }
}