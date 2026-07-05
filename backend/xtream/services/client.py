import requests
from decouple import config


class XtreamClient:
    """
    Cliente base para consumir API compatible con Xtream.
    En esta primera etapa, Xtream seguirá gestionando usuarios,
    planes, bouquets, streams y vencimientos.
    """

    def __init__(self):
        self.base_url = config("XTREAM_BASE_URL", default="").rstrip("/")

    def get_player_api_url(self):
        return f"{self.base_url}/player_api.php"

    def authenticate(self, username: str, password: str):
        params = {
            "username": username,
            "password": password,
        }

        response = requests.get(
            self.get_player_api_url(),
            params=params,
            timeout=15
        )

        response.raise_for_status()
        return response.json()

    def get_live_categories(self, username: str, password: str):
        params = {
            "username": username,
            "password": password,
            "action": "get_live_categories",
        }

        response = requests.get(
            self.get_player_api_url(),
            params=params,
            timeout=15
        )

        response.raise_for_status()
        return response.json()

    def get_live_streams(self, username: str, password: str, category_id=None):
        params = {
            "username": username,
            "password": password,
            "action": "get_live_streams",
        }

        if category_id:
            params["category_id"] = category_id

        response = requests.get(
            self.get_player_api_url(),
            params=params,
            timeout=15
        )

        response.raise_for_status()
        return response.json()
    
    def build_live_stream_url(
        self,
        username: str,
        password: str,
        stream_id: str,
        output: str = "ts"
    ):
        """
        Construye la URL de reproducción para un canal en vivo.
        Formatos comunes: ts, m3u8, rtmp.
        """
        return f"{self.base_url}/live/{username}/{password}/{stream_id}.{output}"