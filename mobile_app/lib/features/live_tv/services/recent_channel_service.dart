import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/recent_channel.dart';

class RecentChannelService {
  static const String _storageKey = 'recent_channels';

  Future<List<RecentChannel>> getRecentChannels() async {
    final prefs = await SharedPreferences.getInstance();

    final jsonString = prefs.getString(_storageKey);

    if (jsonString == null) {
      return [];
    }

    final List<dynamic> data = jsonDecode(jsonString);

    return data
        .map((e) => RecentChannel.fromJson(e))
        .toList();
  }

  Future<void> saveChannel(RecentChannel channel) async {
    final prefs = await SharedPreferences.getInstance();

    final channels = await getRecentChannels();

    channels.removeWhere((item) => item.id == channel.id);

    channels.insert(0, channel);

    if (channels.length > 10) {
      channels.removeRange(10, channels.length);
    }

    final json = jsonEncode(
      channels.map((e) => e.toJson()).toList(),
    );

    await prefs.setString(_storageKey, json);
  }

  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }
}