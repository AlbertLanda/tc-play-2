import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/favorite_channel.dart';

class FavoriteChannelService {
  static const _storageKey = 'favorite_channels';

  Future<List<FavoriteChannel>> getFavoriteChannels() async {
    final prefs = await SharedPreferences.getInstance();

    final data = prefs.getStringList(_storageKey) ?? [];

    return data
        .map((e) => FavoriteChannel.fromJson(jsonDecode(e)))
        .toList();
  }

  Future<bool> isFavorite(int channelId) async {
    final favorites = await getFavoriteChannels();

    return favorites.any((c) => c.id == channelId);
  }

  Future<void> saveChannel(FavoriteChannel channel) async {
    final prefs = await SharedPreferences.getInstance();

    final favorites = await getFavoriteChannels();

    favorites.removeWhere((c) => c.id == channel.id);

    favorites.insert(0, channel);

    final encoded =
        favorites.map((c) => jsonEncode(c.toJson())).toList();

    await prefs.setStringList(_storageKey, encoded);
  }

  Future<void> removeChannel(int channelId) async {
    final prefs = await SharedPreferences.getInstance();

    final favorites = await getFavoriteChannels();

    favorites.removeWhere((c) => c.id == channelId);

    final encoded =
        favorites.map((c) => jsonEncode(c.toJson())).toList();

    await prefs.setStringList(_storageKey, encoded);
  }
}