import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../models/student_account.dart';

class StudentAvatar extends StatelessWidget {
  final StudentAccount account;
  final double radius;

  const StudentAvatar({
    super.key,
    required this.account,
    this.radius = 45,
  });

  @override
  Widget build(BuildContext context) {
    final photoUrl = account.student?.photoUrl;

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppTheme.emerald500, width: 3),
      ),
      child: CircleAvatar(
        radius: radius,
        backgroundColor: AppTheme.slate700,
        backgroundImage: photoUrl != null && photoUrl.isNotEmpty
            ? NetworkImage(photoUrl)
            : null,
        child: photoUrl == null || photoUrl.isEmpty
            ? Icon(
                Icons.person,
                size: radius * 1.1,
                color: AppTheme.slate400,
              )
            : null,
      ),
    );
  }
}
