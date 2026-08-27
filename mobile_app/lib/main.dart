import 'package:flutter/material.dart';
import 'app.dart';
import 'package:media_kit/media_kit.dart';
import 'core/services/pip_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  PipService.init();
  runApp(const TCPlayApp());
}