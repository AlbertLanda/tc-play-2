package com.example.tc_play_app

import android.app.PictureInPictureParams
import android.content.res.Configuration
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "tc_play/pip"
    }

    // Guardamos la referencia del canal para poder AVISAR a Flutter
    // (no solo responder llamadas que vienen de Flutter).
    private var pipChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        pipChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        )

        pipChannel?.setMethodCallHandler { call, result ->

            when (call.method) {

                "enterPip" -> {

                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {

                        val params = PictureInPictureParams.Builder()
                            .setAspectRatio(Rational(16, 9))
                            .build()

                        enterPictureInPictureMode(params)
                        result.success(true)

                    } else {
                        result.success(false)
                    }
                }

                "isPipSupported" -> {
                    result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                }

                else -> result.notImplemented()
            }

        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {

            val params = PictureInPictureParams.Builder()
                .setAspectRatio(Rational(16, 9))
                .build()

            enterPictureInPictureMode(params)
        }
    }

    // Este callback lo dispara Android automáticamente cada vez que la
    // app ENTRA o SALE del modo mini-reproductor (PiP). Se lo pasamos a
    // Flutter para que pueda ocultar/mostrar los controles del player.
    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        pipChannel?.invokeMethod("onPipModeChanged", isInPictureInPictureMode)
    }
}
