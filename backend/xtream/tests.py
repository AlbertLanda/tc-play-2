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

    @patch("xtream.views.transcoder.wait_for_hls_index", return_value=True)
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

    @patch("xtream.views.transcoder.wait_for_hls_index", return_value=True)
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


class TranscoderModeTests(SimpleTestCase):
    """
    Pruebas de la decisión remux vs transcode según el códec del canal.
    Se mockea probe_codecs para no depender de ffprobe ni de un stream real.
    """

    @patch("xtream.services.transcoder.probe_codecs", return_value=("h264", "aac"))
    def test_remux_si_codec_compatible(self, _mock_probe):
        """h264 + aac -> remux (no hace falta transcodificar)."""
        self.assertEqual(transcoder.decide_mode("http://x"), "remux")

    @patch("xtream.services.transcoder.probe_codecs", return_value=("h264", "mp2"))
    def test_transcode_audio_si_solo_audio_incompatible(self, _mock_probe):
        """h264 + mp2 -> transcode_audio (video OK, solo se arregla el audio)."""
        self.assertEqual(transcoder.decide_mode("http://x"), "transcode_audio")

    @patch("xtream.services.transcoder.probe_codecs", return_value=("h264", None))
    def test_remux_si_video_ok_sin_audio(self, _mock_probe):
        """h264 sin audio detectado -> remux (no hay audio que arreglar)."""
        self.assertEqual(transcoder.decide_mode("http://x"), "remux")

    @patch("xtream.services.transcoder.probe_codecs", return_value=("hevc", "ac3"))
    def test_transcode_si_codec_incompatible(self, _mock_probe):
        """hevc / ac3 -> transcode (el navegador no soporta el video)."""
        self.assertEqual(transcoder.decide_mode("http://x"), "transcode")

    @patch("xtream.services.transcoder.probe_codecs", return_value=(None, None))
    def test_transcode_si_codec_desconocido(self, _mock_probe):
        """Si no se puede leer el códec -> transcode por seguridad."""
        self.assertEqual(transcoder.decide_mode("http://x"), "transcode")

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
