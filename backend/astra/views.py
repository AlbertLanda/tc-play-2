from rest_framework.decorators import api_view
from rest_framework.response import Response
from rest_framework import status

from .services.playlist import get_astra_channels, AstraPlaylistError
from xtream.services import transcoder


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


@api_view(["POST"])
def astra_proxy_url(request):
    """
    Recibe un channel_id de Astra, busca su URL real en la playlist y la pasa por
    FFmpeg para generar un HLS compatible con navegador.

    No expone la URL original de Astra al cliente.
    """
    channel_id = request.data.get("channel_id")

    if not channel_id:
        return Response(
            {
                "success": False,
                "error_code": "missing_channel_id",
                "message": "El campo channel_id es obligatorio.",
            },
            status=status.HTTP_400_BAD_REQUEST,
        )

    try:
        safe_channel_id = transcoder.sanitize_stream_id(channel_id)
    except ValueError:
        return Response(
            {
                "success": False,
                "error_code": "invalid_channel_id",
                "message": "El channel_id enviado no es válido.",
            },
            status=status.HTTP_400_BAD_REQUEST,
        )

    try:
        channels = get_astra_channels()
        channel = next(
            (item for item in channels if item.get("id") == safe_channel_id),
            None,
        )

        if channel is None:
            return Response(
                {
                    "success": False,
                    "error_code": "astra_channel_not_found",
                    "message": "No se encontró el canal solicitado en Astra.",
                },
                status=status.HTTP_404_NOT_FOUND,
            )

        stream_url = channel.get("url")

        if not stream_url:
            return Response(
                {
                    "success": False,
                    "error_code": "astra_stream_url_missing",
                    "message": "El canal de Astra no tiene una URL válida.",
                },
                status=status.HTTP_502_BAD_GATEWAY,
            )

        stream_id, reused, mode = transcoder.start_hls_transcode(
            stream_url=stream_url,
            stream_id=safe_channel_id,
            forced_mode="transcode",
        )

        if not reused and not transcoder.wait_for_hls_index(stream_id):
            transcoder.stop_hls_transcode(stream_id)

            return Response(
                {
                    "success": False,
                    "error_code": "hls_output_error",
                    "message": "FFmpeg inició, pero no generó la salida HLS para Astra.",
                },
                status=status.HTTP_500_INTERNAL_SERVER_ERROR,
            )

        return Response(
            {
                "success": True,
                "channel_id": safe_channel_id,
                "channel_name": channel.get("name"),
                "hls_url": transcoder.build_hls_url(request, stream_id),
                "mode": mode or "reused",
                "reused": reused,
                "source": "astra_proxy",
            }
        )

    except AstraPlaylistError as error:
        return Response(
            {
                "success": False,
                "error_code": "astra_playlist_error",
                "message": str(error),
            },
            status=status.HTTP_502_BAD_GATEWAY,
        )

    except transcoder.TranscoderError as error:
        return Response(
            {
                "success": False,
                "error_code": error.error_code,
                "message": str(error),
            },
            status=error.http_status,
        )

    except Exception:
        return Response(
            {
                "success": False,
                "error_code": "unexpected_error",
                "message": "Ocurrió un error inesperado al generar el proxy Astra.",
            },
            status=status.HTTP_500_INTERNAL_SERVER_ERROR,
        )