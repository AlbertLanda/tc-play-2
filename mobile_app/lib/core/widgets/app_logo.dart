import 'package:flutter/material.dart';

class AppLogo extends StatelessWidget {
  final double size;

  const AppLogo({
    super.key,
    this.size = 80,
  });

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/tc_play_logo.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}