import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/live_category.dart';

class LiveTvService {
  static const String _baseUrl = 'http://127.0.0.1:8000';

  Future<List<LiveCategory>> getCategories({
    required String username,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/api/xtream/live/categories/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'password': password,
      }),
    );
  }

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