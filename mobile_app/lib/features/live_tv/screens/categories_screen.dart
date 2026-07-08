import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../services/live_tv_service.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  final LiveTvService _service = LiveTvService();

  late Future<List<String>> _categories;

  // Íconos decorativos asignados de forma cíclica a cada categoría.
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


  @override
  void initState() {
    super.initState();
    _categories = _service.getCategories();
  }

  Future<void> _refresh() async {
    setState(() {
      _categories = _service.getCategories();
    });
    await _categories;
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
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.background,
              Color.lerp(AppColors.background, Colors.black, 0.4) ??
                  AppColors.background,
            ],
          ),
        ),
        child: SafeArea(
          child: FutureBuilder<List<String>>(
            future: _categories,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: AppColors.orange),
                );
              }

              if (snapshot.hasError) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          color: Colors.redAccent, size: 42),
                      const SizedBox(height: 12),
                      const Text(
                        'Error al cargar categorías',
                        style: TextStyle(color: AppColors.white),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _refresh,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.orange,
                          foregroundColor: AppColors.white,
                        ),
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Reintentar'),
                      ),
                    ],
                  ),
                );
              }

              final categories = snapshot.data ?? [];
              final width = MediaQuery.of(context).size.width;
              final crossAxisCount = width >= 900 ? 3 : (width >= 600 ? 2 : 1);

              return RefreshIndicator(
                onRefresh: _refresh,
                color: AppColors.orange,
                child: CustomScrollView(
                  slivers: [
                    // Contador visual de categorías disponibles.
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                      sliver: SliverToBoxAdapter(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.green,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.category_rounded,
                                    color: AppColors.white, size: 18),
                                const SizedBox(width: 6),
                                Text(
                                  '${categories.length} categorías disponibles',
                                  style: const TextStyle(
                                    color: AppColors.white,
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
                      sliver: categories.isEmpty
                          ? const SliverToBoxAdapter(
                              child: Padding(
                                padding: EdgeInsets.only(top: 60),
                                child: Center(
                                  child: Text(
                                    'No hay categorías disponibles.',
                                    style: TextStyle(color: AppColors.white70),
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
                                childAspectRatio: 2.6,
                              ),
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  final icon = _categoryIcons[
                                      index % _categoryIcons.length];
                                  return Card(
                                    color: AppColors.white,
                                    elevation: 5,
                                    shadowColor: Colors.black38,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(16),
                                      onTap: () {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Abriendo ${categories[index]}...',
                                            ),
                                          ),
                                        );
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 12,
                                        ),
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 44,
                                              height: 44,
                                              decoration: BoxDecoration(
                                                color: AppColors.orange
                                                    .withOpacity(0.15),
                                                shape: BoxShape.circle,
                                              ),
                                              child: Icon(
                                                icon,
                                                color: AppColors.orange,
                                                size: 22,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Text(
                                                categories[index],
                                                style: const TextStyle(
                                                  color: AppColors.title,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 15,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                                childCount: categories.length,
                              ),
                            ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}