import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

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

  Timer? _playbackWatchdog;

  bool _isInitializingPlayer = false;
  bool _playerError = false;
  bool _isReconnecting = false;

  Duration _lastPosition = Duration.zero;
  int _stalledChecks = 0;
  int _reconnectAttempts = 0;

  static const int _maxReconnectAttempts = 2;
  static const int _maxStalledChecks = 2;

  @override
  void initState() {
    super.initState();

    WakelockPlus.enable();

    _streamUrl = _service.getProxyStreamUrl(
      username: widget.username,
      password: widget.password,
      streamId: widget.streamId,
    );
  }

  Future<void> _initializePlayer(String url) async {
    try {
      await _videoPlayerController?.dispose();
      _videoPlayerController = null;

      _stopPlaybackWatchdog();

      if (mounted) {
        setState(() {
          _isInitializingPlayer = true;
          _playerError = false;
        });
      }

      final controller = VideoPlayerController.networkUrl(
        Uri.parse(url),
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: true,
        ),
      );

      _videoPlayerController = controller;

      controller.addListener(() {
        if (controller.value.hasError) {
          debugPrint(
            'VIDEO ERROR: ${controller.value.errorDescription}',
          );

          if (!_isReconnecting &&
              _reconnectAttempts < _maxReconnectAttempts) {
            _reconnectPlayer();
          }
        }
      });

      await controller.initialize();

      if (controller.value.isInitialized) {
        await controller.play();

        _startPlaybackWatchdog();
      }

      if (mounted) {
        setState(() {
          _isInitializingPlayer = false;
        });
      }
    } catch (e) {
      debugPrint('PLAYER INITIALIZATION ERROR: $e');

      _stopPlaybackWatchdog();

      await _videoPlayerController?.dispose();
      _videoPlayerController = null;

      if (_isReconnecting) {
        if (_reconnectAttempts >= _maxReconnectAttempts) {
          _finishWithError();
        }
      } else if (mounted) {
        setState(() {
          _isInitializingPlayer = false;
          _playerError = true;
        });
      }
    }
  }

  void _startPlaybackWatchdog() {
    _stopPlaybackWatchdog();

    _lastPosition = Duration.zero;
    _stalledChecks = 0;

    _playbackWatchdog = Timer.periodic(
      const Duration(seconds: 5),
      (_) {
        _checkPlaybackProgress();
      },
    );

    debugPrint('PLAYBACK WATCHDOG STARTED');
  }

  void _stopPlaybackWatchdog() {
    _playbackWatchdog?.cancel();
    _playbackWatchdog = null;
  }

  void _checkPlaybackProgress() {
    final controller = _videoPlayerController;

    if (controller == null ||
        !controller.value.isInitialized ||
        _isInitializingPlayer ||
        _isReconnecting ||
        _playerError) {
      return;
    }

    final currentPosition = controller.value.position;

    if (currentPosition > _lastPosition) {
      _lastPosition = currentPosition;
      _stalledChecks = 0;

      debugPrint(
        'PLAYBACK OK - POSITION: $currentPosition',
      );

      return;
    }

    _stalledChecks++;

    debugPrint(
      'PLAYBACK STALLED - CHECK '
      '$_stalledChecks/$_maxStalledChecks - '
      'POSITION: $currentPosition',
    );

    if (_stalledChecks >= _maxStalledChecks) {
      debugPrint('PLAYBACK FREEZE DETECTED');

      if (_reconnectAttempts < _maxReconnectAttempts) {
        _reconnectPlayer();
      } else {
        _finishWithError();
      }
    }
  }

  Future<void> _reconnectPlayer() async {
    if (_isReconnecting) {
      return;
    }

    if (_reconnectAttempts >= _maxReconnectAttempts) {
      _finishWithError();
      return;
    }

    _isReconnecting = true;
    _reconnectAttempts++;

    _stopPlaybackWatchdog();

    if (mounted) {
      setState(() {
        _isInitializingPlayer = true;
        _playerError = false;
      });
    }

    debugPrint(
      'RECONNECTING PLAYER - ATTEMPT '
      '$_reconnectAttempts/$_maxReconnectAttempts',
    );

    try {
      await _videoPlayerController?.dispose();
      _videoPlayerController = null;

      await _service.stopProxy(
        streamId: widget.streamId,
      );

      final newStreamUrl = await _service.getProxyStreamUrl(
        username: widget.username,
        password: widget.password,
        streamId: widget.streamId,
      );

      if (!mounted) {
        return;
      }

      await _initializePlayer(newStreamUrl);

      final controller = _videoPlayerController;

      if (controller != null &&
          controller.value.isInitialized &&
          !controller.value.hasError) {
        debugPrint(
          'PLAYER RECONNECTED SUCCESSFULLY - ATTEMPT '
          '$_reconnectAttempts/$_maxReconnectAttempts',
        );
      }
    } catch (e) {
      debugPrint('RECONNECTION ERROR: $e');

      if (_reconnectAttempts >= _maxReconnectAttempts) {
        _finishWithError();
      }
    } finally {
      _isReconnecting = false;

      if (mounted && !_playerError) {
        setState(() {
          _isInitializingPlayer = false;
        });
      }
    }
  }

  void _finishWithError() {
    _stopPlaybackWatchdog();

    if (!mounted) {
      return;
    }

    setState(() {
      _isInitializingPlayer = false;
      _playerError = true;
    });

    debugPrint(
      'PLAYER ERROR: Maximum automatic reconnection attempts reached.',
    );
  }

  Future<void> _refresh() async {
    _reconnectAttempts = 0;
    _stalledChecks = 0;
    _isReconnecting = false;

    _stopPlaybackWatchdog();

    await _videoPlayerController?.dispose();
    _videoPlayerController = null;

    await _service.stopProxy(
      streamId: widget.streamId,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _playerError = false;
      _isInitializingPlayer = true;

      _streamUrl = _service.getProxyStreamUrl(
        username: widget.username,
        password: widget.password,
        streamId: widget.streamId,
      );
    });

    try {
      final newStreamUrl = await _streamUrl;

      if (mounted) {
        await _initializePlayer(newStreamUrl);
      }
    } catch (e) {
      debugPrint('MANUAL RETRY ERROR: $e');

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
    _stopPlaybackWatchdog();

    WakelockPlus.disable();

    _videoPlayerController?.dispose();

    _service.stopProxy(
      streamId: widget.streamId,
    );

    super.dispose();
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
            return _buildErrorView(
              message: 'No se pudo cargar el canal.',
            );
          }

          final streamUrl = snapshot.data!;

          if (_videoPlayerController == null &&
              !_isInitializingPlayer &&
              !_playerError &&
              !_isReconnecting) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _initializePlayer(streamUrl);
              }
            });
          }

          if (_isReconnecting) {
            return _buildReconnectingView();
          }

          if (_isInitializingPlayer) {
            return const Center(
              child: CircularProgressIndicator(
                color: AppColors.neonGreen,
              ),
            );
          }

          if (_playerError) {
            return _buildErrorView(
              message: 'No se pudo reproducir el canal.',
            );
          }

          if (_videoPlayerController != null &&
              _videoPlayerController!.value.isInitialized) {
            return Center(
              child: AspectRatio(
                aspectRatio: _videoPlayerController!.value.aspectRatio,
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

  Widget _buildReconnectingView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(
            color: AppColors.neonGreen,
          ),
          const SizedBox(height: 16),
          const Text(
            'Reconectando canal...',
            style: TextStyle(
              color: AppColors.white,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Intento $_reconnectAttempts de $_maxReconnectAttempts',
            style: const TextStyle(
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView({
    required String message,
  }) {
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
          Text(
            message,
            style: const TextStyle(
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
}

