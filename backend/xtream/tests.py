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

from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase


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
