from django.contrib import admin
from django.urls import path, include
from django.conf import settings
from django.conf.urls.static import static

urlpatterns = [
    path("admin/", admin.site.urls),
    path("api/core/", include("core.urls")),
    path("api/xtream/", include("xtream.urls")),
]

# En desarrollo Django sirve los archivos de MEDIA_ROOT (incluye las salidas
# HLS del transcoder). En producción esto lo debe servir el servidor web
# (nginx, etc.), nunca Django.
if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
