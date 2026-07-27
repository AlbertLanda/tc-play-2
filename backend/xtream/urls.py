from django.urls import path
from .views import (
    xtream_login,
    live_categories,
    live_streams,
    live_stream_url,
    live_proxy_url,
    live_stop_proxy,
    live_proxy_status,
    live_diagnose_stream,
    live_hls_status,
    live_benchmark_stream,
)

urlpatterns = [
    path("login/", xtream_login, name="xtream_login"),
    path("live/categories/", live_categories, name="live_categories"),
    path("live/streams/", live_streams, name="live_streams"),
    path("live/stream-url/", live_stream_url, name="live_stream_url"),
    path("live/proxy-url/", live_proxy_url, name="live_proxy_url"),
    path("live/stop-proxy/", live_stop_proxy, name="live_stop_proxy"),
    path("live/proxy-status/", live_proxy_status, name="live_proxy_status"),
    path("live/diagnose-stream/", live_diagnose_stream, name="live_diagnose_stream"),
    path("live/hls-status/<str:stream_id>/", live_hls_status, name="live_hls_status"),
    path("live/benchmark/", live_benchmark_stream, name="live_benchmark_stream"),
]
