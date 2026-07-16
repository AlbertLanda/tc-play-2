from django.urls import path

from .views import (
    astra_channels,
    astra_proxy_url,
    astra_stop_proxy,
    astra_proxy_status,
)


urlpatterns = [
    path("channels/", astra_channels, name="astra_channels"),
    path("proxy-url/", astra_proxy_url, name="astra_proxy_url"),
    path("stop-proxy/", astra_stop_proxy, name="astra_stop_proxy"),
    path("proxy-status/", astra_proxy_status, name="astra_proxy_status"),
]