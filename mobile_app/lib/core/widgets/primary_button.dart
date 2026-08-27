import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../utils/tv_utils.dart';

class PrimaryButton extends StatefulWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool loading;
  final bool autofocus;

  const PrimaryButton({
    super.key,
    required this.text,
    this.onPressed,
    this.loading = false,
    this.autofocus = false,
  });

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final isTv = TvUtils.isTv(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: isTv
          ? TvUtils.focusDecoration(focused: _focused, radius: 10)
          : const BoxDecoration(),
      child: SizedBox(
        height: isTv ? 64 : 56,
        width: double.infinity,
        child: ElevatedButton(
          onPressed: widget.loading ? null : widget.onPressed,
          autofocus: widget.autofocus,
          onFocusChange:
              isTv ? (focused) => setState(() => _focused = focused) : null,
          style: isTv
              ? ElevatedButton.styleFrom(
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 19,
                  ),
                )
              : null,
          child: widget.loading
              ? SizedBox(
                  width: isTv ? 26 : 22,
                  height: isTv ? 26 : 22,
                  child: const CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppColors.white,
                  ),
                )
              : Text(
                  widget.text,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: isTv ? 19 : 17,
                  ),
                ),
        ),
      ),
    );
  }
}
