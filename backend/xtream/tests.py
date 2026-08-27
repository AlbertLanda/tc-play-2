"""
Pruebas automáticas básicas del login normalizado de Xtream.

Se usa unittest.mock.patch para reemplazar XtreamClient y simular la
respuesta del panel Xtream SIN depender de la VPN/NOC ni de credenciales
reales. Cada prueba define la respuesta "cruda" que devolvería Xtream y
verifica cómo el backend la valida y normaliza.

Regla funcional validada:
    - Login válido  -> auth == 1 Y status == "Active"  (200)
    - auth != 1     -> invalid_credentials             (401)
    - auth == 1 pero status != "Active" -> inactive_account (403)
    - Body vacío    -> missing_credentials             (400, sin llamar a Xtream)
"""

from unittest.mock import patch

import os
import shutil
import tempfile
import time
from pathlib import Path

from django.test import SimpleTestCase, override_settings
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase

from .services import transcoder


def _raw_xtream_response(auth="1", status_value="Active"):
    """
    Construye una respuesta CRUDA de ejemplo como la que devuelve el
    panel Xtream. Incluye password y server_info a propósito para
    comprobar que el backend NO los reenvía al cliente.
    """
    return {
        "user_info": {
            "username": "cliente.demo",
            "password": "no-debe-filtrarse",
            "auth": auth,
            "status": status_value,
            "max_connections": "1",
            "active_cons": "0",
            "exp_date": None,
        },
        "server_info": {
            "url": "servidor-interno-no-debe-filtrarse",
            "port": "8080",
        },
    }


class XtreamLoginTests(APITestCase):
    def setUp(self):
        self.url = reverse("xtream_login")
        self.credentials = {"username": "cliente.demo", "password": "cualquiera"}

    @patch("xtream.views.XtreamClient")
    def test_login_activo(self, mock_client):
        """auth == 1 y status Active -> 200 con el usuario normalizado."""
        mock_client.return_value.authenticate.return_value = _raw_xtream_response(
            auth="1", status_value="Active"
        )

        response = self.client.post(self.url, self.credentials, format="json")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data["success"])
        user = response.data["user"]
        self.assertEqual(user["username"], "cliente.demo")
        self.assertEqual(user["auth"], 1)
        self.assertEqual(user["status"], "Active")
        self.assertTrue(user["is_active"])

    @patch("xtream.views.XtreamClient")
    def test_auth_invalido(self, mock_client):
        """auth == 0 -> invalid_credentials (401)."""
        mock_client.return_value.authenticate.return_value = _raw_xtream_response(
            auth="0", status_value="Active"
        )

        response = self.client.post(self.url, self.credentials, format="json")

        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)
        self.assertFalse(response.data["success"])
        self.assertEqual(response.data["error_code"], "invalid_credentials")

    @patch("xtream.views.XtreamClient")
    def test_cuenta_inactiva(self, mock_client):
        """
        auth == 1 pero status no Active -> inactive_account (403).
        Se prueban varios estados no activos que Xtream puede devolver.
        """
        for estado in ("Disabled", "Expired", "Banned"):
            with self.subTest(estado=estado):
                mock_client.return_value.authenticate.return_value = (
                    _raw_xtream_response(auth="1", status_value=estado)
                )

                response = self.client.post(
                    self.url, self.credentials, format="json"
                )

                # El cuerpo debe coincidir exactamente con la respuesta
                # definida para cuenta inactiva (sección 7 del plan).
                self.assertEqual(
                    response.status_code, status.HTTP_403_FORBIDDEN
                )
                self.assertEqual(
                    response.data,
                    {
                        "success": False,
                        "error_code": "inactive_account",
                        "message": "La cuenta no se encuentra activa.",
                    },
                )

    @patch("xtream.views.XtreamClient")
    def test_body_vacio(self, mock_client):
        """Body vacío -> missing_credentials (400) sin tocar Xtream."""
        response = self.client.post(self.url, {}, format="json")

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertFalse(response.data["success"])
        self.assertEqual(response.data["error_code"], "missing_credentials")
        # El backend debe cortar antes de instanciar/consultar Xtream.
        mock_client.assert_not_called()

    @patch("xtream.views.XtreamClient")
    def test_sin_datos_sensibles(self, mock_client):
        """La respuesta exitosa no debe incluir password ni server_info."""
        mock_client.return_value.authenticate.return_value = _raw_xtream_response(
            auth="1", status_value="Active"
        )

        response = self.client.post(self.url, self.credentials, format="json")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        user = response.data["user"]
        self.assertNotIn("password", user)
        self.assertNotIn("server_info", user)
        self.assertNotIn("server_info", response.data)


class LiveProxyUrlTests(APITestCase):
    """
    Pruebas del endpoint experimental de proxy/transcoder HLS.

    Se mockea el servicio transcoder para NO depender de FFmpeg ni de
    credenciales/streams reales. Se valida el contrato: validaciones,
    ffmpeg no disponible, éxito con hls_url y que no se filtre la URL
    original con credenciales.
    """

    def setUp(self):
        self.url = reverse("live_proxy_url")
        self.payload = {
            "username": "cliente.demo",
            "password": "cualquiera",
            "stream_id": 123,
        }

    def test_faltan_datos(self):
        """Sin stream_id -> validation_error (400) sin tocar el transcoder."""
        response = self.client.post(
            self.url,
            {"username": "x", "password": "y"},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data["error_code"], "validation_error")

    def test_stream_id_invalido(self):
        """stream_id con caracteres peligrosos -> validation_error (400)."""
        payload = dict(self.payload, stream_id="../../etc")
        response = self.client.post(self.url, payload, format="json")

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data["error_code"], "validation_error")

    @patch("xtream.views.transcoder.start_hls_transcode")
    def test_ffmpeg_no_disponible(self, mock_start):
        """Si FFmpeg no está -> ffmpeg_not_available (503)."""
        mock_start.side_effect = transcoder.FFmpegNotAvailableError(
            "FFmpeg no está disponible."
        )

        response = self.client.post(self.url, self.payload, format="json")

        self.assertEqual(
            response.status_code, status.HTTP_503_SERVICE_UNAVAILABLE
        )
        self.assertEqual(response.data["error_code"], "ffmpeg_not_available")

    @patch("xtream.views.transcoder.wait_for_hls_ready", return_value=True)
    @patch("xtream.views.transcoder.start_hls_transcode")
    def test_proxy_exitoso(self, mock_start, mock_wait):
        """Éxito -> 200 con hls_url y el modo elegido (remux/transcode)."""
        mock_start.return_value = ("123", False, "transcode")

        response = self.client.post(self.url, self.payload, format="json")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data["success"])
        self.assertEqual(response.data["stream_id"], "123")
        self.assertIn("hls/123/index.m3u8", response.data["hls_url"])
        self.assertEqual(response.data["mode"], "transcode")
        self.assertFalse(response.data["reused"])

    @patch("xtream.views.transcoder.wait_for_hls_ready", return_value=True)
    @patch("xtream.views.transcoder.start_hls_transcode")
    def test_device_profile_default_mobile(self, mock_start, mock_wait):
        """Sin device_profile -> se usa 'mobile' y se refleja en la respuesta."""
        mock_start.return_value = ("123", False, "transcode")

        response = self.client.post(self.url, self.payload, format="json")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["device_profile"], "mobile")
        # start_hls_transcode debe recibir device_profile='mobile'.
        self.assertEqual(
            mock_start.call_args.kwargs.get("device_profile"), "mobile"
        )

    @patch("xtream.views.transcoder.wait_for_hls_ready", return_value=True)
    @patch("xtream.views.transcoder.start_hls_transcode")
    def test_device_profile_tv(self, mock_start, mock_wait):
        """device_profile='tv' -> se propaga al transcoder y a la respuesta."""
        mock_start.return_value = ("123", False, "transcode")
        payload = dict(self.payload, device_profile="tv")

        response = self.client.post(self.url, payload, format="json")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["device_profile"], "tv")
        self.assertEqual(
            mock_start.call_args.kwargs.get("device_profile"), "tv"
        )

    @patch("xtream.views.transcoder.start_hls_transcode")
    def test_device_profile_invalido(self, mock_start):
        """device_profile no reconocido -> invalid_device_profile (400)."""
        payload = dict(self.payload, device_profile="playstation")

        response = self.client.post(self.url, payload, format="json")

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(
            response.data["error_code"], "invalid_device_profile"
        )
        mock_start.assert_not_called()

    @patch("xtream.views.transcoder.wait_for_hls_ready", return_value=True)
    @patch("xtream.views.transcoder.start_hls_transcode")
    def test_no_filtra_credenciales(self, mock_start, mock_wait):
        """La respuesta no debe contener la contraseña ni la URL original."""
        mock_start.return_value = ("123", False, "remux")

        response = self.client.post(self.url, self.payload, format="json")

        cuerpo = str(response.data)
        self.assertNotIn("cualquiera", cuerpo)  # password
        self.assertNotIn("/live/", cuerpo)      # ruta de la URL original TS
    
    @patch("xtream.views.transcoder.start_hls_transcode")
    def test_reutiliza_proceso_activo(self, mock_start):
        """Si ya hay HLS activo, el transcoder lo reutiliza (reused=True)."""
        mock_start.return_value = ("123", True, None)

        response = self.client.post(self.url, self.payload, format="json")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data["reused"])

    @patch("xtream.views.transcoder.start_hls_transcode")
    @patch("xtream.views.XtreamClient")
    def test_url_original_invalida(self, mock_client, mock_start):
        """
        Si la URL original no se puede construir (p. ej. XTREAM_BASE_URL
        vacío -> URL sin http) -> stream_url_error (502) y NO se lanza FFmpeg.
        """
        mock_client.return_value.build_live_stream_url.return_value = (
            "/live/cliente.demo/cualquiera/123.ts"
        )

        response = self.client.post(self.url, self.payload, format="json")

        self.assertEqual(response.status_code, status.HTTP_502_BAD_GATEWAY)
        self.assertEqual(response.data["error_code"], "stream_url_error")
        mock_start.assert_not_called()

    @patch("pathlib.Path.mkdir", side_effect=OSError("sin permisos"))
    @patch("xtream.services.transcoder.is_stream_active", return_value=False)
    @patch("xtream.services.transcoder.is_ffmpeg_available", return_value=True)
    @patch("xtream.views.XtreamClient")
    def test_error_al_crear_carpeta(
        self, mock_client, mock_ffmpeg, mock_active, mock_mkdir
    ):
        """
        Si no se puede crear la carpeta HLS (mkdir falla) ->
        hls_output_error (500). Se deja correr el transcoder real y se
        fuerza el fallo justo en la creación de la carpeta.
        """
        mock_client.return_value.build_live_stream_url.return_value = (
            "http://servidor/live/cliente.demo/cualquiera/123.ts"
        )

        response = self.client.post(self.url, self.payload, format="json")

        self.assertEqual(
            response.status_code, status.HTTP_500_INTERNAL_SERVER_ERROR
        )
        self.assertEqual(response.data["error_code"], "hls_output_error")

    @patch("xtream.services.transcoder.subprocess.Popen", side_effect=OSError)
    @patch("xtream.services.transcoder.decide_mode", return_value="transcode")
    @patch("pathlib.Path.mkdir")
    @patch("xtream.services.transcoder.is_stream_active", return_value=False)
    @patch("xtream.services.transcoder.is_ffmpeg_available", return_value=True)
    @patch("xtream.views.XtreamClient")
    def test_error_al_iniciar_ffmpeg(
        self, mock_client, mock_ffmpeg, mock_active, mock_mkdir,
        mock_mode, mock_popen
    ):
        """
        Si FFmpeg no se puede iniciar (Popen lanza OSError) ->
        transcoder_start_error (500). La carpeta sí se crea (mkdir mockeado
        para no fallar) y el fallo ocurre al lanzar el proceso. Se mockea
        decide_mode para no ejecutar ffprobe real sobre una URL de prueba.
        """
        mock_client.return_value.build_live_stream_url.return_value = (
            "http://servidor/live/cliente.demo/cualquiera/123.ts"
        )

        response = self.client.post(self.url, self.payload, format="json")

        self.assertEqual(
            response.status_code, status.HTTP_500_INTERNAL_SERVER_ERROR
        )
        self.assertEqual(response.data["error_code"], "transcoder_start_error")

    @patch("xtream.views.transcoder.remove_hls_output")
    @patch("xtream.views.transcoder.stop_hls_transcode")
    @patch("xtream.views.transcoder.get_hls_status")
    @patch("xtream.views.transcoder.wait_for_hls_ready", return_value=False)
    @patch("xtream.views.transcoder.start_hls_transcode")
    def test_hls_no_listo_limpia_y_devuelve_diagnostico(
        self, mock_start, mock_wait, mock_status, mock_stop, mock_remove
    ):
        """
        Si el HLS no queda listo a tiempo -> hls_not_ready (500) con el
        detalle hls_status, y se limpia el proceso y la salida.
        """
        mock_start.return_value = ("123", False, "transcode")
        mock_status.return_value = {
            "stream_id": "123",
            "index_exists": True,
            "index_size_bytes": 271,
            "segments": 0,
            "min_segments_required": 2,
            "ready": False,
            "damaged": True,
            "process_alive": False,
        }

        response = self.client.post(self.url, self.payload, format="json")

        self.assertEqual(
            response.status_code, status.HTTP_500_INTERNAL_SERVER_ERROR
        )
        self.assertEqual(response.data["error_code"], "hls_not_ready")
        self.assertEqual(response.data["stream_id"], "123")
        self.assertEqual(response.data["hls_status"]["segments"], 0)
        self.assertFalse(response.data["hls_status"]["ready"])
        # El diagnóstico se toma antes de limpiar; luego se detiene y borra.
        mock_stop.assert_called_once_with("123")
        mock_remove.assert_called_once_with("123")


class TranscoderModeTests(SimpleTestCase):
    """
    Pruebas de la decisión remux vs transcode según el códec del canal.
    Se mockea probe_codecs para no depender de ffprobe ni de un stream real.
    """

    @staticmethod
    def _info(video, audio, height=1080, fps=30.0):
        return {
            "video_codec": video,
            "audio_codec": audio,
            "height": height,
            "fps": fps,
        }

    @patch("xtream.services.transcoder.probe_stream_info")
    def test_remux_si_codec_compatible(self, mock_probe):
        """h264 + aac (30fps) -> remux (no hace falta transcodificar)."""
        mock_probe.return_value = self._info("h264", "aac")
        self.assertEqual(transcoder.decide_mode("http://x"), "remux")

    @patch("xtream.services.transcoder.probe_stream_info")
    def test_transcode_audio_si_solo_audio_incompatible(self, mock_probe):
        """h264 + mp2 (30fps) -> transcode_audio (video OK, se arregla audio)."""
        mock_probe.return_value = self._info("h264", "mp2")
        self.assertEqual(transcoder.decide_mode("http://x"), "transcode_audio")

    @patch("xtream.services.transcoder.probe_stream_info")
    def test_remux_si_video_ok_sin_audio(self, mock_probe):
        """h264 sin audio detectado (30fps) -> remux."""
        mock_probe.return_value = self._info("h264", None)
        self.assertEqual(transcoder.decide_mode("http://x"), "remux")

    @patch("xtream.services.transcoder.probe_stream_info")
    def test_transcode_si_codec_incompatible(self, mock_probe):
        """hevc / ac3 -> transcode (el navegador no soporta el video)."""
        mock_probe.return_value = self._info("hevc", "ac3")
        self.assertEqual(transcoder.decide_mode("http://x"), "transcode")

    @patch("xtream.services.transcoder.probe_stream_info")
    def test_transcode_si_codec_desconocido(self, mock_probe):
        """Si no se puede leer el códec -> transcode por seguridad."""
        mock_probe.return_value = self._info(None, None, height=None, fps=None)
        self.assertEqual(transcoder.decide_mode("http://x"), "transcode")

    @patch("xtream.services.transcoder.probe_stream_info")
    def test_transcode_movil_si_alto_framerate(self, mock_probe):
        """h264 + aac PERO a 60fps -> transcode (normalización móvil 720p30)."""
        mock_probe.return_value = self._info("h264", "aac", fps=59.94)
        self.assertEqual(transcoder.decide_mode("http://x"), "transcode")

    @patch("xtream.services.transcoder.probe_stream_info")
    def test_transcode_audio_no_sube_a_transcode_a_30fps(self, mock_probe):
        """h264 + mp2 a 29.97fps NO se sube a transcode (el cel lo maneja)."""
        mock_probe.return_value = self._info("h264", "mp2", fps=29.97)
        self.assertEqual(transcoder.decide_mode("http://x"), "transcode_audio")

    def test_build_command_remux_usa_copy(self):
        """El comando en modo remux usa -c copy y no libx264."""
        cmd = transcoder._build_ffmpeg_command("http://x", "out.m3u8", "remux")
        self.assertIn("copy", cmd)
        self.assertNotIn("libx264", cmd)

    def test_build_command_transcode_audio_copia_video(self):
        """En transcode_audio se copia el video (-c:v copy) y se recodifica audio."""
        cmd = transcoder._build_ffmpeg_command(
            "http://x", "out.m3u8", "transcode_audio"
        )
        self.assertEqual(cmd[cmd.index("-c:v") + 1], "copy")
        self.assertEqual(cmd[cmd.index("-c:a") + 1], "aac")
        self.assertNotIn("libx264", cmd)

    def test_build_command_transcode_usa_libx264(self):
        """El comando en modo transcode recodifica con libx264/aac."""
        cmd = transcoder._build_ffmpeg_command("http://x", "out.m3u8", "transcode")
        self.assertIn("libx264", cmd)
        self.assertNotIn("copy", cmd)

    def test_build_command_transcode_fuerza_yuv420p(self):
        """El modo transcode fuerza -pix_fmt yuv420p (compatibilidad Android)."""
        cmd = transcoder._build_ffmpeg_command("http://x", "out.m3u8", "transcode")
        self.assertEqual(cmd[cmd.index("-pix_fmt") + 1], "yuv420p")

    # --- Perfiles por dispositivo (device_profile) -----------------------

    @patch("xtream.services.transcoder.probe_stream_info")
    def test_web_no_fuerza_transcode_a_60fps(self, mock_probe):
        """
        Perfil web: h264 + aac a 60fps NO se sube a transcode (el navegador/PC
        decodifica 60fps). Se queda en remux, a diferencia de mobile/tv.
        """
        mock_probe.return_value = self._info("h264", "aac", fps=59.94)
        self.assertEqual(
            transcoder.decide_mode("http://x", device_profile="web"), "remux"
        )

    @patch("xtream.services.transcoder.probe_stream_info")
    def test_tv_copy_first_no_fuerza_transcode_a_60fps(self, mock_probe):
        """
        Perfil tv (copy-first): h264 + aac a 60fps NO se sube a transcode; se
        respeta el video original (remux). La normalización 720p30 es solo
        para móvil hasta validar el desempeño en una TV real.
        """
        mock_probe.return_value = self._info("h264", "aac", fps=59.94)
        self.assertEqual(
            transcoder.decide_mode("http://x", device_profile="tv"), "remux"
        )

    @patch("xtream.services.transcoder.probe_stream_info")
    def test_tv_copy_first_solo_arregla_audio(self, mock_probe):
        """
        Perfil tv (copy-first): h264 + mp2 a 60fps -> transcode_audio (copia el
        video 1080p60, solo convierte el audio a AAC), NO transcode de video.
        """
        mock_probe.return_value = self._info("h264", "mp2", fps=59.94)
        self.assertEqual(
            transcoder.decide_mode("http://x", device_profile="tv"),
            "transcode_audio",
        )

    def test_build_command_mobile_720p30_1800k(self):
        """Perfil mobile: escala a 720p, fps=30, bitrate 1800k y preset ultrafast."""
        cmd = transcoder._build_ffmpeg_command(
            "http://x", "out.m3u8", "transcode", device_profile="mobile"
        )

        vf = cmd[cmd.index("-vf") + 1]

        self.assertIn("min(720,ih)", vf)
        self.assertIn("fps=30", vf)
        self.assertEqual(cmd[cmd.index("-b:v") + 1], "1800k")
        self.assertEqual(cmd[cmd.index("-maxrate") + 1], "2000k")
        self.assertEqual(cmd[cmd.index("-bufsize") + 1], "4000k")
        self.assertEqual(cmd[cmd.index("-g") + 1], "60")
        self.assertEqual(cmd[cmd.index("-preset") + 1], "ultrafast")

    def test_build_command_tv_720p30_3000k(self):
        """Perfil tv: escala a 720p, fps=30 y bitrate mayor (3000k)."""
        cmd = transcoder._build_ffmpeg_command(
            "http://x", "out.m3u8", "transcode", device_profile="tv"
        )
        vf = cmd[cmd.index("-vf") + 1]
        self.assertIn("min(720,ih)", vf)
        self.assertIn("fps=30", vf)
        self.assertEqual(cmd[cmd.index("-b:v") + 1], "3000k")

    def test_build_command_web_preserva_resolucion_y_fps(self):
        """
        Perfil web en transcode: NO reescala ni normaliza fps (sin -vf) y usa
        calidad por CRF (sin -b:v). Preserva la señal original.
        """
        cmd = transcoder._build_ffmpeg_command(
            "http://x", "out.m3u8", "transcode", device_profile="web"
        )
        self.assertIn("libx264", cmd)
        self.assertNotIn("-vf", cmd)
        self.assertNotIn("-b:v", cmd)
        self.assertIn("-crf", cmd)

    def test_normalize_device_profile_default_y_validos(self):
        """None/'' -> mobile (default); mobile/tv/web válidos (case-insensitive)."""
        self.assertEqual(transcoder.normalize_device_profile(None), "mobile")
        self.assertEqual(transcoder.normalize_device_profile(""), "mobile")
        self.assertEqual(transcoder.normalize_device_profile("tv"), "tv")
        self.assertEqual(transcoder.normalize_device_profile("TV"), "tv")
        self.assertEqual(transcoder.normalize_device_profile("web"), "web")

    def test_normalize_device_profile_invalido_lanza(self):
        """Un perfil no reconocido lanza ValueError."""
        with self.assertRaises(ValueError):
            transcoder.normalize_device_profile("consola")


class TranscoderLifecycleTests(SimpleTestCase):
    """
    Pruebas del límite de procesos concurrentes y de la limpieza automática
    por TTL. No dependen de FFmpeg real.
    """

    @override_settings(MAX_CONCURRENT_TRANSCODES=5)
    @patch("xtream.services.transcoder.count_active_processes", return_value=5)
    @patch("xtream.services.transcoder.is_stream_active", return_value=False)
    @patch("xtream.services.transcoder.is_ffmpeg_available", return_value=True)
    def test_limite_concurrencia(self, mock_ffmpeg, mock_active, mock_count):
        """Si se alcanzó el límite de procesos -> TranscoderBusyError (503)."""
        with self.assertRaises(transcoder.TranscoderBusyError):
            transcoder.start_hls_transcode("http://x/live/u/p/9.ts", "999")

    def test_cleanup_borra_inactivos_y_conserva_activos(self):
        """
        cleanup_inactive borra las carpetas cuya salida está obsoleta (mtime
        viejo) y conserva las frescas (FFmpeg sigue escribiendo).
        """
        tmp = Path(tempfile.mkdtemp())
        try:
            viejo = tmp / "900"
            viejo.mkdir()
            (viejo / "index.m3u8").write_text("x")
            # Envejecer el index.m3u8 más allá del TTL.
            antiguo = time.time() - 9999
            os.utime(viejo / "index.m3u8", (antiguo, antiguo))

            fresco = tmp / "901"
            fresco.mkdir()
            (fresco / "index.m3u8").write_text("x")

            with override_settings(HLS_ROOT=tmp, HLS_CLEANUP_TTL_SECONDS=300):
                cleaned = transcoder.cleanup_inactive()

            self.assertIn("900", cleaned)
            self.assertFalse(viejo.exists())      # inactivo -> borrado
            self.assertTrue(fresco.exists())      # fresco -> conservado
        finally:
            shutil.rmtree(tmp, ignore_errors=True)

    def test_cleanup_borra_carpeta_huerfana_sin_playlist(self):
        """Una carpeta sin index.m3u8 se considera huérfana y se borra."""
        tmp = Path(tempfile.mkdtemp())
        try:
            huerfana = tmp / "902"
            huerfana.mkdir()  # sin index.m3u8

            with override_settings(HLS_ROOT=tmp, HLS_CLEANUP_TTL_SECONDS=300):
                cleaned = transcoder.cleanup_inactive()

            self.assertIn("902", cleaned)
            self.assertFalse(huerfana.exists())
        finally:
            shutil.rmtree(tmp, ignore_errors=True)


# --- Día 8: control de procesos y diagnóstico de canales Xtream -----------

class LiveStopProxyTests(APITestCase):
    """POST /api/xtream/live/stop-proxy/ (detener + borrar salida HLS)."""

    def setUp(self):
        self.url = reverse("live_stop_proxy")

    def test_stream_id_faltante_devuelve_400(self):
        response = self.client.post(self.url, {}, format="json")

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data["error_code"], "missing_stream_id")

    def test_stream_id_invalido_devuelve_400(self):
        response = self.client.post(
            self.url, {"stream_id": "../../etc"}, format="json"
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data["error_code"], "invalid_stream_id")

    @patch("xtream.views.transcoder.remove_hls_output", return_value=True)
    @patch("xtream.views.transcoder.stop_hls_transcode", return_value=True)
    def test_detiene_proceso_existente(self, mock_stop, mock_remove):
        response = self.client.post(self.url, {"stream_id": 41}, format="json")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data["success"])
        self.assertTrue(response.data["stopped"])
        self.assertTrue(response.data["output_removed"])
        self.assertEqual(response.data["stream_id"], "41")
        # Sin device_profile explícito se detiene la salida mobile (default),
        # no un "41" genérico: la limpieza es por perfil.
        self.assertEqual(response.data["device_profile"], "mobile")
        mock_stop.assert_called_once_with("41-mobile")
        mock_remove.assert_called_once_with("41-mobile")

    @patch("xtream.views.transcoder.remove_hls_output", return_value=False)
    @patch("xtream.views.transcoder.stop_hls_transcode", return_value=False)
    def test_sin_proceso_activo_responde_stopped_false(self, mock_stop, mock_remove):
        response = self.client.post(self.url, {"stream_id": 999}, format="json")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data["success"])
        self.assertFalse(response.data["stopped"])
        self.assertFalse(response.data["output_removed"])


class LiveProxyStatusTests(APITestCase):
    """GET /api/xtream/live/proxy-status/ (monitoreo del transcoder)."""

    def setUp(self):
        self.url = reverse("live_proxy_status")

    @patch("xtream.views.transcoder.get_transcoder_status")
    def test_devuelve_estado_del_transcoder(self, mock_status):
        mock_status.return_value = {
            "active_processes": 1,
            "max_concurrent": 5,
            "outputs": [
                {
                    "stream_id": "41",
                    "process_alive": True,
                    "index_exists": True,
                    "index_age_seconds": 2.5,
                    "index_size_bytes": 350,
                    "segments": 6,
                    "damaged": False,
                }
            ],
        }

        response = self.client.get(self.url)

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data["success"])
        self.assertEqual(response.data["active_processes"], 1)
        self.assertEqual(response.data["max_concurrent"], 5)
        self.assertEqual(response.data["outputs"][0]["stream_id"], "41")

    def test_solo_acepta_get(self):
        response = self.client.post(self.url, {}, format="json")

        self.assertEqual(
            response.status_code, status.HTTP_405_METHOD_NOT_ALLOWED
        )


class LiveDiagnoseStreamTests(APITestCase):
    """POST /api/xtream/live/diagnose-stream/ (códecs + modo recomendado)."""

    def setUp(self):
        self.url = reverse("live_diagnose_stream")
        self.payload = {
            "username": "cliente.demo",
            "password": "cualquiera",
            "stream_id": 41,
            "output": "m3u8",
        }

    def test_credenciales_faltantes_devuelve_400(self):
        response = self.client.post(
            self.url, {"stream_id": 41}, format="json"
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data["error_code"], "missing_credentials")

    def test_stream_id_faltante_devuelve_400(self):
        response = self.client.post(
            self.url,
            {"username": "x", "password": "y"},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data["error_code"], "missing_stream_id")

    @patch("xtream.views.transcoder.is_ffmpeg_available", return_value=False)
    def test_ffmpeg_no_disponible_devuelve_503(self, _mock_ffmpeg):
        response = self.client.post(self.url, self.payload, format="json")

        self.assertEqual(
            response.status_code, status.HTTP_503_SERVICE_UNAVAILABLE
        )
        self.assertEqual(response.data["error_code"], "ffmpeg_not_available")

    @patch("xtream.views.transcoder.is_ffmpeg_available", return_value=True)
    @patch("xtream.views.XtreamClient")
    def test_url_invalida_devuelve_502(self, mock_client, _mock_ffmpeg):
        """URL sin http (XTREAM_BASE_URL vacío) -> stream_url_error (502)."""
        mock_client.return_value.build_live_stream_url.return_value = (
            "/live/cliente.demo/cualquiera/41.m3u8"
        )

        response = self.client.post(self.url, self.payload, format="json")

        self.assertEqual(response.status_code, status.HTTP_502_BAD_GATEWAY)
        self.assertEqual(response.data["error_code"], "stream_url_error")

    @patch("xtream.views.transcoder.probe_codecs", return_value=("h264", "aac"))
    @patch("xtream.views.transcoder.is_ffmpeg_available", return_value=True)
    @patch("xtream.views.XtreamClient")
    def test_diagnostico_exitoso_remux(self, mock_client, _mock_ffmpeg, _mock_probe):
        """h264 + aac -> web_compatible true y recommended_mode remux."""
        mock_client.return_value.build_live_stream_url.return_value = (
            "http://servidor/live/cliente.demo/cualquiera/41.m3u8"
        )

        response = self.client.post(self.url, self.payload, format="json")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data["success"])
        self.assertEqual(response.data["stream_id"], "41")
        self.assertEqual(response.data["video_codec"], "h264")
        self.assertEqual(response.data["audio_codec"], "aac")
        self.assertTrue(response.data["web_compatible"])
        self.assertEqual(response.data["recommended_mode"], "remux")

    @patch("xtream.views.transcoder.probe_codecs", return_value=("hevc", "ac3"))
    @patch("xtream.views.transcoder.is_ffmpeg_available", return_value=True)
    @patch("xtream.views.XtreamClient")
    def test_diagnostico_incompatible_transcode(
        self, mock_client, _mock_ffmpeg, _mock_probe
    ):
        """hevc + ac3 -> web_compatible false y recommended_mode transcode."""
        mock_client.return_value.build_live_stream_url.return_value = (
            "http://servidor/live/cliente.demo/cualquiera/41.m3u8"
        )

        response = self.client.post(self.url, self.payload, format="json")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertFalse(response.data["web_compatible"])
        self.assertEqual(response.data["recommended_mode"], "transcode")

    @patch("xtream.views.transcoder.probe_codecs", return_value=("h264", "aac"))
    @patch("xtream.views.transcoder.is_ffmpeg_available", return_value=True)
    @patch("xtream.views.XtreamClient")
    def test_no_filtra_credenciales(self, mock_client, _mock_ffmpeg, _mock_probe):
        """La respuesta de diagnóstico no debe exponer password ni la URL."""
        mock_client.return_value.build_live_stream_url.return_value = (
            "http://servidor/live/cliente.demo/cualquiera/41.m3u8"
        )

        response = self.client.post(self.url, self.payload, format="json")

        cuerpo = str(response.data)
        self.assertNotIn("cualquiera", cuerpo)   # password
        self.assertNotIn("/live/", cuerpo)       # ruta con credenciales


class ModeFromCodecsTests(SimpleTestCase):
    """Decisión de modo a partir de códecs ya sondeados (sin ffprobe)."""

    def test_h264_aac_es_remux(self):
        self.assertEqual(transcoder.mode_from_codecs("h264", "aac"), "remux")

    def test_h264_sin_audio_es_remux(self):
        self.assertEqual(transcoder.mode_from_codecs("h264", None), "remux")

    def test_h264_audio_incompatible_es_transcode_audio(self):
        self.assertEqual(
            transcoder.mode_from_codecs("h264", "mp2"), "transcode_audio"
        )

    def test_video_incompatible_es_transcode(self):
        self.assertEqual(transcoder.mode_from_codecs("hevc", "aac"), "transcode")

    def test_codec_desconocido_es_transcode(self):
        self.assertEqual(transcoder.mode_from_codecs(None, None), "transcode")

    def test_solo_audio_compatible_es_remux(self):
        """Radio (sin video) con audio aac -> remux, NO transcode (no libx264)."""
        self.assertEqual(transcoder.mode_from_codecs(None, "aac"), "remux")

    def test_solo_audio_incompatible_es_transcode_audio(self):
        """
        Radio (sin video) con audio incompatible (aac_latm/mp2) ->
        transcode_audio: convierte el audio a AAC SIN forzar libx264 sobre
        un stream que no tiene video (antes caía en transcode y FFmpeg fallaba).
        """
        self.assertEqual(
            transcoder.mode_from_codecs(None, "aac_latm"), "transcode_audio"
        )
        self.assertEqual(
            transcoder.mode_from_codecs(None, "mp2"), "transcode_audio"
        )


# --- Día 9: endpoint de diagnóstico HLS por stream_id ---------------------

class HlsStatusHelperTests(SimpleTestCase):
    """transcoder.get_hls_status(): estado de la salida HLS en disco."""

    def test_sin_salida_reporta_vacio(self):
        """Sin carpeta/index -> index_exists False, 0 segmentos, no vivo."""
        tmp = Path(tempfile.mkdtemp())
        try:
            with override_settings(HLS_ROOT=tmp):
                data = transcoder.get_hls_status("777")

            self.assertEqual(data["stream_id"], "777")
            self.assertFalse(data["index_exists"])
            self.assertEqual(data["index_size_bytes"], 0)
            self.assertEqual(data["segments"], 0)
            self.assertFalse(data["process_alive"])
        finally:
            shutil.rmtree(tmp, ignore_errors=True)

    def test_con_salida_cuenta_segmentos(self):
        """Con index.m3u8 y .ts -> index_exists True, tamaño y segmentos > 0."""
        tmp = Path(tempfile.mkdtemp())
        try:
            folder = tmp / "778"
            folder.mkdir()
            (folder / "index.m3u8").write_text("#EXTM3U")
            (folder / "segment_000.ts").write_text("x")
            (folder / "segment_001.ts").write_text("y")

            with override_settings(HLS_ROOT=tmp):
                data = transcoder.get_hls_status("778")

            self.assertTrue(data["index_exists"])
            self.assertGreater(data["index_size_bytes"], 0)
            self.assertEqual(data["segments"], 2)
            self.assertFalse(data["damaged"])
        finally:
            shutil.rmtree(tmp, ignore_errors=True)

    def test_ready_true_con_segmentos_suficientes(self):
        """Con index + 2 segmentos (>= min) -> ready True y min_segments_required."""
        tmp = Path(tempfile.mkdtemp())
        try:
            folder = tmp / "779"
            folder.mkdir()
            (folder / "index.m3u8").write_text("#EXTM3U")
            (folder / "segment_000.ts").write_text("x")
            (folder / "segment_001.ts").write_text("y")

            with override_settings(HLS_ROOT=tmp, HLS_MIN_SEGMENTS=2):
                data = transcoder.get_hls_status("779")

            self.assertEqual(data["min_segments_required"], 2)
            self.assertTrue(data["ready"])
        finally:
            shutil.rmtree(tmp, ignore_errors=True)

    def test_ready_false_con_pocos_segmentos(self):
        """Con index pero menos segmentos que el mínimo -> ready False."""
        tmp = Path(tempfile.mkdtemp())
        try:
            folder = tmp / "780"
            folder.mkdir()
            (folder / "index.m3u8").write_text("#EXTM3U")
            (folder / "segment_000.ts").write_text("x")

            with override_settings(HLS_ROOT=tmp, HLS_MIN_SEGMENTS=2):
                data = transcoder.get_hls_status("780")

            self.assertEqual(data["segments"], 1)
            self.assertFalse(data["ready"])
        finally:
            shutil.rmtree(tmp, ignore_errors=True)


# --- Día 11: distinguir HLS "listo" de HLS "vivo" -------------------------

class ProcesoFalso:
    """
    Doble de subprocess.Popen. poll() devuelve None si el proceso sigue
    corriendo, o un returncode si ya terminó.

    terminate()/wait()/kill() permiten usarlo con stop_hls_transcode(), que
    apaga de verdad el proceso; ``terminado`` deja constancia de que se pidió
    la parada.
    """

    def __init__(self, returncode=None):
        self.returncode = returncode
        self.terminado = False

    def poll(self):
        return self.returncode

    def terminate(self):
        self.terminado = True
        self.returncode = 0

    def wait(self, timeout=None):
        return self.returncode

    def kill(self):
        self.terminate()


def _montar_salida_hls(root, stream_id, segmentos=7, edad_index=0.0):
    """
    Crea una salida HLS en disco y envejece el index.m3u8 ``edad_index``
    segundos, para simular "FFmpeg dejó de escribir hace N segundos".
    """
    folder = Path(root) / stream_id
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "index.m3u8").write_text("#EXTM3U\n#EXT-X-VERSION:3\n")
    for i in range(segmentos):
        (folder / f"segment_{i:03d}.ts").write_text("x")

    if edad_index:
        marca = time.time() - edad_index
        os.utime(folder / "index.m3u8", (marca, marca))
    return folder


class OutputLiveTests(SimpleTestCase):
    """
    transcoder.is_output_live(): decide por la antigüedad del index.m3u8,
    NO por el registro _processes (que se pierde al reiniciar Django).
    """

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        transcoder._processes.clear()
        self.addCleanup(transcoder._processes.clear)

    def test_live_true_con_index_fresco(self):
        """Index reescrito hace 2s -> algo lo está escribiendo: live True."""
        _montar_salida_hls(self.tmp, "800", edad_index=2)

        with override_settings(HLS_ROOT=self.tmp, HLS_ACTIVE_TTL_SECONDS=10):
            self.assertTrue(transcoder.is_output_live("800"))

    def test_live_false_con_index_viejo(self):
        """Index sin tocarse hace 45s -> nadie produce: live False."""
        _montar_salida_hls(self.tmp, "801", edad_index=45)

        with override_settings(HLS_ROOT=self.tmp, HLS_ACTIVE_TTL_SECONDS=10):
            self.assertFalse(transcoder.is_output_live("801"))

    def test_live_false_sin_salida(self):
        """Sin carpeta ni index -> no hay nada vivo."""
        with override_settings(HLS_ROOT=self.tmp, HLS_ACTIVE_TTL_SECONDS=10):
            self.assertFalse(transcoder.is_output_live("802"))

    def test_live_false_si_salida_danada(self):
        """Index fresco pero sin segmentos (playlist rota) -> live False."""
        folder = self.tmp / "803"
        folder.mkdir()
        (folder / "index.m3u8").write_text("#EXTM3U")  # sin .ts

        with override_settings(HLS_ROOT=self.tmp, HLS_ACTIVE_TTL_SECONDS=10):
            self.assertFalse(transcoder.is_output_live("803"))

    def test_live_no_depende_del_registro_de_procesos(self):
        """
        Django reinició y _processes quedó vacío, pero FFmpeg sigue vivo y
        refrescando el index. live debe seguir siendo True aunque
        process_alive sea False: si no, se mataría un proceso sano.
        """
        _montar_salida_hls(self.tmp, "804", edad_index=1)

        with override_settings(HLS_ROOT=self.tmp, HLS_ACTIVE_TTL_SECONDS=10):
            data = transcoder.get_hls_status("804")

        self.assertFalse(data["process_alive"])  # registro vacío
        self.assertTrue(data["live"])            # el disco dice que sí

    def test_index_age_seconds_refleja_antiguedad(self):
        """index_age_seconds mide los segundos desde la última escritura."""
        _montar_salida_hls(self.tmp, "805", edad_index=20)

        with override_settings(HLS_ROOT=self.tmp):
            edad = transcoder.get_index_age_seconds("805")

        self.assertAlmostEqual(edad, 20, delta=2)

    def test_index_age_seconds_none_sin_index(self):
        """Sin index.m3u8 no hay antigüedad que medir -> None."""
        with override_settings(HLS_ROOT=self.tmp):
            self.assertIsNone(transcoder.get_index_age_seconds("806"))

    def test_caso_rpp_ready_true_pero_live_false(self):
        """
        Caso RPP (stream_id 65) reportado por Joleydi: index y 7 segmentos en
        disco, FFmpeg muerto. La salida es reproducible (ready=True) pero está
        congelada (live=False): el player agota los segmentos y se detiene.

        Este es el escenario que hls-status debe permitir distinguir.
        """
        _montar_salida_hls(self.tmp, "65", segmentos=7, edad_index=45)
        transcoder._processes["65"] = ProcesoFalso(returncode=1)  # murió

        with override_settings(
            HLS_ROOT=self.tmp, HLS_ACTIVE_TTL_SECONDS=10, HLS_MIN_SEGMENTS=2
        ):
            data = transcoder.get_hls_status("65")

        self.assertEqual(data["segments"], 7)
        self.assertFalse(data["damaged"])
        self.assertFalse(data["process_alive"])
        self.assertTrue(data["ready"])   # hay contenido reproducible...
        self.assertFalse(data["live"])   # ...pero ya no se renueva
        self.assertGreater(data["index_age_seconds"], 10)
        self.assertEqual(data["live_max_age_seconds"], 10)


class WaitForHlsReadyTests(SimpleTestCase):
    """
    transcoder.wait_for_hls_ready(): la espera completa que exige index +
    segmentos suficientes antes de dar el HLS por listo (Día 10).

    Se trabaja sobre una carpeta temporal (HLS_ROOT) y sin proceso FFmpeg
    registrado, por lo que los casos "no listos" agotan el timeout corto.
    """

    def _make_output(self, tmp, stream_id, index_content="#EXTM3U", segments=0):
        folder = tmp / stream_id
        folder.mkdir()
        (folder / "index.m3u8").write_text(index_content)
        for i in range(segments):
            (folder / f"segment_{i:03d}.ts").write_text("x")
        return folder

    def test_false_si_no_existe_index(self):
        tmp = Path(tempfile.mkdtemp())
        try:
            with override_settings(HLS_ROOT=tmp):
                listo = transcoder.wait_for_hls_ready(
                    "800", timeout_seconds=1, min_segments=2
                )
            self.assertFalse(listo)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)

    def test_false_si_index_vacio(self):
        tmp = Path(tempfile.mkdtemp())
        try:
            self._make_output(tmp, "801", index_content="", segments=2)
            with override_settings(HLS_ROOT=tmp):
                listo = transcoder.wait_for_hls_ready(
                    "801", timeout_seconds=1, min_segments=2
                )
            self.assertFalse(listo)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)

    def test_false_si_no_hay_segmentos(self):
        tmp = Path(tempfile.mkdtemp())
        try:
            self._make_output(tmp, "802", segments=0)
            with override_settings(HLS_ROOT=tmp):
                listo = transcoder.wait_for_hls_ready(
                    "802", timeout_seconds=1, min_segments=2
                )
            self.assertFalse(listo)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)

    def test_false_si_menos_segmentos_que_el_minimo(self):
        tmp = Path(tempfile.mkdtemp())
        try:
            self._make_output(tmp, "803", segments=1)
            with override_settings(HLS_ROOT=tmp):
                listo = transcoder.wait_for_hls_ready(
                    "803", timeout_seconds=1, min_segments=2
                )
            self.assertFalse(listo)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)

    def test_true_si_index_y_segmentos_suficientes(self):
        tmp = Path(tempfile.mkdtemp())
        try:
            self._make_output(tmp, "804", segments=2)
            with override_settings(HLS_ROOT=tmp):
                listo = transcoder.wait_for_hls_ready(
                    "804", timeout_seconds=2, min_segments=2
                )
            self.assertTrue(listo)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)


class LiveHlsStatusEndpointTests(APITestCase):
    """GET /api/xtream/live/hls-status/<stream_id>/."""

    def test_stream_id_invalido_devuelve_400(self):
        url = reverse("live_hls_status", args=["bad.id"])
        response = self.client.get(url)

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data["error_code"], "invalid_stream_id")

    @patch("xtream.views.transcoder.get_hls_status")
    def test_devuelve_estado_hls(self, mock_status):
        mock_status.return_value = {
            "stream_id": "71",
            "index_exists": True,
            "index_size_bytes": 273,
            "segments": 6,
            "damaged": False,
            "process_alive": True,
        }

        url = reverse("live_hls_status", args=["71"])
        response = self.client.get(url)

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data["success"])
        self.assertEqual(response.data["stream_id"], "71")
        self.assertTrue(response.data["index_exists"])
        self.assertEqual(response.data["segments"], 6)
        self.assertTrue(response.data["process_alive"])

    def test_solo_acepta_get(self):
        url = reverse("live_hls_status", args=["71"])
        response = self.client.post(url, {}, format="json")

        self.assertEqual(
            response.status_code, status.HTTP_405_METHOD_NOT_ALLOWED
        )


# --- recuperación automática de HLS muerto ------------------------

class IsStreamActiveRecoveryTests(SimpleTestCase):
    """
    transcoder.is_stream_active(): reutiliza el HLS vivo y fuerza la
    regeneración del muerto/dañado.
    """

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        transcoder._processes.clear()
        self.addCleanup(transcoder._processes.clear)

    def test_activo_si_proceso_vivo(self):
        """process_alive=True -> activo, aunque el index esté viejo."""
        _montar_salida_hls(self.tmp, "900", segmentos=7, edad_index=999)
        transcoder._processes["900"] = ProcesoFalso(returncode=None)  # vivo

        with override_settings(HLS_ROOT=self.tmp, HLS_ACTIVE_TTL_SECONDS=10):
            self.assertTrue(transcoder.is_stream_active("900"))

    def test_activo_si_proceso_muerto_pero_live(self):
        """
        Sin proceso registrado (Django reinició) pero index fresco: la salida
        sigue viva (live=True) y debe reutilizarse.
        """
        _montar_salida_hls(self.tmp, "901", segmentos=7, edad_index=2)

        with override_settings(HLS_ROOT=self.tmp, HLS_ACTIVE_TTL_SECONDS=10):
            self.assertTrue(transcoder.is_stream_active("901"))

    def test_limpia_y_regenera_si_ready_pero_muerto(self):
        """
        ready=True + live=False (caso RPP): NO se reutiliza. Se limpia el
        proceso zombie y la carpeta para forzar regeneración.
        """
        folder = _montar_salida_hls(self.tmp, "902", segmentos=7, edad_index=45)
        transcoder._processes["902"] = ProcesoFalso(returncode=1)  # murió

        with override_settings(
            HLS_ROOT=self.tmp, HLS_ACTIVE_TTL_SECONDS=10, HLS_MIN_SEGMENTS=2
        ):
            self.assertFalse(transcoder.is_stream_active("902"))

        self.assertFalse(folder.exists())               # salida borrada
        self.assertNotIn("902", transcoder._processes)  # zombie removido

    def test_limpia_y_regenera_si_danado(self):
        """damaged=True (index con contenido pero sin .ts) -> limpiar."""
        folder = self.tmp / "903"
        folder.mkdir()
        (folder / "index.m3u8").write_text("#EXTM3U")  # sin segmentos

        with override_settings(HLS_ROOT=self.tmp, HLS_ACTIVE_TTL_SECONDS=10):
            self.assertFalse(transcoder.is_stream_active("903"))

        self.assertFalse(folder.exists())


class StartHlsRegeneraMuertoTests(SimpleTestCase):
    """
    start_hls_transcode() (lo que usa /proxy-url/) no reutiliza un HLS muerto:
    lo limpia y relanza FFmpeg (reused=False).
    """

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        transcoder._processes.clear()
        self.addCleanup(transcoder._processes.clear)

    @patch("xtream.services.transcoder.ensure_cleanup_thread")
    @patch("xtream.services.transcoder.subprocess.Popen")
    @patch("xtream.services.transcoder.decide_mode", return_value="transcode")
    @patch("xtream.services.transcoder.is_ffmpeg_available", return_value=True)
    def test_proxy_no_reutiliza_hls_muerto_y_relanza(
        self, _mock_ffmpeg, _mock_mode, mock_popen, _mock_cleanup
    ):
        _montar_salida_hls(self.tmp, "904-mobile", segmentos=7, edad_index=45)
        transcoder._processes["904-mobile"] = ProcesoFalso(returncode=1)  # muerto
        mock_popen.return_value = ProcesoFalso(returncode=None)     # nuevo vivo

        with override_settings(
            HLS_ROOT=self.tmp,
            HLS_ACTIVE_TTL_SECONDS=10,
            HLS_MIN_SEGMENTS=2,
            MAX_CONCURRENT_TRANSCODES=5,
        ):
            sid, reused, mode = transcoder.start_hls_transcode(
                "http://servidor/live/u/p/904.ts", "904"
            )

        self.assertEqual(sid, "904-mobile")
        self.assertFalse(reused)          # no reutilizó el HLS muerto
        self.assertEqual(mode, "transcode")
        mock_popen.assert_called_once()   # relanzó FFmpeg


class RecoveryRequiredStatusTests(SimpleTestCase):
    """get_hls_status(): campo recovery_required."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        transcoder._processes.clear()
        self.addCleanup(transcoder._processes.clear)

    def test_recovery_required_true_si_ready_y_no_live(self):
        """ready=True + live=False -> recovery_required=True."""
        _montar_salida_hls(self.tmp, "905", segmentos=7, edad_index=45)

        with override_settings(
            HLS_ROOT=self.tmp, HLS_ACTIVE_TTL_SECONDS=10, HLS_MIN_SEGMENTS=2
        ):
            data = transcoder.get_hls_status("905")

        self.assertTrue(data["ready"])
        self.assertFalse(data["live"])
        self.assertTrue(data["recovery_required"])

    def test_recovery_required_false_si_live(self):
        """Salida viva (live=True) -> no requiere recuperación."""
        _montar_salida_hls(self.tmp, "906", segmentos=7, edad_index=2)

        with override_settings(
            HLS_ROOT=self.tmp, HLS_ACTIVE_TTL_SECONDS=10, HLS_MIN_SEGMENTS=2
        ):
            data = transcoder.get_hls_status("906")

        self.assertTrue(data["live"])
        self.assertFalse(data["recovery_required"])


class LiveProxyUrlRecoveryEndpointTests(APITestCase):
    """
    Endpoint POST /api/xtream/live/proxy-url/ frente a una salida MUERTA.

    Confirmación literal del entregable Día 12: "/proxy-url/ regenera cuando
    live=False". Se monta un HLS muerto (ready=True + live=False) en disco con
    un proceso zombie y se golpea el endpoint real; debe NO reutilizar, relanzar
    FFmpeg y responder reused=False con una hls_url nueva.
    """

    def setUp(self):
        self.url = reverse("live_proxy_url")
        self.payload = {
            "username": "cliente.demo",
            "password": "cualquiera",
            "stream_id": "65",
        }
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        transcoder._processes.clear()
        self.addCleanup(transcoder._processes.clear)

    @patch("xtream.views.transcoder.wait_for_hls_ready", return_value=True)
    @patch("xtream.services.transcoder.ensure_cleanup_thread")
    @patch("xtream.services.transcoder.subprocess.Popen")
    @patch("xtream.services.transcoder.decide_mode", return_value="transcode")
    @patch("xtream.services.transcoder.is_ffmpeg_available", return_value=True)
    @patch("xtream.views.XtreamClient")
    def test_proxy_url_regenera_si_live_false(
        self, mock_client, _mock_ffmpeg, _mock_mode, mock_popen,
        _mock_cleanup, _mock_wait,
    ):
        # HLS muerto en disco (ready=True + live=False) + proceso zombie.
        _montar_salida_hls(self.tmp, "65-mobile", segmentos=7, edad_index=45)
        transcoder._processes["65-mobile"] = ProcesoFalso(returncode=1)
        mock_popen.return_value = ProcesoFalso(returncode=None)  # FFmpeg nuevo
        mock_client.return_value.build_live_stream_url.return_value = (
            "http://servidor/live/cliente.demo/cualquiera/65.ts"
        )

        with override_settings(
            HLS_ROOT=self.tmp,
            HLS_ACTIVE_TTL_SECONDS=10,
            HLS_MIN_SEGMENTS=2,
            MAX_CONCURRENT_TRANSCODES=5,
        ):
            response = self.client.post(self.url, self.payload, format="json")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data["success"])
        self.assertFalse(response.data["reused"])    # NO reutilizó el muerto
        self.assertEqual(response.data["mode"], "transcode")
        self.assertEqual(response.data["stream_id"], "65")
        self.assertIn("hls/65-mobile/index.m3u8", response.data["hls_url"])
        mock_popen.assert_called_once()              # relanzó FFmpeg


class ProcessUptimeTests(SimpleTestCase):
    """
    get_hls_status(): campo uptime_seconds / uptime_minutes (cuánto lleva
    corriendo el proceso FFmpeg del canal).
    """

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        transcoder._processes.clear()
        transcoder._process_started_at.clear()
        self.addCleanup(transcoder._processes.clear)
        self.addCleanup(transcoder._process_started_at.clear)

    def test_uptime_none_sin_proceso(self):
        """Sin proceso registrado -> uptime None (aunque la salida esté viva)."""
        _montar_salida_hls(self.tmp, "910", segmentos=7, edad_index=2)

        with override_settings(
            HLS_ROOT=self.tmp, HLS_ACTIVE_TTL_SECONDS=10, HLS_MIN_SEGMENTS=2
        ):
            data = transcoder.get_hls_status("910")

        self.assertIsNone(data["uptime_seconds"])
        self.assertIsNone(data["uptime_minutes"])

    def test_uptime_cuenta_desde_el_arranque(self):
        """Proceso vivo lanzado hace 120s -> uptime ~120s / ~2.0 min."""
        _montar_salida_hls(self.tmp, "911", segmentos=7, edad_index=2)
        transcoder._processes["911"] = ProcesoFalso(returncode=None)  # vivo
        transcoder._process_started_at["911"] = time.time() - 120

        with override_settings(
            HLS_ROOT=self.tmp, HLS_ACTIVE_TTL_SECONDS=10, HLS_MIN_SEGMENTS=2
        ):
            data = transcoder.get_hls_status("911")

        self.assertAlmostEqual(data["uptime_seconds"], 120, delta=2)
        self.assertAlmostEqual(data["uptime_minutes"], 2.0, delta=0.1)

    def test_uptime_none_si_proceso_murio(self):
        """Proceso ya terminado -> uptime None (dejó de correr con normalidad)."""
        _montar_salida_hls(self.tmp, "912", segmentos=7, edad_index=2)
        transcoder._processes["912"] = ProcesoFalso(returncode=1)  # murió
        transcoder._process_started_at["912"] = time.time() - 60

        with override_settings(
            HLS_ROOT=self.tmp, HLS_ACTIVE_TTL_SECONDS=10, HLS_MIN_SEGMENTS=2
        ):
            data = transcoder.get_hls_status("912")

        self.assertIsNone(data["uptime_seconds"])


# --- Aislamiento de la salida HLS por device_profile ----------------------
# Regla que se valida aquí: la identidad de una salida HLS es la pareja
# (stream_id, device_profile), NO el stream_id suelto. Antes de esta
# separación, una TV que pedía el canal 123 reutilizaba el HLS 720p30 que
# había dejado un celular y nunca recibía su perfil.

class OutputKeyTests(SimpleTestCase):
    """build_output_key() / split_output_key(): construcción y lectura."""

    def test_key_incluye_el_perfil(self):
        self.assertEqual(transcoder.build_output_key("123", "mobile"), "123-mobile")
        self.assertEqual(transcoder.build_output_key("123", "tv"), "123-tv")
        self.assertEqual(transcoder.build_output_key("123", "web"), "123-web")

    def test_perfiles_distintos_dan_claves_distintas(self):
        """El mismo stream_id con perfiles distintos NUNCA colisiona."""
        claves = {
            transcoder.build_output_key("123", perfil)
            for perfil in ("mobile", "tv", "web")
        }
        self.assertEqual(len(claves), 3)

    def test_sin_perfil_usa_mobile(self):
        """Default mobile: la app móvil actual no envía device_profile."""
        self.assertEqual(transcoder.build_output_key("123"), "123-mobile")
        self.assertEqual(transcoder.build_output_key("123", None), "123-mobile")
        self.assertEqual(transcoder.build_output_key("123", ""), "123-mobile")

    def test_perfil_invalido_lanza_valueerror(self):
        with self.assertRaises(ValueError):
            transcoder.build_output_key("123", "playstation")

    def test_stream_id_peligroso_lanza_valueerror(self):
        """La clave no puede abrir la puerta a path traversal."""
        with self.assertRaises(ValueError):
            transcoder.build_output_key("../../etc", "tv")

    def test_split_devuelve_stream_id_y_perfil(self):
        self.assertEqual(transcoder.split_output_key("123-tv"), ("123", "tv"))

    def test_split_respeta_stream_id_con_guiones(self):
        """El corte es por el ULTIMO guion y solo si el sufijo es un perfil."""
        self.assertEqual(
            transcoder.split_output_key("canal-01-tv"), ("canal-01", "tv")
        )

    def test_split_sin_sufijo_de_perfil_devuelve_none(self):
        """Carpeta antigua sin perfil -> device_profile None, no un invento."""
        self.assertEqual(transcoder.split_output_key("canal-01"), ("canal-01", None))


class HlsAislamientoPorPerfilTests(SimpleTestCase):
    """
    start_hls_transcode(): la reutilización se evalúa por (stream_id, perfil).

    Se mockea FFmpeg (Popen / is_ffmpeg_available / decide_mode) para no
    depender de binarios ni de streams reales.
    """

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        transcoder._processes.clear()
        self.addCleanup(transcoder._processes.clear)
        self.addCleanup(transcoder._process_started_at.clear)
        self.addCleanup(transcoder._process_profile.clear)

    def _override(self):
        return override_settings(
            HLS_ROOT=self.tmp,
            HLS_ACTIVE_TTL_SECONDS=10,
            HLS_MIN_SEGMENTS=2,
            MAX_CONCURRENT_TRANSCODES=5,
        )

    @patch("xtream.services.transcoder.ensure_cleanup_thread")
    @patch("xtream.services.transcoder.subprocess.Popen")
    @patch("xtream.services.transcoder.decide_mode", return_value="transcode")
    @patch("xtream.services.transcoder.is_ffmpeg_available", return_value=True)
    def test_tv_no_reutiliza_el_hls_de_mobile(
        self, _mock_ffmpeg, _mock_mode, mock_popen, _mock_cleanup
    ):
        """
        EL BUG DEL DIA: con un HLS mobile VIVO para el canal 123, la TV pide el
        mismo canal. Debe lanzar su propio FFmpeg (reused=False) y no heredar
        la salida móvil 720p30.
        """
        _montar_salida_hls(self.tmp, "123-mobile", segmentos=7, edad_index=0)
        transcoder._processes["123-mobile"] = ProcesoFalso(returncode=None)  # vivo
        mock_popen.return_value = ProcesoFalso(returncode=None)

        with self._override():
            key, reused, mode = transcoder.start_hls_transcode(
                "http://servidor/live/u/p/123.ts", "123", device_profile="tv"
            )

        self.assertEqual(key, "123-tv")
        self.assertFalse(reused)           # NO heredó la salida de mobile
        self.assertEqual(mode, "transcode")
        mock_popen.assert_called_once()    # lanzó su propio FFmpeg

    @patch("xtream.services.transcoder.ensure_cleanup_thread")
    @patch("xtream.services.transcoder.subprocess.Popen")
    @patch("xtream.services.transcoder.decide_mode", return_value="remux")
    @patch("xtream.services.transcoder.is_ffmpeg_available", return_value=True)
    def test_mismo_stream_y_mismo_perfil_si_reutiliza(
        self, _mock_ffmpeg, _mock_mode, mock_popen, _mock_cleanup
    ):
        """Dos peticiones idénticas (canal + perfil) comparten un solo FFmpeg."""
        _montar_salida_hls(self.tmp, "123-tv", segmentos=7, edad_index=0)
        transcoder._processes["123-tv"] = ProcesoFalso(returncode=None)  # vivo

        with self._override():
            key, reused, mode = transcoder.start_hls_transcode(
                "http://servidor/live/u/p/123.ts", "123", device_profile="tv"
            )

        self.assertEqual(key, "123-tv")
        self.assertTrue(reused)            # reutiliza: no duplica procesos
        self.assertIsNone(mode)            # no se vuelve a decidir el modo
        mock_popen.assert_not_called()

    @patch("xtream.services.transcoder.ensure_cleanup_thread")
    @patch("xtream.services.transcoder.subprocess.Popen")
    @patch("xtream.services.transcoder.decide_mode", return_value="transcode")
    @patch("xtream.services.transcoder.is_ffmpeg_available", return_value=True)
    def test_cada_perfil_escribe_en_su_propia_carpeta(
        self, _mock_ffmpeg, _mock_mode, mock_popen, _mock_cleanup
    ):
        """Los tres perfiles del mismo canal conviven en disco sin pisarse."""
        mock_popen.return_value = ProcesoFalso(returncode=None)

        with self._override():
            for perfil in ("mobile", "tv", "web"):
                transcoder.start_hls_transcode(
                    "http://servidor/live/u/p/123.ts", "123", device_profile=perfil
                )

        for perfil in ("mobile", "tv", "web"):
            self.assertTrue(
                (self.tmp / f"123-{perfil}").is_dir(),
                f"falta la carpeta HLS del perfil {perfil}",
            )
        self.assertEqual(mock_popen.call_count, 3)  # un FFmpeg por perfil

    @patch("xtream.services.transcoder.ensure_cleanup_thread")
    @patch("xtream.services.transcoder.subprocess.Popen")
    @patch("xtream.services.transcoder.decide_mode", return_value="transcode")
    @patch("xtream.services.transcoder.is_ffmpeg_available", return_value=True)
    def test_perfil_invalido_lanza_error_controlado(
        self, _mock_ffmpeg, _mock_mode, mock_popen, _mock_cleanup
    ):
        """Un perfil desconocido no lanza FFmpeg: se corta antes con ValueError."""
        with self._override(), self.assertRaises(ValueError):
            transcoder.start_hls_transcode(
                "http://servidor/live/u/p/123.ts", "123",
                device_profile="playstation",
            )

        mock_popen.assert_not_called()

    def test_detener_un_perfil_no_afecta_al_otro(self):
        """stop/remove de la salida TV deja intacta la del celular."""
        _montar_salida_hls(self.tmp, "123-mobile", segmentos=7)
        _montar_salida_hls(self.tmp, "123-tv", segmentos=7)
        proceso_mobile = ProcesoFalso(returncode=None)
        transcoder._processes["123-mobile"] = proceso_mobile
        transcoder._processes["123-tv"] = ProcesoFalso(returncode=None)

        with self._override():
            self.assertTrue(transcoder.stop_hls_transcode("123-tv"))
            self.assertTrue(transcoder.remove_hls_output("123-tv"))

        self.assertFalse((self.tmp / "123-tv").exists())
        self.assertTrue((self.tmp / "123-mobile").is_dir())
        self.assertIs(transcoder._processes.get("123-mobile"), proceso_mobile)
        self.assertFalse(proceso_mobile.terminado)  # su FFmpeg sigue vivo

    def test_status_reporta_el_perfil_de_la_salida(self):
        """get_hls_status() informa a qué device_profile pertenece la salida."""
        _montar_salida_hls(self.tmp, "123-tv", segmentos=7)

        with self._override():
            data = transcoder.get_hls_status("123-tv")

        self.assertEqual(data["stream_id"], "123")
        self.assertEqual(data["device_profile"], "tv")
        self.assertTrue(data["ready"])

    def test_status_reporta_perfil_sin_registro_en_memoria(self):
        """
        El perfil sale de la CLAVE, no del registro en memoria: sigue siendo
        correcto tras reiniciar Django (cuando _processes queda vacío).
        """
        _montar_salida_hls(self.tmp, "123-web", segmentos=7)
        transcoder._processes.clear()
        transcoder._process_profile.clear()

        with self._override():
            data = transcoder.get_hls_status("123-web")

        self.assertEqual(data["device_profile"], "web")
        self.assertFalse(data["process_alive"])

    def test_monitoreo_lista_cada_perfil_por_separado(self):
        """get_transcoder_status() distingue las salidas por perfil."""
        _montar_salida_hls(self.tmp, "123-mobile", segmentos=7)
        _montar_salida_hls(self.tmp, "123-tv", segmentos=7)

        with self._override():
            data = transcoder.get_transcoder_status()

        perfiles = {
            (o["stream_id"], o["device_profile"]) for o in data["outputs"]
        }
        self.assertEqual(perfiles, {("123", "mobile"), ("123", "tv")})

    def test_cleanup_sigue_limpiando_con_claves_por_perfil(self):
        """
        La limpieza automática recorre HLS_ROOT a UN nivel; con la convención
        plana "123-tv" sigue encontrando y borrando las salidas inactivas.
        """
        _montar_salida_hls(self.tmp, "123-tv", segmentos=7, edad_index=9999)
        _montar_salida_hls(self.tmp, "123-mobile", segmentos=7, edad_index=0)

        with override_settings(HLS_ROOT=self.tmp, HLS_CLEANUP_TTL_SECONDS=300):
            limpiados = transcoder.cleanup_inactive()

        self.assertEqual(limpiados, ["123-tv"])       # inactiva: borrada
        self.assertFalse((self.tmp / "123-tv").exists())
        self.assertTrue((self.tmp / "123-mobile").is_dir())  # fresca: intacta


class ProxyUrlPerfilesEndpointTests(APITestCase):
    """
    Prueba manual mínima del plan, automatizada: tres POST a /proxy-url/ con
    el MISMO stream_id cambiando solo device_profile deben devolver tres
    hls_url distintas.
    """

    def setUp(self):
        self.url = reverse("live_proxy_url")
        self.payload = {
            "username": "cliente.demo",
            "password": "cualquiera",
            "stream_id": "123",
        }

    @patch("xtream.views.transcoder.wait_for_hls_ready", return_value=True)
    @patch("xtream.views.transcoder.start_hls_transcode")
    def test_tres_perfiles_devuelven_tres_urls_distintas(
        self, mock_start, _mock_wait
    ):
        urls = {}
        for perfil in ("mobile", "tv", "web"):
            mock_start.return_value = (f"123-{perfil}", False, "transcode")
            response = self.client.post(
                self.url, dict(self.payload, device_profile=perfil), format="json"
            )

            self.assertEqual(response.status_code, status.HTTP_200_OK)
            self.assertEqual(response.data["device_profile"], perfil)
            self.assertEqual(response.data["stream_id"], "123")
            self.assertIn(f"hls/123-{perfil}/index.m3u8", response.data["hls_url"])
            urls[perfil] = response.data["hls_url"]

        self.assertEqual(len(set(urls.values())), 3, f"URLs cruzadas: {urls}")

    @patch("xtream.views.transcoder.wait_for_hls_ready", return_value=True)
    @patch("xtream.views.transcoder.start_hls_transcode")
    def test_sin_device_profile_la_url_es_la_de_mobile(
        self, mock_start, _mock_wait
    ):
        """Compatibilidad: la app móvil actual no envía device_profile."""
        mock_start.return_value = ("123-mobile", False, "remux")

        response = self.client.post(self.url, self.payload, format="json")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["device_profile"], "mobile")
        self.assertIn("hls/123-mobile/index.m3u8", response.data["hls_url"])

    @patch("xtream.views.transcoder.wait_for_hls_ready", return_value=True)
    @patch("xtream.views.transcoder.start_hls_transcode")
    def test_reused_true_con_el_mismo_perfil(self, mock_start, _mock_wait):
        """El contrato conserva reused para el mismo canal + mismo perfil."""
        mock_start.return_value = ("123-tv", True, None)

        response = self.client.post(
            self.url, dict(self.payload, device_profile="tv"), format="json"
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data["reused"])
        self.assertEqual(response.data["device_profile"], "tv")
        self.assertIn("hls/123-tv/index.m3u8", response.data["hls_url"])


class StopProxyPerfilTests(APITestCase):
    """POST /stop-proxy/ limpia la salida del perfil indicado, no todas."""

    def setUp(self):
        self.url = reverse("live_stop_proxy")

    @patch("xtream.views.transcoder.remove_hls_output", return_value=True)
    @patch("xtream.views.transcoder.stop_hls_transcode", return_value=True)
    def test_detiene_solo_el_perfil_pedido(self, mock_stop, mock_remove):
        response = self.client.post(
            self.url, {"stream_id": "123", "device_profile": "tv"}, format="json"
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["device_profile"], "tv")
        mock_stop.assert_called_once_with("123-tv")
        mock_remove.assert_called_once_with("123-tv")

    def test_perfil_invalido_devuelve_400(self):
        response = self.client.post(
            self.url,
            {"stream_id": "123", "device_profile": "playstation"},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data["error_code"], "invalid_device_profile")


class HlsStatusEndpointPerfilTests(APITestCase):
    """GET /hls-status/<stream_id>/?device_profile=... consulta por perfil."""

    @patch("xtream.views.transcoder.get_hls_status")
    def test_query_param_selecciona_la_salida_del_perfil(self, mock_status):
        mock_status.return_value = {"stream_id": "123", "device_profile": "tv"}
        url = reverse("live_hls_status", args=["123"])

        response = self.client.get(url, {"device_profile": "tv"})

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        mock_status.assert_called_once_with("123-tv")

    @patch("xtream.views.transcoder.get_hls_status")
    def test_sin_query_param_consulta_mobile(self, mock_status):
        mock_status.return_value = {"stream_id": "123", "device_profile": "mobile"}
        url = reverse("live_hls_status", args=["123"])

        response = self.client.get(url)

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        mock_status.assert_called_once_with("123-mobile")

    def test_perfil_invalido_devuelve_400(self):
        url = reverse("live_hls_status", args=["123"])

        response = self.client.get(url, {"device_profile": "playstation"})

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data["error_code"], "invalid_device_profile")
