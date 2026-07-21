import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../home/widgets/home_menu_card.dart';
import '../models/live_category.dart';
import '../services/live_tv_service.dart';
import 'channels_screen.dart';

class CategoriesScreen extends StatefulWidget {
  final String username;
  final String password;

  const CategoriesScreen({
    super.key,
    required this.username,
    required this.password,
  });

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  final LiveTvService _service = LiveTvService();
  final TextEditingController _searchController = TextEditingController();

  late Future<List<LiveCategory>> _categories;
  String _search = '';

  static const List<IconData> _categoryIcons = [
    Icons.newspaper_rounded,
    Icons.sports_soccer_rounded,
    Icons.theater_comedy_rounded,
    Icons.movie_rounded,
    Icons.child_care_rounded,
    Icons.music_note_rounded,
    Icons.travel_explore_rounded,
    Icons.public_rounded,
  ];

  static const List<Color> _categoryColors = [
    AppColors.primary,
    AppColors.accent,
    AppColors.orange,
    AppColors.primaryDark,
  ];

  @override
  void initState() {
    super.initState();
    _categories = _service.getCategories(
      username: widget.username,
      password: widget.password,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _categories = _service.getCategories(
        username: widget.username,
        password: widget.password,
      );
    });
    await _categories;
  }

  InputDecoration _searchDecoration() {
    return InputDecoration(
      hintText: 'Buscar categoría...',
      hintStyle: TextStyle(
        color: AppColors.textSecondary.withValues(alpha: .6),
        fontSize: 15,
      ),
      prefixIcon: const Icon(Icons.search_rounded,
          color: AppColors.textSecondary, size: 20),
      filled: true,
      fillColor: Colors.white.withValues(alpha: .05),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: .12)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: .12)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text('Categorías'),
        centerTitle: true,
      ),
      body: FutureBuilder<List<LiveCategory>>(
        future: _categories,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline_rounded,
                      color: AppColors.error, size: 42),
                  const SizedBox(height: 12),
                  const Text('Error al cargar categorías',
                      style: TextStyle(color: AppColors.textPrimary)),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Reintentar'),
                  ),
                ],
              ),
            );
          }

          final categories = snapshot.data ?? [];
          final filtered = categories
              .where(
                  (c) => c.name.toLowerCase().contains(_search.toLowerCase()))
              .toList();

          final width = MediaQuery.of(context).size.width;
          final crossAxisCount = width >= 900 ? 5 : (width >= 600 ? 4 : 3);

          return RefreshIndicator(
            onRefresh: _refresh,
            color: AppColors.primary,
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                  sliver: SliverToBoxAdapter(
                    child: TextField(
                      controller: _searchController,
                      style: const TextStyle(
                          color: AppColors.textPrimary, fontSize: 15),
                      onChanged: (value) => setState(() => _search = value),
                      decoration: _searchDecoration(),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                  sliver: SliverToBoxAdapter(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: .3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.category_rounded,
                                color: AppColors.primary, size: 18),
                            const SizedBox(width: 6),
                            Text(
                              '${filtered.length} categorías disponibles',
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  sliver: filtered.isEmpty
                      ? const SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.only(top: 60),
                            child: Center(
                              child: Text(
                                'No hay categorías disponibles.',
                                style:
                                    TextStyle(color: AppColors.textSecondary),
                              ),
                            ),
                          ),
                        )
                      : SliverGrid(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: crossAxisCount,
                            mainAxisSpacing: 14,
                            crossAxisSpacing: 14,
                            childAspectRatio: 0.85,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final category = filtered[index];
                              final icon =
                                  _categoryIcons[index % _categoryIcons.length];
                              final color = _categoryColors[
                                  index % _categoryColors.length];

                              return LogoTile(
                                title: category.name,
                                subtitle: 'ID: ${category.id}',
                                icon: icon,
                                color: color,
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ChannelsScreen(
                                        username: widget.username,
                                        password: widget.password,
                                        categoryId: category.id,
                                        categoryName: category.name,
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                            childCount: filtered.length,
                          ),
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
