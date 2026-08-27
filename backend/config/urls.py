from django.conf import settings
from django.contrib import admin
from django.urls import include, path, re_path
from django.views.static import serve

urlpatterns = [
    path("admin/", admin.site.urls),
    path("api/core/", include("core.urls")),
    path("api/xtream/", include("xtream.urls")),
    path("api/astra/", include("astra.urls")),

    # Staging/Azure Docker:
    # Sirve archivos HLS generados dinámicamente por FFmpeg en MEDIA_ROOT.
    # Esto permite acceder a /media/hls/<stream_id>/index.m3u8 y segmentos .ts.
    re_path(
        r"^media/(?P<path>.*)$",
        serve,
        {"document_root": settings.MEDIA_ROOT},
    ),
]