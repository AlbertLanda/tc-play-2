"""
Pruebas del control de procesos del proxy/transcoder Astra (Día 7).

Cubren:
    - POST /api/astra/stop-proxy/  (validación, sanitización y detención)
    - GET  /api/astra/proxy-status/ (estado de procesos y salidas HLS)
    - Detección de salidas HLS dañadas en el transcoder.

No se lanza FFmpeg real: los procesos se simulan con mocks y las salidas
HLS se crean en una carpeta temporal.
"""

import shutil
import tempfile
from pathlib import Path
from unittest.mock import MagicMock, patch

from django.test import SimpleTestCase, override_settings

from xtream.services import transcoder


PROXY_URL = "/api/astra/proxy-url/"
STOP_PROXY_URL = "/api/astra/stop-proxy/"
PROXY_STATUS_URL = "/api/astra/proxy-status/"


class AstraStopProxyTests(SimpleTestCase):
    """Validación y comportamiento de POST /api/astra/stop-proxy/."""

    def _post(self, payload):
        return self.client.post(
            STOP_PROXY_URL, payload, content_type="application/json"
        )

    def test_channel_id_faltante_devuelve_400(self):
        response = self._post({})

        self.assertEqual(response.status_code, 400)
        self.assertEqual(
            response.json()["error_code"], "missing_channel_id"
        )

    def test_channel_id_invalido_devuelve_400(self):
        # Caracteres de path traversal no permitidos por sanitize_stream_id.
        response = self._post({"channel_id": "../../etc"})

        self.assertEqual(response.status_code, 400)
        self.assertEqual(
            response.json()["error_code"], "invalid_channel_id"
        )

    @patch("xtream.services.transcoder.remove_hls_output", return_value=True)
    @patch("xtream.services.transcoder.stop_hls_transcode", return_value=True)
    def test_detiene_proceso_existente(self, mock_stop, mock_remove):
        response = self._post({"channel_id": "astra-5"})

        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertTrue(data["success"])
        self.assertTrue(data["stopped"])
        self.assertTrue(data["output_removed"])
        self.assertEqual(data["channel_id"], "astra-5")
        # Astra tiene una única salida web y conserva su clave histórica.
        mock_stop.assert_called_once_with("astra-5")
        mock_remove.assert_called_once_with("astra-5")

    @patch("xtream.services.transcoder.remove_hls_output", return_value=False)
    @patch("xtream.services.transcoder.stop_hls_transcode", return_value=False)
    def test_sin_proceso_activo_responde_stopped_false(self, mock_stop, mock_remove):
        # Detener algo que no corre no es un error: se informa stopped false.
        response = self._post({"channel_id": "astra-99"})

        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertTrue(data["success"])
        self.assertFalse(data["stopped"])
        self.assertFalse(data["output_removed"])


class AstraProxyStatusTests(SimpleTestCase):
    """Comportamiento de GET /api/astra/proxy-status/."""

    @patch("xtream.services.transcoder.get_transcoder_status")
    def test_devuelve_estado_del_transcoder(self, mock_status):
        mock_status.return_value = {
            "active_processes": 2,
            "max_concurrent": 5,
            "outputs": [
                {
                    "stream_id": "astra-5",
                    "process_alive": True,
                    "index_exists": True,
                    "index_age_seconds": 2.0,
                    "index_size_bytes": 350,
                    "segments": 6,
                    "damaged": False,
                }
            ],
        }

        response = self.client.get(PROXY_STATUS_URL)

        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertTrue(data["success"])
        self.assertEqual(data["active_processes"], 2)
        self.assertEqual(data["max_concurrent"], 5)
        self.assertEqual(len(data["outputs"]), 1)
        self.assertEqual(data["outputs"][0]["stream_id"], "astra-5")

    def test_solo_acepta_get(self):
        response = self.client.post(
            PROXY_STATUS_URL, {}, content_type="application/json"
        )

        self.assertEqual(response.status_code, 405)


class TranscoderDamagedOutputTests(SimpleTestCase):
    """Detección y limpieza de salidas HLS dañadas en el transcoder."""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.hls_root = Path(self._tmp.name)
        self.addCleanup(self._tmp.cleanup)

    def _make_output(self, stream_id, index_content=b"", segments=0):
        folder = self.hls_root / stream_id
        folder.mkdir(parents=True)
        (folder / "index.m3u8").write_bytes(index_content)
        for n in range(segments):
            (folder / f"segment_{n:03d}.ts").write_bytes(b"x")
        return folder

    def test_index_vacio_se_detecta_como_danado(self):
        self._make_output("astra-1", index_content=b"", segments=3)

        with override_settings(HLS_ROOT=self.hls_root):
            self.assertTrue(transcoder.is_hls_output_damaged("astra-1"))

    def test_index_sin_segmentos_se_detecta_como_danado(self):
        self._make_output("astra-2", index_content=b"#EXTM3U", segments=0)

        with override_settings(HLS_ROOT=self.hls_root):
            self.assertTrue(transcoder.is_hls_output_damaged("astra-2"))

    def test_salida_sana_no_se_marca_danada(self):
        self._make_output("astra-3", index_content=b"#EXTM3U", segments=3)

        with override_settings(HLS_ROOT=self.hls_root):
            self.assertFalse(transcoder.is_hls_output_damaged("astra-3"))
            # Fresca y sana -> se reutiliza (no se relanza FFmpeg).
            self.assertTrue(transcoder.is_stream_active("astra-3"))

    def test_salida_danada_se_limpia_y_no_se_reutiliza(self):
        folder = self._make_output("astra-4", index_content=b"", segments=0)

        with override_settings(HLS_ROOT=self.hls_root):
            self.assertFalse(transcoder.is_stream_active("astra-4"))

        # is_stream_active debe haber borrado la carpeta dañada para que
        # el siguiente proxy-url regenere la salida desde cero.
        self.assertFalse(folder.exists())

    def test_get_transcoder_status_lista_salidas(self):
        self._make_output("astra-5", index_content=b"#EXTM3U", segments=6)

        with override_settings(HLS_ROOT=self.hls_root, MAX_CONCURRENT_TRANSCODES=5):
            status = transcoder.get_transcoder_status()

        self.assertEqual(status["max_concurrent"], 5)
        self.assertIsInstance(status["active_processes"], int)
        ids = [out["stream_id"] for out in status["outputs"]]
        self.assertIn("astra-5", ids)
        salida = next(o for o in status["outputs"] if o["stream_id"] == "astra-5")
        self.assertEqual(salida["segments"], 6)
        self.assertFalse(salida["damaged"])


class AstraProxyUrlTests(SimpleTestCase):
    """
    POST /api/astra/proxy-url/: el flujo principal de Astra.

    Astra conserva su ruta histórica y no expone device_profile en su
    contrato público.
    """

    def _post(self, payload):
        return self.client.post(
            PROXY_URL, payload, content_type="application/json"
        )

    def _canal(self):
        return [{"id": "astra-5", "name": "Canal 5", "url": "http://astra/5.ts"}]

    @patch("astra.views.transcoder.build_hls_url")
    @patch("astra.views.transcoder.wait_for_hls_index", return_value=True)
    @patch("astra.views.transcoder.start_hls_transcode")
    @patch("astra.views.get_astra_channels")
    def test_url_conserva_la_clave_historica(
        self, mock_channels, mock_start, mock_wait, mock_url
    ):
        """La espera y la URL siguen apuntando a /hls/astra-5/."""
        mock_channels.return_value = self._canal()
        mock_start.return_value = ("astra-5", False, "transcode")
        mock_url.return_value = "http://testserver/media/hls/astra-5/index.m3u8"

        response = self._post({"channel_id": "astra-5"})

        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertTrue(data["success"])
        self.assertEqual(data["channel_id"], "astra-5")
        self.assertIn("hls/astra-5/index.m3u8", data["hls_url"])
        # La espera y la URL se hacen sobre la CLAVE, no sobre el channel_id.
        mock_wait.assert_called_once_with("astra-5")
        self.assertEqual(mock_url.call_args.args[1], "astra-5")

    @patch("astra.views.transcoder.build_hls_url")
    @patch("astra.views.transcoder.wait_for_hls_index", return_value=True)
    @patch("astra.views.transcoder.start_hls_transcode")
    @patch("astra.views.get_astra_channels")
    def test_astra_pide_su_clave_sin_imponer_perfil(
        self, mock_channels, mock_start, _mock_wait, mock_url
    ):
        """
        Astra fija su clave de salida pero NO manda device_profile: así el
        transcoder aplica el default y sus parámetros de FFmpeg no cambian.
        """
        mock_channels.return_value = self._canal()
        mock_start.return_value = ("astra-5", False, "transcode")
        mock_url.return_value = "http://testserver/media/hls/astra-5/index.m3u8"

        self._post({"channel_id": "astra-5"})

        self.assertEqual(mock_start.call_args.kwargs["output_key"], "astra-5")
        self.assertNotIn("device_profile", mock_start.call_args.kwargs)

    @patch("astra.views.transcoder.stop_hls_transcode")
    @patch("astra.views.transcoder.wait_for_hls_index", return_value=False)
    @patch("astra.views.transcoder.start_hls_transcode")
    @patch("astra.views.get_astra_channels")
    def test_si_no_hay_salida_limpia_con_la_misma_clave(
        self, mock_channels, mock_start, _mock_wait, mock_stop
    ):
        """
        Si FFmpeg no generó el index, la limpieza debe apuntar a la MISMA
        clave que se lanzó; con el channel_id crudo quedaría un proceso vivo
        sin nadie que lo apague.
        """
        mock_channels.return_value = self._canal()
        mock_start.return_value = ("astra-5", False, "transcode")

        response = self._post({"channel_id": "astra-5"})

        self.assertEqual(response.status_code, 500)
        self.assertEqual(response.json()["error_code"], "hls_output_error")
        mock_stop.assert_called_once_with("astra-5")

    @patch("astra.views.get_astra_channels")
    def test_canal_inexistente_devuelve_404(self, mock_channels):
        mock_channels.return_value = self._canal()

        response = self._post({"channel_id": "noexiste"})

        self.assertEqual(response.status_code, 404)
        self.assertEqual(
            response.json()["error_code"], "astra_channel_not_found"
        )


class AstraProxyStatusClaveTests(SimpleTestCase):
    """El monitoreo de Astra conserva la clave histórica de la salida."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)

    def test_status_reporta_la_clave_astra_sin_sufijo(self):
        folder = self.tmp / "astra-5"
        folder.mkdir(parents=True)
        (folder / "index.m3u8").write_text("#EXTM3U\n")
        (folder / "segment_000.ts").write_text("x")

        with override_settings(HLS_ROOT=self.tmp):
            data = transcoder.get_transcoder_status()

        salida = data["outputs"][0]
        self.assertEqual(salida["output_key"], "astra-5")
        self.assertEqual(salida["stream_id"], "astra-5")
        self.assertIsNone(salida["device_profile"])


class AstraOutputKeyTests(SimpleTestCase):
    """
    Integración de la clave histórica de Astra con el transcoder.

    Sirve de guard de regresión: el aislamiento de perfiles cambió la clave de
    salida, pero NO debe cambiar cómo se codifica Astra.
    """

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        transcoder._processes.clear()
        transcoder._process_started_at.clear()
        transcoder._process_profile.clear()
        self.addCleanup(transcoder._processes.clear)
        self.addCleanup(transcoder._process_started_at.clear)
        self.addCleanup(transcoder._process_profile.clear)

    @patch("xtream.services.transcoder.ensure_cleanup_thread")
    @patch("xtream.services.transcoder.subprocess.Popen")
    @patch("xtream.services.transcoder.is_ffmpeg_available", return_value=True)
    def test_astra_conserva_su_clave_y_su_codificacion(
        self, _mock_ffmpeg, mock_popen, _mock_cleanup
    ):
        process = MagicMock()
        process.poll.return_value = None
        mock_popen.return_value = process

        # Mismos argumentos que usa astra_proxy_url: clave explícita y SIN
        # device_profile, para que aplique el default.
        with override_settings(HLS_ROOT=self.tmp, MAX_CONCURRENT_TRANSCODES=5):
            output_key, reused, mode = transcoder.start_hls_transcode(
                stream_url="http://astra/5.ts",
                stream_id="astra-5",
                forced_mode="transcode",
                output_key="astra-5",
            )

        # La salida sigue en /hls/astra-5/, sin sufijo de perfil.
        self.assertEqual(output_key, "astra-5")
        self.assertFalse(reused)
        self.assertEqual(mode, "transcode")
        self.assertTrue((self.tmp / "astra-5").is_dir())

        # Y se codifica igual que antes del aislamiento por perfiles: acotado
        # a 720p30 con bitrate con techo, no a resolución/FPS del origen.
        command = mock_popen.call_args.args[0]
        video_filters = command[command.index("-vf") + 1]
        self.assertIn("min(720,ih)", video_filters)
        self.assertIn("fps=30", video_filters)
        self.assertIn("2500k", command)
        self.assertNotIn("-crf", command)
