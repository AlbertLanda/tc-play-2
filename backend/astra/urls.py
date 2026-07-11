from django.urls import path

from .views import astra_channels, astra_proxy_url


urlpatterns = [
    path("channels/", astra_channels, name="astra_channels"),
    path("proxy-url/", astra_proxy_url, name="astra_proxy_url"),
]