import 'package:video_player/video_player.dart';
import 'dart:core';

import '../services/live_tv_service.dart';

class LiveTvPlayerController {
  final LiveTvService service = LiveTvService();

  VideoPlayerController? videoController;

  bool isInitializing = false;
  bool hasError = false;
  bool isReconnecting = false;
  bool isDisposed = false;

  Future<VideoPlayerController?> createController(String url) async {
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(url),
      videoPlayerOptions: VideoPlayerOptions(
        mixWithOthers: true,
      ),
    );

    try {
      await controller.initialize();

      if (!controller.value.isInitialized) {
        await controller.dispose();
        return null;
      }

      return controller;
    } catch (e) {
      await controller.dispose();
      return null;
    }
  }

  Future<void> dispose() async {
    isDisposed = true;
    await videoController?.dispose();
    videoController = null;
  }
}