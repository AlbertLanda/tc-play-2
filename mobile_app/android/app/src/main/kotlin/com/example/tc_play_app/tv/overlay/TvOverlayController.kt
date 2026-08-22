package com.example.tc_play_app.tv.overlay

import android.app.Activity
import android.graphics.Color
import android.util.Log
import android.view.Gravity
import android.view.SurfaceView
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
import androidx.media3.exoplayer.analytics.AnalyticsListener

class TvOverlayController(
    private val activity: Activity
) {

    companion object {
        private const val TAG = "TCPLAY_OVERLAY"
    }

    private var container: FrameLayout? = null
    private var surfaceView: SurfaceView? = null

    // Ahora el player ya NO es permanente.
    // Cada cambio real de canal genera una sesión nueva.
    private var player: ExoPlayer? = null

    private var currentUrl: String? = null

    // Solo para poder identificar en consola cada sesión.
    private var playerGeneration: Int = 0

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

            ensureOverlayCreated(decorView)

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
                "Overlay mostrado " +
                    "x=$x y=$y width=$width height=$height"
            )

            if (currentUrl == url && player != null) {
                Log.i(
                    TAG,
                    "La URL actual ya está reproduciéndose. Se ignora."
                )
                return@runOnUiThread
            }

            switchChannel(url)
        }
    }

    // ============================================================
    // CREACIÓN DEL OVERLAY VISUAL
    // ============================================================

    private fun ensureOverlayCreated(
        decorView: FrameLayout
    ) {
        if (
            container != null &&
            surfaceView != null
        ) {
            return
        }

        Log.i(
            TAG,
            "Creando overlay visual nativo con SurfaceView"
        )

        val nativeContainer =
            FrameLayout(activity).apply {

                setBackgroundColor(Color.BLACK)

                isFocusable = false
                isFocusableInTouchMode = false
                isClickable = false
            }

        val nativeSurfaceView =
            SurfaceView(activity).apply {

                setZOrderMediaOverlay(true)

                isFocusable = false
                isFocusableInTouchMode = false
                isClickable = false
            }

        nativeContainer.addView(
            nativeSurfaceView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        )

        decorView.addView(nativeContainer)

        container = nativeContainer
        surfaceView = nativeSurfaceView

        Log.i(
            TAG,
            "Overlay SurfaceView creado"
        )
    }

    // ============================================================
    // CAMBIO DE CANAL
    // ============================================================

    private fun switchChannel(
        url: String
    ) {
        val currentSurfaceView =
            surfaceView ?: run {

                Log.e(
                    TAG,
                    "No existe SurfaceView para reproducir."
                )

                return
            }

        Log.i(
            TAG,
            "========================================"
        )

        Log.i(
            TAG,
            "CAMBIO DE CANAL"
        )

        Log.i(
            TAG,
            "Liberando completamente sesión anterior"
        )

        // --------------------------------------------------------
        // 1. MATAMOS COMPLETAMENTE LA SESIÓN ANTERIOR
        // --------------------------------------------------------

        releaseCurrentPlayer()

        // --------------------------------------------------------
        // 2. CREAMOS UNA SESIÓN COMPLETAMENTE NUEVA
        // --------------------------------------------------------

        playerGeneration++

        val generation = playerGeneration

        Log.i(
            TAG,
            "Creando PLAYER #$generation"
        )

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

        val newPlayer =
            ExoPlayer.Builder(activity)
                .setMediaSourceFactory(
                    DefaultMediaSourceFactory(
                        httpFactory
                    )
                )
                .build()

        // Guardamos el nuevo player antes de comenzar.
        player = newPlayer
        currentUrl = url

        newPlayer.setVideoSurfaceView(
            currentSurfaceView
        )

        Log.i(
            TAG,
            "PLAYER #$generation conectado al SurfaceView"
        )

        // --------------------------------------------------------
        // LOGS DE DIAGNÓSTICO
        // --------------------------------------------------------

        newPlayer.addListener(
            object : Player.Listener {

                override fun onPlaybackStateChanged(
                    playbackState: Int
                ) {
                    // Si esta sesión ya dejó de ser la actual,
                    // ignoramos callbacks atrasados.
                    if (player !== newPlayer) {
                        return
                    }

                    val state = when (playbackState) {
                        Player.STATE_IDLE ->
                            "IDLE"

                        Player.STATE_BUFFERING ->
                            "BUFFERING"

                        Player.STATE_READY ->
                            "READY"

                        Player.STATE_ENDED ->
                            "ENDED"

                        else ->
                            "UNKNOWN"
                    }

                    Log.i(
                        TAG,
                        "PLAYER #$generation " +
                            "Estado=$state " +
                            "playWhenReady=" +
                            newPlayer.playWhenReady
                    )
                }

                override fun onVideoSizeChanged(
                    videoSize: VideoSize
                ) {
                    if (player !== newPlayer) {
                        return
                    }

                    Log.i(
                        TAG,
                        "PLAYER #$generation " +
                            "VideoSize=" +
                            "${videoSize.width}x" +
                            "${videoSize.height}"
                    )
                }

                override fun onRenderedFirstFrame() {
                    if (player !== newPlayer) {
                        return
                    }

                    Log.i(
                        TAG,
                        "PLAYER #$generation " +
                            "***** PRIMER FRAME *****"
                    )
                }

                override fun onPlayerError(
                    error: PlaybackException
                ) {
                    if (player !== newPlayer) {
                        return
                    }

                    Log.e(
                        TAG,
                        "PLAYER #$generation " +
                            "ERROR=${error.errorCodeName}",
                        error
                    )
                }
            }
        )

        newPlayer.addAnalyticsListener(
            object : AnalyticsListener {

                override fun onDroppedVideoFrames(
                    eventTime: AnalyticsListener.EventTime,
                    droppedFrames: Int,
                    elapsedMs: Long
                ) {
                    if (player !== newPlayer) {
                        return
                    }

                    Log.w(
                        TAG,
                        "PLAYER #$generation " +
                            "DROPPED_FRAMES=" +
                            "$droppedFrames " +
                            "periodo=${elapsedMs}ms"
                    )
                }
            }
        )

        // --------------------------------------------------------
        // 3. CARGAMOS EL NUEVO STREAM
        // --------------------------------------------------------

        val mediaItem =
            MediaItem.Builder()
                .setUri(url)
                .setMimeType(
                    MimeTypes.APPLICATION_M3U8
                )
                .build()

        newPlayer.setMediaItem(
            mediaItem
        )

        newPlayer.prepare()

        newPlayer.playWhenReady = true

        Log.i(
            TAG,
            "PLAYER #$generation reproducción solicitada"
        )

        Log.i(
            TAG,
            "========================================"
        )
    }

    // ============================================================
    // LIBERACIÓN DE PLAYER
    // ============================================================

    private fun releaseCurrentPlayer() {
        val oldPlayer = player
        val currentSurfaceView = surfaceView

        if (oldPlayer == null) {
            Log.i(
                TAG,
                "No había una sesión anterior que liberar"
            )

            return
        }

        Log.i(
            TAG,
            "Liberando ExoPlayer anterior"
        )

        try {
            // Evitamos que siga intentando reproducir.
            oldPlayer.playWhenReady = false
        } catch (e: Exception) {
            Log.w(
                TAG,
                "No se pudo desactivar playWhenReady: $e"
            )
        }

        try {
            oldPlayer.pause()
        } catch (e: Exception) {
            Log.w(
                TAG,
                "No se pudo pausar player anterior: $e"
            )
        }

        try {
            oldPlayer.stop()
        } catch (e: Exception) {
            Log.w(
                TAG,
                "No se pudo detener player anterior: $e"
            )
        }

        try {
            if (currentSurfaceView != null) {
                oldPlayer.clearVideoSurfaceView(
                    currentSurfaceView
                )
            }
        } catch (e: Exception) {
            Log.w(
                TAG,
                "No se pudo liberar SurfaceView anterior: $e"
            )
        }

        try {
            oldPlayer.clearMediaItems()
        } catch (e: Exception) {
            Log.w(
                TAG,
                "No se pudieron limpiar MediaItems: $e"
            )
        }

        try {
            oldPlayer.release()
        } catch (e: Exception) {
            Log.w(
                TAG,
                "Error liberando ExoPlayer: $e"
            )
        }

        // Muy importante:
        // quitamos inmediatamente la referencia a la sesión anterior.
        player = null

        Log.i(
            TAG,
            "ExoPlayer anterior liberado completamente"
        )
    }

    // ============================================================
    // OCULTAR
    // ============================================================

    fun hide() {
        activity.runOnUiThread {

            container?.visibility =
                View.GONE

            // Al salir de TV o cambiar de categoría,
            // liberamos también la sesión multimedia.
            releaseCurrentPlayer()

            currentUrl = null

            Log.i(
                TAG,
                "Overlay ocultado"
            )
        }
    }

    // ============================================================
    // DESTRUCCIÓN TOTAL
    // ============================================================

    fun dispose() {
        activity.runOnUiThread {

            Log.i(
                TAG,
                "Liberando completamente overlay nativo"
            )

            releaseCurrentPlayer()

            container?.let { view ->

                val parent =
                    view.parent as? FrameLayout

                parent?.removeView(
                    view
                )
            }

            player = null
            surfaceView = null
            container = null
            currentUrl = null

            Log.i(
                TAG,
                "Overlay nativo eliminado"
            )
        }
    }
}