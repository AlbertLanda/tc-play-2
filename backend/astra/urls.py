from django.urls import path

from .views import astra_channels


urlpatterns = [
    path("channels/", astra_channels, name="astra_channels"),
]