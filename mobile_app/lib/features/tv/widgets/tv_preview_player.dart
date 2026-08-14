import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../core/constants/app_colors.dart';
import '../../live_tv/models/live_channel.dart';
import '../../live_tv/services/live_tv_service.dart';

class TvPreviewPlayer extends StatefulWidget {
  const TvPreviewPlayer({
    super.key,
    required this.username,
    required this.password,
    required this.channel,
  });

  final String username;
  final String password;
  final LiveChannel channel;

  @override
  State<TvPreviewPlayer> createState() => _TvPreviewPlayerState();
}

class _TvPreviewPlayerState extends State<TvPreviewPlayer> {
  final LiveTvService _service = LiveTvService();

  late final Player _player;
  late final VideoController _videoController;

  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();

    _player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 1024 * 1024 * 32,
      ),
    );

    _videoController = VideoController(_player);

    _loadChannel();
  }

  @override
  void didUpdateWidget(covariant TvPreviewPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.channel.id != widget.channel.id) {
      _loadChannel();
    }
  }

  Future<void> _loadChannel() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _player.stop();

      final url = await _service.getStreamUrl(
        username: widget.username,
        password: widget.password,
        streamId: widget.channel.id,
        output: 'ts',
      );

      debugPrint(
        'TV PREVIEW: canal=${widget.channel.name} id=${widget.channel.id}',
      );

      await _player.open(
        Media(
          url,
          httpHeaders: const {
            'User-Agent':
                'Mozilla/5.0 (Android TV) AppleWebKit/537.36 TCPlay/2.0',
            'Accept': '*/*',
            'Connection': 'keep-alive',
          },
        ),
        play: true,
      );

      if (!mounted) return;

      setState(() {
        _loading = false;
      });
    } catch (e) {
      debugPrint('TV PREVIEW ERROR: $e');

      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Video(
              controller: _videoController,
              controls: NoVideoControls,
              fit: BoxFit.contain,
            ),

            if (_loading)
              Container(
                color: Colors.black.withValues(alpha: .60),
                child: const Center(
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
              ),

            if (_error != null)
              Container(
                color: Colors.black.withValues(alpha: .85),
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        color: AppColors.error,
                        size: 42,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'No se pudo reproducir el canal',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}