import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../core/constants/app_colors.dart';
import '../services/live_tv_service.dart';

class PlayerScreen extends StatefulWidget {
  final String username;
  final String password;
  final int streamId;
  final String channelName;
  final String? channelIcon;

  const PlayerScreen({
    super.key,
    required this.username,
    required this.password,
    required this.streamId,
    required this.channelName,
    this.channelIcon,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final LiveTvService _service = LiveTvService();

  late Future<String> _streamUrl;

  VideoPlayerController? _videoPlayerController;

  bool _isInitializingPlayer = false;
  bool _playerError = false;

  @override
  void initState() {
    super.initState();

    _streamUrl = _service.getProxyStreamUrl(
      username: widget.username,
      password: widget.password,
      streamId: widget.streamId,
    );
  }

  Future<void> _initializePlayer(String url) async {

    print('=================================');
    print('ENTRO A INIT PLAYER');
    print('URL RECIBIDA: $url');
    print('=================================');

    print('ENTRO A INIT PLAYER');
    print('STREAM URL: $url');

    try {
      await _videoPlayerController?.dispose();
      _videoPlayerController = null;

      if (mounted) {
        setState(() {
          _isInitializingPlayer = true;
          _playerError = false;
        });
      }

      _videoPlayerController = VideoPlayerController.networkUrl(
        Uri.parse(url),
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: true,
        ),
      );

      _videoPlayerController!.addListener(() {
        final controller = _videoPlayerController!;

        if (controller.value.hasError) {
          print(
            'VIDEO ERROR: ${controller.value.errorDescription}',
          );
        }
      });

      await _videoPlayerController!.initialize();

      if (_videoPlayerController!.value.isInitialized){
        await _videoPlayerController!.play();
      }

      if (mounted) {
        setState(() {
          _isInitializingPlayer = false;
        });
      }

    } catch (e, stackTrace) {
        print('=================================');
        print('ERROR VIDEO PLAYER');
        print(e);
        print(stackTrace);
        print('=================================');

        await _videoPlayerController?.dispose();
        _videoPlayerController = null;

        if (mounted) {
          setState(() {
            _isInitializingPlayer = false;
            _playerError = true;
          });
        }
      }
  }

  @override
  void dispose() {
    _videoPlayerController?.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    await _videoPlayerController?.dispose();
    _videoPlayerController = null;

    setState(() {
      _playerError = false;
      _isInitializingPlayer = false;

      _streamUrl = _service.getProxyStreamUrl(
        username: widget.username,
        password: widget.password,
        streamId: widget.streamId,
      );
    });

    await _streamUrl;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text(widget.channelName),
        centerTitle: true,
      ),
      body: FutureBuilder<String>(
        future: _streamUrl,
        builder: (context, snapshot) {

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(
                color: AppColors.neonGreen,
              ),
            );
          }

          if (snapshot.hasError) {
            print('ERROR STREAM: ${snapshot.error}');

            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [

                  const Icon(
                    Icons.error_outline,
                    color: Colors.red,
                    size: 50,
                  ),

                  const SizedBox(height: 16),

                  const Text(
                    'No se pudo cargar el canal.',
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


          final streamUrl = snapshot.data!;

          print('=================================');
          print('STREAM URL DEL FUTURE');
          print(streamUrl);
          print('=================================');

          print('STREAM URL DEL FUTURE: $streamUrl');


          if (_videoPlayerController == null &&
              !_isInitializingPlayer &&
              !_playerError) {

            WidgetsBinding.instance.addPostFrameCallback((_) {
              _initializePlayer(streamUrl);
            });
          }


          if (_isInitializingPlayer) {
            return const Center(
              child: CircularProgressIndicator(
                color: AppColors.neonGreen,
              ),
            );
          }


          if (_playerError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [

                  const Icon(
                    Icons.error_outline,
                    color: Colors.red,
                    size: 50,
                  ),

                  const SizedBox(height: 16),

                  const Text(
                    'No se pudo reproducir el canal.',
                    style: TextStyle(
                      color: AppColors.white,
                    ),
                  ),

                  const SizedBox(height: 16),

                  ElevatedButton(
                    onPressed: () {
                      _initializePlayer(streamUrl);
                    },
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            );
          }


          if (_videoPlayerController != null &&
              _videoPlayerController!.value.isInitialized) {

            return Center(
              child: AspectRatio(
                aspectRatio:
                    _videoPlayerController!.value.aspectRatio,
                child: VideoPlayer(
                  _videoPlayerController!,
                ),
              ),
            );
          }


          return const Center(
            child: CircularProgressIndicator(
              color: AppColors.neonGreen,
            ),
          );
        },
      ),
    );
  }
}