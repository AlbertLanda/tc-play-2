import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../services/live_tv_service.dart';
import '../../../core/constants/app_colors.dart';

class LivePlayer extends StatefulWidget {
  const LivePlayer({
    super.key,
    required this.streamId,
    required this.username,
    required this.password,
    required this.channelName,
    this.channelIcon,
    this.onFullscreen,
  });

  final int streamId;
  final String username;
  final String password;
  final String channelName;
  final String? channelIcon;

  final VoidCallback? onFullscreen;

  @override
  State<LivePlayer> createState() => _LivePlayerState();
}

class _LivePlayerState extends State<LivePlayer> {
   final LiveTvService _service = LiveTvService();

    VideoPlayerController? _controller;

    bool _isLoading = true;
    bool _hasError = false; 

    @override
    void initState() {
        super.initState();
        _loadChannel();
    }

    @override
void didUpdateWidget(covariant LivePlayer oldWidget) {
  super.didUpdateWidget(oldWidget);

  if (oldWidget.streamId != widget.streamId) {

    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    _loadChannel();
  }
}

Future<void> _loadChannel() async {
  try {
    final url = await _service.getProxyStreamUrl(
      username: widget.username,
      password: widget.password,
      streamId: widget.streamId,
    );

    await _controller?.dispose();
    _controller = null;

    final controller = VideoPlayerController.networkUrl(
      Uri.parse(url),
    );

    await controller.initialize();

    await controller.play();

    if (!mounted) return;

    setState(() {
      _controller = controller;
      _isLoading = false;
    });

  } catch (e) {
    if (!mounted) return;

    setState(() {
      _isLoading = false;
      _hasError = true;
    });
  }
}
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
  return const Center(
    child: CircularProgressIndicator(
      color: AppColors.primary,
    ),
  );
}

if (_hasError) {
  return const Center(
    child: Text(
      'No se pudo reproducir el canal',
      style: TextStyle(color: Colors.white),
    ),
  );
}

    return Container(
      height: 220,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        children: [
            if (_controller != null &&
                _controller!.value.isInitialized)
        Center(
            child: AspectRatio(
                aspectRatio: _controller!.value.aspectRatio,
                child: VideoPlayer(_controller!),
            ),
        ),

          Positioned(
            left: 16,
            bottom: 16,
            child: Text(
              widget.channelName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          Positioned(
            right: 8,
            bottom: 8,
            child: IconButton(
              onPressed: widget.onFullscreen,
              icon: const Icon(
                Icons.fullscreen_rounded,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
void dispose() {
  _controller?.dispose();
  super.dispose();
}

}