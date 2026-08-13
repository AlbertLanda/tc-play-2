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

    // Si el PiP nativo puede activarse en este momento. Antes
    // onUserLeaveHint() entraba a PiP SIEMPRE que el usuario apretaba
    // Home, sin importar qué pantalla de la app estuviera visible en ese
    // instante (el reproductor a pantalla completa, o cualquier otra
    // sección con el mini-reproductor propio de Flutter flotando
    // encima). Eso hacía que Android encogiera lo que fuera que hubiera
    // en pantalla —incluido el mini-reproductor— dentro de la ventanita
    // de PiP, en vez de encoger solo el video del reproductor.
    //
    // Ahora Flutter avisa por acá (ver "setPipEnabled" más abajo) si en
    // este momento corresponde permitir el PiP nativo: true solo cuando
    // PlayerScreen está realmente a pantalla completa, false en
    // cualquier otro caso. Por defecto arranca en false.
    private var pipEnabled: Boolean = false

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

                        // enterPictureInPictureMode() devuelve un boolean real
                        // (true si Android efectivamente activó la ventanita).
                        val entered = enterPictureInPictureMode(params)
                        result.success(entered)
                    } else {
                        result.success(false)
                    }
                }

                "isPipSupported" -> {
                    result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                }

                "setPipEnabled" -> {
                    pipEnabled = call.argument<Boolean>("enabled") ?: false
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()

        // Solo se entra a PiP automáticamente al apretar Home si Flutter
        // marcó que corresponde (PlayerScreen a pantalla completa). Si
        // el usuario está navegando por otra pantalla de la app con el
        // mini-reproductor propio activo, NO se entra a PiP nativo acá:
        // ese caso lo maneja Flutter pausando la reproducción.
        if (pipEnabled && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
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