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

  VideoPlayerController? _videoPlayerController;

  Timer? _playbackWatchdog;
  Timer? _reconnectDelayTimer;

  bool _isInitializingPlayer = false;
  bool _playerError = false;
  bool _isReconnecting = false;
  bool _isDisposed = false;

  int _reconnectAttempts = 0;

  static const int _maxReconnectAttempts = 2;

  Duration _lastPosition = Duration.zero;
  DateTime _lastPositionChange = DateTime.now();

  @override
  void initState() {
    super.initState();

    WakelockPlus.enable();

    _loadInitialPlayer();
  }

  Future<void> _loadInitialPlayer() async {
    if (_isDisposed) {
      return;
    }

    if (mounted) {
      setState(() {
        _isInitializingPlayer = true;
        _playerError = false;
      });
    }

    try {
      final streamUrl = await _service.getProxyStreamUrl(
        username: widget.username,
        password: widget.password,
        streamId: widget.streamId,
      );

      if (!mounted || _isDisposed) {
        return;
      }

      final controller = await _createAndInitializeController(streamUrl);

      if (!mounted || _isDisposed) {
        await controller?.dispose();
        return;
      }

      if (controller == null) {
        _showPlayerError();
        return;
      }

      _videoPlayerController = controller;

      await controller.play();

      _reconnectAttempts = 0;

      _startPlaybackWatchdog();

      setState(() {
        _isInitializingPlayer = false;
        _playerError = false;
      });

      debugPrint('PLAYER INITIALIZED SUCCESSFULLY');
    } catch (e) {
      debugPrint('INITIAL PLAYER ERROR: $e');

      if (!mounted || _isDisposed) {
        return;
      }

      _showPlayerError();
    }
  }

  Future<VideoPlayerController?> _createAndInitializeController(
    String url,
  ) async {
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(url),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );

    try {
      await controller.initialize();

      if (!controller.value.isInitialized) {
        await controller.dispose();
        return null;
      }

      controller.addListener(() {
        if (_isDisposed) {
          return;
        }

        if (controller.value.hasError &&
            identical(controller, _videoPlayerController)) {
          debugPrint('VIDEO ERROR: ${controller.value.errorDescription}');

          _startAutomaticReconnect();
        }
      });

      return controller;
    } catch (e) {
      debugPrint('CONTROLLER INITIALIZATION ERROR: $e');

      await controller.dispose();

      return null;
    }
  }

  void _startPlaybackWatchdog() {
    _playbackWatchdog?.cancel();

    _lastPosition = _videoPlayerController?.value.position ?? Duration.zero;
    _lastPositionChange = DateTime.now();

    _playbackWatchdog = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _checkPlaybackHealth(),
    );
  }

  void _checkPlaybackHealth() {
    if (_isDisposed || _isReconnecting || _videoPlayerController == null) {
      return;
    }

    final controller = _videoPlayerController!;

    if (!controller.value.isInitialized) {
      return;
    }

    if (controller.value.hasError) {
      _startAutomaticReconnect();
      return;
    }

    final currentPosition = controller.value.position;

    if (currentPosition != _lastPosition) {
      _lastPosition = currentPosition;
      _lastPositionChange = DateTime.now();
      return;
    }

    final frozenDuration = DateTime.now().difference(_lastPositionChange);

    if (frozenDuration >= const Duration(seconds: 10)) {
      debugPrint(
        'PLAYBACK FROZEN FOR 10 SECONDS - '
        'STARTING AUTOMATIC RECOVERY',
      );

      _startAutomaticReconnect();
    }
  }

  Future<void> _startAutomaticReconnect() async {
    if (_isReconnecting || _isDisposed) {
      return;
    }

    if (_reconnectAttempts >= _maxReconnectAttempts) {
      debugPrint('MAXIMUM AUTOMATIC RECONNECT ATTEMPTS REACHED');

      _showPlayerError();

      return;
    }

    _isReconnecting = true;
    _reconnectAttempts++;

    debugPrint(
      'AUTOMATIC RECONNECT '
      '$_reconnectAttempts/$_maxReconnectAttempts',
    );

    _playbackWatchdog?.cancel();

    final oldController = _videoPlayerController;

    try {
      await _service.stopProxy(streamId: widget.streamId);

      if (_isDisposed) {
        return;
      }

      final newStreamUrl = await _service.getProxyStreamUrl(
        username: widget.username,
        password: widget.password,
        streamId: widget.streamId,
      );

      if (_isDisposed) {
        return;
      }

      final newController = await _createAndInitializeController(newStreamUrl);

      if (newController == null) {
        debugPrint(
          'AUTOMATIC RECONNECT FAILED '
          '$_reconnectAttempts/$_maxReconnectAttempts',
        );

        _handleReconnectFailure();

        return;
      }

      if (_isDisposed || !mounted) {
        await newController.dispose();
        return;
      }

      await newController.play();

      _videoPlayerController = newController;

      await oldController?.dispose();

      _reconnectAttempts = 0;

      _startPlaybackWatchdog();

      debugPrint('AUTOMATIC RECONNECT SUCCESS');

      if (mounted) {
        setState(() {
          _playerError = false;
        });
      }
    } catch (e) {
      debugPrint('AUTOMATIC RECONNECT ERROR: $e');

      _handleReconnectFailure();
    } finally {
      _isReconnecting = false;
    }
  }

  void _handleReconnectFailure() {
    if (_isDisposed) {
      return;
    }

    if (_reconnectAttempts < _maxReconnectAttempts) {
      _reconnectDelayTimer?.cancel();

      _reconnectDelayTimer = Timer(const Duration(seconds: 2), () {
        if (!_isDisposed && !_isReconnecting) {
          _startAutomaticReconnect();
        }
      });

      return;
    }

    debugPrint(
      'AUTOMATIC RECONNECT FAILED '
      'AFTER $_maxReconnectAttempts ATTEMPTS',
    );

    _showPlayerError();
  }

  void _showPlayerError() {
    if (!mounted || _isDisposed) {
      return;
    }

    setState(() {
      _isInitializingPlayer = false;
      _playerError = true;
    });
  }

  Future<void> _refresh() async {
    if (_isDisposed) {
      return;
    }

    _reconnectAttempts = 0;
    _playerError = false;

    await _startAutomaticReconnect();
  }

  @override
  void dispose() {
    _isDisposed = true;

    _playbackWatchdog?.cancel();
    _reconnectDelayTimer?.cancel();

    WakelockPlus.disable();

    _videoPlayerController?.dispose();

    _service.stopProxy(streamId: widget.streamId);

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        centerTitle: true,
        title: Text(widget.channelName),
      ),
      body: _buildPlayerContent(),
    );
  }

  Widget _buildPlayerContent() {
    final controller = _videoPlayerController;

    if (controller != null && controller.value.isInitialized && !_playerError) {
      return Center(
        child: AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: VideoPlayer(controller),
        ),
      );
    }

    if (_isInitializingPlayer) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.neonGreen),
      );
    }

    if (_playerError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 50),
            const SizedBox(height: 16),
            const Text(
              'No se pudo reproducir el canal.',
              style: TextStyle(color: AppColors.white),
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

    return const Center(
      child: CircularProgressIndicator(color: AppColors.neonGreen),
    );
  }
}
