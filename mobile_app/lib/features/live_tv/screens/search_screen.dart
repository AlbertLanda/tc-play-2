import 'dart:async';
import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../models/live_category.dart';
import '../models/live_channel.dart';
import '../services/live_tv_service.dart';
import '../services/search_cache.dart';
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
  bool _hasSearchText = false;
  bool _isSearching = false;
  bool _isNavigating = false;

  List<LiveCategory> _categories = [];
  List<LiveChannel> _channels = [];

  List<LiveCategory> _allCategories = [];
  List<LiveChannel> _allChannels = [];

  @override
  void initState() {
    super.initState();
    _loadSearchData();
  }

  Future<void> _loadSearchData() async {
    if (SearchCache.hasData) {
      _allCategories = SearchCache.categories!;
      _allChannels = SearchCache.channels!;

      if (mounted) {
        setState(() {});
      }

      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      // Reutiliza la precarga que ya se empezó desde Inicio (ver
      // HomeScreen.initState) si sigue en curso, en vez de volver a
      // pedir todo desde cero. Si por algún motivo esa precarga no
      // llegó a dispararse, esto la inicia recién ahora.
      await SearchCache.ensureLoaded(
        _service,
        username: widget.username,
        password: widget.password,
      );

      _allCategories = SearchCache.categories ?? [];
      _allChannels = SearchCache.channels ?? [];

      if (_controller.text.trim().isNotEmpty) {
        _search(_controller.text);
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _search(String query) {

    setState(() {
      _hasSearchText = query.trim().isNotEmpty;
      _isSearching = query.trim().isNotEmpty;
    });
    _searchTimer?.cancel();

    _searchTimer = Timer(
      const Duration(milliseconds: 300),
      () {
        
        if (_loading) {
          return;
        }

        if (query.trim().isEmpty) {
          setState(() {
            _categories = [];
            _channels = [];
            _isSearching = false;
          });
          return;
        }

        final search = query.toLowerCase();

        final matchedCategories = _allCategories.where((category) {
          return category.name.toLowerCase().contains(search);
        }).toList();

        final matchedChannels = _allChannels.where((channel) {
          return channel.name.toLowerCase().contains(search);
        }).toList();

        setState(() {
          _categories = matchedCategories;
          _channels = matchedChannels;
          _isSearching = false;
        });
      },
    );
  }

  Future<void> _openPlayer(LiveChannel channel) async {
    if (_isNavigating) return;

    _isNavigating = true;

    try {
      await Navigator.push(
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
    } finally {
      if (mounted) {
        setState(() {
          _isNavigating = false;
        });
      }
    }
  }


  @override
  void dispose() {

    _searchTimer?.cancel();

    _controller.dispose();

    super.dispose();
  }


  @override
Widget build(BuildContext context) {
  final mediaQuery = MediaQuery.of(context);
  final isLandscape =
      mediaQuery.orientation == Orientation.landscape;

  final keyboardVisible = mediaQuery.viewInsets.bottom > 0;

  return Scaffold(
    backgroundColor: AppColors.background,
    resizeToAvoidBottomInset: true,

    appBar: AppBar(
      toolbarHeight: isLandscape ? 44 : 56,
      backgroundColor: AppColors.background,
      title: Text(
        'Buscar',
        style: TextStyle(
          fontSize: isLandscape ? 18 : 20,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    body: SafeArea(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: isLandscape ? 12 : 16,
          vertical: isLandscape ? 6 : 16,
        ),
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
                hintText: 'Buscar canal...',
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: .5),
                ),

                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: Colors.white,
                  size: isLandscape ? 21 : 24,
                ),

                filled: true,
                fillColor: AppColors.surface,

                contentPadding: EdgeInsets.symmetric(
                  vertical: isLandscape ? 8 : 16,
                  horizontal: isLandscape ? 14 : 20,
                ),

                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),

                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),

                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide(
                    color: AppColors.primary,
                    width: 1.3,
                  ),
                ),

                disabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
              ),
            ),

            SizedBox(
              height: isLandscape ? 6 : 12,
            ),

            if (_loading && _hasSearchText)
              Padding(
                padding: EdgeInsets.only(
                  top: isLandscape ? 8 : 30,
                ),
                child: Column(
                  children: [
                    SizedBox(
                      width: isLandscape ? 20 : 24,
                      height: isLandscape ? 20 : 24,
                      child: const CircularProgressIndicator(
                        color: AppColors.primary,
                        strokeWidth: 2,
                      ),
                    ),

                    if (!isLandscape) ...[
                      const SizedBox(height: 14),
                      const Text(
                        'Cargando canales...',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

            Expanded(
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,

                padding: EdgeInsets.only(
                  top: isLandscape ? 4 : 8,
                  bottom: keyboardVisible ? 8 : 20,
                ),

                children: [
                  if (!_loading && !_hasSearchText)
                    Padding(
                      padding: EdgeInsets.only(
                        top: isLandscape ? 15 : 80,
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.search_rounded,
                            color: AppColors.textSecondary,
                            size: isLandscape ? 36 : 48,
                          ),

                          SizedBox(
                            height: isLandscape ? 6 : 12,
                          ),

                          Text(
                            'Busca tu canal favorito',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: isLandscape ? 14 : 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),

                          if (!isLandscape) ...[
                            const SizedBox(height: 6),
                            const Text(
                              'Escribe el nombre del canal que deseas ver',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                  if (_categories.isNotEmpty) ...[
                    Text(
                      'Categorías',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isLandscape ? 16 : 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    ..._categories.map(
                      (category) => ListTile(
                        dense: isLandscape,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: isLandscape ? 4 : 8,
                        ),

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
                  ],

                  if (_channels.isNotEmpty) ...[
                    Padding(
                      padding: EdgeInsets.only(
                        top: isLandscape ? 8 : 20,
                      ),
                      child: Text(
                        'Canales',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: isLandscape ? 16 : 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                    ..._channels.map(
                      (channel) => ListTile(
                        dense: isLandscape,

                        contentPadding: EdgeInsets.symmetric(
                          horizontal: isLandscape ? 4 : 8,
                        ),

                        leading: channel.icon != null &&
                                channel.icon!.isNotEmpty
                            ? Image.network(
                                channel.icon!,
                                width: isLandscape ? 32 : 40,
                                height: isLandscape ? 32 : 40,
                                errorBuilder:
                                    (_, _, _) => const Icon(
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
                  ],

                  if (!_loading &&
                      !_isSearching &&
                      _channels.isEmpty &&
                      _categories.isEmpty &&
                      _controller.text.trim().isNotEmpty)
                    Padding(
                      padding: EdgeInsets.all(
                        isLandscape ? 15 : 30,
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.search_off_rounded,
                            color: AppColors.textSecondary,
                            size: isLandscape ? 36 : 48,
                          ),

                          SizedBox(
                            height: isLandscape ? 8 : 14,
                          ),

                          Text(
                            'No encontramos resultados.',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: isLandscape ? 14 : null,
                              fontWeight: FontWeight.w600,
                            ),
                          ),

                          if (!isLandscape) ...[
                            const SizedBox(height: 6),
                            const Text(
                              'Prueba escribiendo otro nombre de canal.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
  
}