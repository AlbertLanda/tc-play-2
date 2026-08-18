import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../live_tv/models/live_channel.dart';
import '../../live_tv/services/live_tv_service.dart';
import 'tv_native_player.dart';

class TvNativePreview extends StatefulWidget {
  const TvNativePreview({
    super.key,
    required this.username,
    required this.password,
    required this.channel,
  });

  final String username;
  final String password;
  final LiveChannel channel;

  @override
  State<TvNativePreview> createState() => _TvNativePreviewState();
}

class _TvNativePreviewState extends State<TvNativePreview> {
  final LiveTvService _service = LiveTvService();

  String? _streamUrl;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStream();
  }

  @override
  void didUpdateWidget(covariant TvNativePreview oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.channel.id != widget.channel.id) {
      _loadStream();
    }
  }

  Future<void> _loadStream() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
      _streamUrl = null;
    });

    try {
      final url = await _service.getStreamUrl(
        username: widget.username,
        password: widget.password,
        streamId: widget.channel.id,
        output: 'm3u8',
      );

      debugPrint(
        'TV NATIVE PREVIEW: '
        '${widget.channel.name} (${widget.channel.id})',
      );

      if (!mounted) return;

      setState(() {
        _streamUrl = url;
        _loading = false;
      });
    } catch (e) {
      debugPrint('TV NATIVE PREVIEW ERROR: $e');

      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                color: AppColors.primary,
              ),
              SizedBox(height: 14),
              Text(
                'Cargando canal...',
                style: TextStyle(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.error,
              ),
            ),
          ),
        ),
      );
    }

    final url = _streamUrl;

    if (url == null || url.isEmpty) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: Text(
            'URL de reproducción no disponible.',
            style: TextStyle(
              color: AppColors.textSecondary,
            ),
          ),
        ),
      );
    }

    return TvNativePlayer(
      key: ValueKey('${widget.channel.id}-$url'),
      url: url,
    );
  }
}