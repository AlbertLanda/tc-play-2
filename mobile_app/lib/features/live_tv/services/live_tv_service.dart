import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/live_category.dart';
import '../models/live_channel.dart';
import '../../../core/constants/api_constants.dart';

class LiveTvService {
  static const String _baseUrl = 'http://192.168.42.118:8000';

  /// Categorías reales
  Future<List<LiveCategory>> getCategories({
    required String username,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('${ApiConstants.baseUrl}/api/xtream/live/categories/'),
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'username': username,
        'password': password,
      }),
    );

    final data = jsonDecode(response.body);

    if (response.statusCode != 200 || data['success'] != true) {
      throw Exception(
        data['message'] ?? 'No se pudieron cargar las categorías.',
      );
    }

    final categories = data['categories'] as List<dynamic>? ?? [];

    return categories
        .map(
          (item) => LiveCategory.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  /// Canales reales
  Future<List<LiveChannel>> getChannels({
    required String username,
    required String password,
    required String categoryId,
  }) async {
    final response = await http.post(
      Uri.parse('${ApiConstants.baseUrl}/api/xtream/live/streams/'),
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'username': username,
        'password': password,
        'category_id': categoryId,
      }),
    );

    final data = jsonDecode(response.body);

    if (response.statusCode != 200 || data['success'] != true) {
      throw Exception(
        data['message'] ?? 'No se pudieron cargar los canales.',
      );
    }

    final channels = data['channels'] as List<dynamic>? ?? [];

    return channels
        .map(
          (item) => LiveChannel.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  /// Información temporal del reproductor
  Future<Map<String, dynamic>> getLiveTvData() async {
    await Future.delayed(const Duration(seconds: 2));

    return {
      "currentChannel": {
        "number": "001",
        "name": "TC Noticias HD",
        "isLive": true,
      },
      "channels": [
        {
          "number": "001",
          "name": "TC Noticias HD",
        },
        {
          "number": "002",
          "name": "TC Deportes HD",
        },
        {
          "number": "003",
          "name": "TC Películas",
        },
        {
          "number": "004",
          "name": "TC Música",
        },
        {
          "number": "005",
          "name": "TC Infantil",
        },
      ],
    };
  }
}