import 'dart:async';
import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../models/live_category.dart';
import '../models/live_channel.dart';
import '../services/live_tv_service.dart';
import 'player_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.username,
    required this.password,
  });

  final String username;
  final String password;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final LiveTvService _service = LiveTvService();

  final TextEditingController _controller = TextEditingController();

  Timer? _searchTimer;

  bool _loading = false;

  List<LiveCategory> _categories = [];
  List<LiveChannel> _channels = [];

  void _search(String query) {

  _searchTimer?.cancel();

  _searchTimer = Timer(
    const Duration(milliseconds: 600),
    () async {

      if (query.trim().length < 3) {
        setState(() {
          _categories = [];
          _channels = [];
        });
        return;
      }

      setState(() {
        _loading = true;
      });

      try {

        debugPrint('SEARCH USER: ${widget.username}');
        debugPrint('PASSWORD LENGTH: ${widget.password.length}');

        final categories = await _service.getCategories(
          username: widget.username,
          password: widget.password,
        );


        final matchedCategories = categories.where((category) {
          return category.name
              .toLowerCase()
              .contains(query.toLowerCase());
        }).toList();


        final List<LiveChannel> matchedChannels = [];


        for (final category in categories) {

          final channels = await _service.getChannels(
            username: widget.username,
            password: widget.password,
            categoryId: category.id,
          );


          matchedChannels.addAll(
            channels.where(
              (channel) => channel.name
                  .toLowerCase()
                  .contains(query.toLowerCase()),
            ),
          );
        }


        if (!mounted) return;


        setState(() {

          _categories = matchedCategories;

          _channels = matchedChannels;

          _loading = false;

        });


      } catch (e) {

        if (!mounted) return;


        setState(() {
          _loading = false;
        });


        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error buscando canales: $e',
            ),
          ),
        );
      }

    },
  );
}


  void _openPlayer(LiveChannel channel) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          username: widget.username,
          password: widget.password,
          streamId: channel.id,
          channelName: channel.name,
          channelIcon: channel.icon,
        ),
      ),
    );
  }


  @override
  void dispose() {

    _searchTimer?.cancel();

    _controller.dispose();

    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,

      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text(
          'Buscar',
        ),
      ),

      body: Padding(
        padding: const EdgeInsets.all(16),

        child: Column(
          children: [

            TextField(
              controller: _controller,

              autofocus: true,

              onChanged: _search,

              style: const TextStyle(
                color: Colors.white,
              ),

              decoration: InputDecoration(
                hintText: 'Buscar canal o categoría...',
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: .5),
                ),

                prefixIcon: const Icon(
                  Icons.search,
                  color: Colors.white,
                ),

                filled: true,

                fillColor: AppColors.surface,

                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),

            const SizedBox(height: 20),


            if (_loading)
              const CircularProgressIndicator(
                color: AppColors.primary,
              ),


            Expanded(
              child: ListView(
                children: [

                  if (_categories.isNotEmpty)
                    const Text(
                      'Categorías',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),


                  ..._categories.map(
                    (category) => ListTile(
                      leading: const Icon(
                        Icons.category,
                        color: Colors.amber,
                      ),

                      title: Text(
                        category.name,
                        style: const TextStyle(
                          color: Colors.white,
                        ),
                      ),

                      subtitle: const Text(
                        'Categoría',
                        style: TextStyle(
                          color: Colors.white54,
                        ),
                      ),
                    ),
                  ),



                  if (_channels.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 20),
                      child: Text(
                        'Canales',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),


                  ..._channels.map(
                    (channel) => ListTile(

                      leading: channel.icon != null &&
                              channel.icon!.isNotEmpty
                          ? Image.network(
                              channel.icon!,
                              width: 40,
                              height: 40,
                              errorBuilder:
                                  (_, __, ___) =>
                                      const Icon(
                                Icons.tv,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.tv,
                              color: Colors.white,
                            ),

                      title: Text(
                        channel.name,
                        style: const TextStyle(
                          color: Colors.white,
                        ),
                      ),

                      subtitle: const Text(
                        'EN VIVO',
                        style: TextStyle(
                          color: Colors.greenAccent,
                        ),
                      ),

                      onTap: () => _openPlayer(channel),
                    ),
                  ),


                  if (!_loading &&
                      _channels.isEmpty &&
                      _categories.isEmpty &&
                      _controller.text.length >= 3)

                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(30),
                        child: Text(
                          'No se encontraron resultados',
                          style: TextStyle(
                            color: Colors.white54,
                          ),
                        ),
                      ),
                    ),

                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}