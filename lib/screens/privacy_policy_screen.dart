// lib/screens/privacy_policy_screen.dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import 'main_app_screen.dart';
import 'support_login_screen.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  // These are used when user comes from OTP login and MUST agree
  final int? userId;
  final String? email;
  final VoidCallback? onAgreed;

  const PrivacyPolicyScreen({
    super.key,
    this.userId,
    this.email,
    this.onAgreed,
  });

  // Check if this is a "forced agreement" screen (from OTP login)
  bool get _requiresAgreement => onAgreed != null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.homeBackgroundDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
        title: Text(
          'Privacy Policy',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Privacy Policy for Ezeyway',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Last updated: ${DateTime.now().toString().split(' ')[0]}',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        color: const Color(0xFFA1A1AA),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Your existing sections (unchanged)
                    _buildSection('1. Information We Collect', 'We collect information you provide directly to us...'),
                    _buildSection('2. How We Use Your Information', 'We use the information to provide, maintain...'),
                    _buildSection('3. Information Sharing', 'We do not sell, trade, or transfer your data...'),
                    _buildSection('4. Data Security', 'We implement strong security measures...'),
                    _buildSection('5. Your Rights', 'You can access, update, or delete your data...'),
                    _buildSection('6. Changes to This Policy', 'We will notify you of any changes...'),
                    _buildSection('7. Contact Us', 'Reach us at privacy@ezeyway.com'),

                    const SizedBox(height: 32),
                    Center(
                      child: RichText(
                        text: TextSpan(
                          style: GoogleFonts.plusJakartaSans(fontSize: 12, color: const Color(0xFFA1A1AA)),
                          children: [
                            const TextSpan(text: 'Powered by '),
                            TextSpan(
                              text: 'Ezeyway',
                              style: GoogleFonts.plusJakartaSans(
                                color: AppTheme.primaryColor,
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.underline,
                              ),
                              recognizer: TapGestureRecognizer()
                                ..onTap = () => Navigator.of(context).push(
                                      MaterialPageRoute(builder: (_) => const SupportLoginScreen()),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),

            // Only show "I Agree" button if user MUST accept (from OTP flow)
            if (_requiresAgreement)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: ElevatedButton(
                  onPressed: () async {
                    // Call the callback → completes login
                    onAgreed?.call();

                    // Optional: Also send agreement to backend if needed
                    // await ApiService().agreeToPrivacy(userId!);

                    if (context.mounted) {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const MainAppScreen()),
                        (route) => false,
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    minimumSize: const Size(double.infinity, 56),
                  ),
                  child: Text(
                    'I Agree & Continue',
                    style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
          const SizedBox(height: 8),
          Text(
            content,
            style: GoogleFonts.plusJakartaSans(fontSize: 14, color: const Color(0xFFA1A1AA), height: 1.6),
          ),
        ],
      ),
    );
  }
}