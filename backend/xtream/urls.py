from django.urls import path
from .views import xtream_login, live_categories, live_streams, live_stream_url

urlpatterns = [
    path("login/", xtream_login, name="xtream_login"),
    path("live/categories/", live_categories, name="live_categories"),
    path("live/streams/", live_streams, name="live_streams"),
    path("live/stream-url/", live_stream_url, name="live_stream_url"),
]