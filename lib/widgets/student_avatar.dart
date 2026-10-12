import 'package:flutter/material.dart';
import '../models/student_account.dart';

class StudentAvatar extends StatelessWidget {
  final StudentAccount account;
  final double radius;
  final bool enablePreview;

  const StudentAvatar({
    super.key,
    required this.account,
    this.radius = 45,
    this.enablePreview = true,
  });

  void _showPhotoPreview(BuildContext context, String? photoUrl) {
    if (!enablePreview) return;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header Dialog
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.verified_user_outlined, size: 18, color: Color(0xFF059669)),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Verifikasi Foto Santri',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20, color: Color(0xFF64748B)),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),

              // Gambar Foto Santri
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 280),
                color: const Color(0xFF0F172A),
                child: (photoUrl != null && photoUrl.isNotEmpty)
                    ? Image.network(
                        photoUrl,
                        fit: BoxFit.contain,
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return const SizedBox(
                            height: 200,
                            child: Center(
                              child: CircularProgressIndicator(color: Color(0xFF10B981)),
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) => Container(
                          height: 200,
                          alignment: Alignment.center,
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48),
                              SizedBox(height: 8),
                              Text(
                                'Foto tidak dapat dimuat',
                                style: TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      )
                    : Container(
                        height: 200,
                        alignment: Alignment.center,
                        child: Text(
                          account.customerName.isNotEmpty ? account.customerName[0].toUpperCase() : 'S',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 72,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
              ),

              // Detail Identitas Santri
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.customerName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'NIS: ${account.accountNumber}${account.student?.className != null ? ' • Kelas ${account.student!.className}' : ''}${account.student?.hostel != null ? ' • ${account.student!.hostel}' : ''}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Saldo Rekening',
                            style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                          ),
                          Text(
                            account.balanceFormatted,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF059669),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFallback() {
    final initial = account.customerName.isNotEmpty ? account.customerName[0].toUpperCase() : 'S';
    return Container(
      color: const Color(0xFF1E293B),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontSize: radius * 0.9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final photoUrl = account.photoUrl ?? account.student?.photoUrl;

    return GestureDetector(
      onTap: enablePreview ? () => _showPhotoPreview(context, photoUrl) : null,
      child: Container(
        width: radius * 2 + 6,
        height: radius * 2 + 6,
        padding: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF10B981), width: 2),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF10B981).withValues(alpha: 0.15),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipOval(
          child: (photoUrl != null && photoUrl.isNotEmpty)
              ? Image.network(
                  photoUrl,
                  width: radius * 2,
                  height: radius * 2,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      color: const Color(0xFFF1F5F9),
                      child: const Center(
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF10B981)),
                        ),
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) => _buildFallback(),
                )
              : _buildFallback(),
        ),
      ),
    );
  }
}
