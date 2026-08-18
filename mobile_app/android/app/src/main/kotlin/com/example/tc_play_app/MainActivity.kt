package com.example.tc_play_app

import android.app.PictureInPictureParams
import android.content.res.Configuration
import android.os.Build
import android.util.Rational
import com.example.tc_play_app.tv.TvPlayerPlatformViewFactory
import com.example.tc_play_app.tv.overlay.TvOverlayController
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "tc_play/pip"
        private const val TV_OVERLAY_CHANNEL = "tc_play/tv_overlay"
    }

    // Canal nativo para Picture in Picture.
    private var pipChannel: MethodChannel? = null

    // Controla si Android puede entrar automáticamente a PiP
    // cuando el usuario presiona Home.
    private var pipEnabled: Boolean = false

    // Canal y controlador del overlay nativo para TV.
    private var tvOverlayChannel: MethodChannel? = null
    private var tvOverlayController: TvOverlayController? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ============================================================
        // PLAYER NATIVO MEDIANTE PLATFORM VIEW
        //
        // Lo conservamos temporalmente porque forma parte del
        // laboratorio anterior. Más adelante podremos retirarlo si el
        // overlay nativo demuestra ser la solución definitiva.
        // ============================================================

        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                "tcplay/tv-native-player",
                TvPlayerPlatformViewFactory(),
            )

        // ============================================================
        // OVERLAY NATIVO PARA TV
        //
        // Este overlay se monta directamente sobre la Activity y NO
        // atraviesa PlatformView.
        // ============================================================

        tvOverlayController = TvOverlayController(this)

        tvOverlayChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            TV_OVERLAY_CHANNEL
        )

        tvOverlayChannel?.setMethodCallHandler { call, result ->

            when (call.method) {

                "showPlayer" -> {
                    val url =
                        call.argument<String>("url")

                    val x =
                        call.argument<Int>("x") ?: 0

                    val y =
                        call.argument<Int>("y") ?: 0

                    val width =
                        call.argument<Int>("width") ?: 1

                    val height =
                        call.argument<Int>("height") ?: 1

                    if (url.isNullOrBlank()) {
                        result.error(
                            "INVALID_URL",
                            "La URL del canal está vacía",
                            null
                        )
                        return@setMethodCallHandler
                    }

                    tvOverlayController?.showPlayer(
                        url = url,
                        x = x,
                        y = y,
                        width = width,
                        height = height
                    )

                    result.success(null)
                }

                "hide" -> {
                    tvOverlayController?.hide()
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }

        // ============================================================
        // PICTURE IN PICTURE
        // ============================================================

        pipChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        )

        pipChannel?.setMethodCallHandler { call, result ->

            when (call.method) {

                "enterPip" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {

                        val params = PictureInPictureParams.Builder()
                            .setAspectRatio(
                                Rational(16, 9)
                            )
                            .build()

                        val entered =
                            enterPictureInPictureMode(params)

                        result.success(entered)

                    } else {

                        result.success(false)
                    }
                }

                "isPipSupported" -> {
                    result.success(
                        Build.VERSION.SDK_INT >=
                            Build.VERSION_CODES.O
                    )
                }

                "setPipEnabled" -> {
                    pipEnabled =
                        call.argument<Boolean>("enabled")
                            ?: false

                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()

        // Solo entramos automáticamente a PiP si Flutter indicó
        // explícitamente que el reproductor fullscreen está activo.
        if (
            pipEnabled &&
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
        ) {

            val params = PictureInPictureParams.Builder()
                .setAspectRatio(
                    Rational(16, 9)
                )
                .build()

            enterPictureInPictureMode(params)
        }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(
            isInPictureInPictureMode,
            newConfig
        )

        pipChannel?.invokeMethod(
            "onPipModeChanged",
            isInPictureInPictureMode
        )
    }

    override fun onDestroy() {

        // Liberamos el overlay nativo.
        tvOverlayController?.dispose()
        tvOverlayController = null

        tvOverlayChannel?.setMethodCallHandler(null)
        tvOverlayChannel = null

        // Liberamos referencia al canal PiP.
        pipChannel?.setMethodCallHandler(null)
        pipChannel = null

        super.onDestroy()
    }
}