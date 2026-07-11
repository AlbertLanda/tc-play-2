from rest_framework.decorators import api_view
from rest_framework.response import Response
from rest_framework import status

from .services.playlist import get_astra_channels, AstraPlaylistError


@api_view(["GET"])
def astra_channels(request):
    """
    Devuelve los canales disponibles desde la playlist HLS de Astra,
    normalizados como JSON para que la web no consuma directamente la IP.
    """
    try:
        channels = get_astra_channels()

        return Response({
            "success": True,
            "count": len(channels),
            "channels": channels,
        })

    except AstraPlaylistError as error:
        return Response(
            {
                "success": False,
                "error_code": "astra_playlist_error",
                "message": str(error),
            },
            status=status.HTTP_502_BAD_GATEWAY,
        )

    except Exception:
        return Response(
            {
                "success": False,
                "error_code": "unexpected_error",
                "message": "Ocurrió un error inesperado al leer Astra.",
            },
            status=status.HTTP_500_INTERNAL_SERVER_ERROR,
        )