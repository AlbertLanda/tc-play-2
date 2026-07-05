from rest_framework.decorators import api_view
from rest_framework.response import Response
from rest_framework import status

from .services.client import XtreamClient


@api_view(["POST"])
def xtream_login(request):
    username = request.data.get("username")
    password = request.data.get("password")

    if not username or not password:
        return Response(
            {"detail": "Usuario y contraseña son obligatorios."},
            status=status.HTTP_400_BAD_REQUEST
        )

    try:
        client = XtreamClient()
        data = client.authenticate(username, password)

        return Response({
            "success": True,
            "data": data
        })

    except Exception as error:
        return Response(
            {
                "success": False,
                "detail": "No se pudo validar el usuario en Xtream.",
                "error": str(error)
            },
            status=status.HTTP_502_BAD_GATEWAY
        )


@api_view(["POST"])
def live_categories(request):
    username = request.data.get("username")
    password = request.data.get("password")

    if not username or not password:
        return Response(
            {"detail": "Usuario y contraseña son obligatorios."},
            status=status.HTTP_400_BAD_REQUEST
        )

    try:
        client = XtreamClient()
        data = client.get_live_categories(username, password)

        return Response({
            "success": True,
            "data": data
        })

    except Exception as error:
        return Response(
            {
                "success": False,
                "detail": "No se pudieron obtener las categorías.",
                "error": str(error)
            },
            status=status.HTTP_502_BAD_GATEWAY
        )


@api_view(["POST"])
def live_streams(request):
    username = request.data.get("username")
    password = request.data.get("password")
    category_id = request.data.get("category_id")

    if not username or not password:
        return Response(
            {"detail": "Usuario y contraseña son obligatorios."},
            status=status.HTTP_400_BAD_REQUEST
        )

    try:
        client = XtreamClient()
        data = client.get_live_streams(username, password, category_id)

        return Response({
            "success": True,
            "data": data
        })

    except Exception as error:
        return Response(
            {
                "success": False,
                "detail": "No se pudieron obtener los canales.",
                "error": str(error)
            },
            status=status.HTTP_502_BAD_GATEWAY
        )
    
@api_view(["POST"])
def live_stream_url(request):
    username = request.data.get("username")
    password = request.data.get("password")
    stream_id = request.data.get("stream_id")
    output = request.data.get("output", "ts")

    if not username or not password or not stream_id:
        return Response(
            {"detail": "Usuario, contraseña y stream_id son obligatorios."},
            status=status.HTTP_400_BAD_REQUEST
        )

    try:
        client = XtreamClient()
        stream_url = client.build_live_stream_url(
            username=username,
            password=password,
            stream_id=stream_id,
            output=output
        )

        return Response({
            "success": True,
            "stream_url": stream_url
        })

    except Exception as error:
        return Response(
            {
                "success": False,
                "detail": "No se pudo construir la URL de reproducción.",
                "error": str(error)
            },
            status=status.HTTP_502_BAD_GATEWAY
        )