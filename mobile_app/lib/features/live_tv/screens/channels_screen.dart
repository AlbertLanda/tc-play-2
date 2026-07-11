import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../models/live_channel.dart';
import '../services/live_tv_service.dart';

class ChannelsScreen extends StatefulWidget {
  final String username;
  final String password;
  final String categoryId;
  final String categoryName;

  const ChannelsScreen({
    super.key,
    required this.username,
    required this.password,
    required this.categoryId,
    required this.categoryName,
  });

  @override
  State<ChannelsScreen> createState() => _ChannelsScreenState();
}

class _ChannelsScreenState extends State<ChannelsScreen> {
  final LiveTvService _service = LiveTvService();

  late Future<List<LiveChannel>> _channels;

  final TextEditingController _searchController = TextEditingController();

  String _search = '';

  @override
  void initState() {
    super.initState();

    _channels = _service.getChannels(
      username: widget.username,
      password: widget.password,
      categoryId: widget.categoryId,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _channels = _service.getChannels(
        username: widget.username,
        password: widget.password,
        categoryId: widget.categoryId,
      );
    });

    await _channels;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(widget.categoryName),
        centerTitle: true,
      ),
      body: FutureBuilder<List<LiveChannel>>(
        future: _channels,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(
                color: AppColors.neonGreen,
              ),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Colors.red,
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Error al cargar canales',
                    style: TextStyle(
                      color: AppColors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reintentar'),
                  ),
                ],
              ),
            );
          }

          final channels = snapshot.data ?? [];

          final filteredChannels = channels.where((channel) {
            return channel.name
                .toLowerCase()
                .contains(_search.toLowerCase());
          }).toList();

          

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _searchController,
                  onChanged: (value) {
                    setState(() {
                      _search = value;
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'Buscar canal...',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '${filteredChannels.length} de ${channels.length} canales',
                  style: const TextStyle(
                    color: AppColors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 16),

                if (filteredChannels.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 80),
                    child: Center(
                      child: Text(
                        'No se encontraron canales.',
                        style: TextStyle(
                          color: AppColors.white70,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  )
                else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filteredChannels.length,
                  itemBuilder: (context, index) {
                    final channel = filteredChannels[index];

                    return Card(
                      color: AppColors.white,
                      elevation: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: ListTile(
                        leading: channel.icon != null &&
                                channel.icon!.isNotEmpty
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  channel.icon!,
                                  width: 50,
                                  height: 50,
                                  fit: BoxFit.cover,
                                  errorBuilder:
                                      (context, error, stackTrace) {
                                    return Container(
                                      width: 50,
                                      height: 50,
                                      decoration: BoxDecoration(
                                        color: AppColors.neonGreen
                                            .withValues(alpha: 0.15),
                                        borderRadius:
                                            BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        Icons.live_tv_rounded,
                                        color: AppColors.neonGreen,
                                      ),
                                    );
                                  },
                                ),
                              )
                            : Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  color: AppColors.neonGreen
                                      .withValues(alpha: 0.15),
                                  borderRadius:
                                      BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.live_tv_rounded,
                                  color: AppColors.neonGreen,
                                ),
                              ),
                        title: Text(
                          channel.name,
                          style: const TextStyle(
                            color: AppColors.title,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                              'ID: ${channel.id}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            Text(
                              'Tipo: ${channel.streamType}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Reproducción disponible en Día 6',
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}