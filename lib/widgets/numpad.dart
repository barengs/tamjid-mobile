import 'package:flutter/material.dart';
import '../core/app_theme.dart';

class Numpad extends StatelessWidget {
  final Function(String) onDigit;
  final VoidCallback onClear;
  final VoidCallback onDelete;

  const Numpad({
    super.key,
    required this.onDigit,
    required this.onClear,
    required this.onDelete,
  });

  Widget _buildKey(BuildContext context, String text, {Color? color, VoidCallback? onTap}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(5.0),
        child: Material(
          color: color ?? AppTheme.slate800,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap ?? () => onDigit(text),
            child: Container(
              height: 64,
              alignment: Alignment.center,
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            _buildKey(context, '1'),
            _buildKey(context, '2'),
            _buildKey(context, '3'),
          ],
        ),
        Row(
          children: [
            _buildKey(context, '4'),
            _buildKey(context, '5'),
            _buildKey(context, '6'),
          ],
        ),
        Row(
          children: [
            _buildKey(context, '7'),
            _buildKey(context, '8'),
            _buildKey(context, '9'),
          ],
        ),
        Row(
          children: [
            _buildKey(context, 'C', color: AppTheme.rose500.withValues(alpha: 0.25), onTap: onClear),
            _buildKey(context, '0'),
            _buildKey(context, '000'),
          ],
        ),
      ],
    );
  }
}
