import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/keycloak_config.dart';
import '../services/auth_service.dart';
import '../services/dpop_service.dart';
import 'dashboard_screen.dart';

/// Keycloak login screen with premium dark UI and animated button.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  bool _isLoading = false;
  String? _errorMessage;

  late final AnimationController _bgController;
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _bgController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await DpopService.instance.init();
      final userInfo = await AuthService.instance.login();

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, animation, __) =>
              DashboardScreen(userInfo: userInfo),
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.05, 0),
                  end: Offset.zero,
                ).animate(CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOut,
                )),
                child: child,
              ),
            );
          },
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final raw = e.toString();

      // User pressed back in browser — silently dismiss, no error shown.
      if (raw.contains('UserCancelled') ||
          raw.contains('user_cancelled') ||
          raw.contains('User cancelled') ||
          raw.contains('cancelled flow')) {
        setState(() => _errorMessage = null);
        return;
      }

      // Token exchange / DPoP errors — show Keycloak's response body.
      String friendly;
      if (raw.contains('Token exchange failed')) {
        // Extract HTTP status and body for actionable message.
        final match = RegExp(r'\((\d+)\): (.+)').firstMatch(raw);
        if (match != null) {
          friendly = 'Login failed (HTTP ${match.group(1)}):\n${match.group(2)}';
        } else {
          friendly = 'Token exchange failed. Check Keycloak DPoP settings.';
        }
      } else if (raw.contains('SocketException') ||
          raw.contains('Connection refused') ||
          raw.contains('Failed host lookup')) {
        friendly =
            'Cannot reach Keycloak at ${KeycloakConfig.baseUrl}.\nCheck that the server is running and your device is on the same network.';
      } else {
        friendly = raw.replaceFirst('Exception: ', '');
      }

      setState(() => _errorMessage = friendly);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E1A),
      body: Stack(
        children: [
          // ── Animated background orbs ──────────────
          _AnimatedBackground(controller: _bgController),

          // ── Main content ──────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                children: [
                  const Spacer(flex: 2),

                  // Logo / brand
                  _buildLogo(),

                  const SizedBox(height: 40),

                  // Title
                  Text(
                    'Welcome Back',
                    style: GoogleFonts.inter(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Sign in securely with your\nKeycloak account',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      color: Colors.white.withOpacity(0.55),
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const Spacer(flex: 2),

                  // Error message
                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.red.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded,
                              color: Colors.redAccent, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: Colors.redAccent,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Login button
                  ScaleTransition(
                    scale: _pulseAnimation,
                    child: _LoginButton(
                      isLoading: _isLoading,
                      onPressed: _isLoading ? null : _handleLogin,
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Security badge
                  _buildSecurityBadge(),

                  const Spacer(),

                  // Footer
                  Text(
                    'Protected by DPoP token binding · RFC 9449',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: Colors.white.withOpacity(0.25),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogo() {
    return Container(
      width: 90,
      height: 90,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Color(0xFF6C63FF), Color(0xFF3ECFCF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6C63FF).withOpacity(0.5),
            blurRadius: 30,
            spreadRadius: 2,
          ),
        ],
      ),
      child: const Icon(Icons.lock_outline_rounded,
          color: Colors.white, size: 40),
    );
  }

  Widget _buildSecurityBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.verified_user_outlined,
              color: Color(0xFF3ECFCF), size: 16),
          const SizedBox(width: 8),
          Text(
            'PKCE + DPoP · End-to-end secured',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: Colors.white.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Login button ───────────────────────────────────

class _LoginButton extends StatelessWidget {
  const _LoginButton({required this.isLoading, required this.onPressed});

  final bool isLoading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF6C63FF), Color(0xFF3ECFCF)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6C63FF).withOpacity(0.45),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          child: isLoading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.login_rounded,
                        color: Colors.white, size: 22),
                    const SizedBox(width: 12),
                    Text(
                      'Sign in with Keycloak',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

// ── Animated background ────────────────────────────

class _AnimatedBackground extends StatelessWidget {
  const _AnimatedBackground({required this.controller});

  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        final t = controller.value;
        return CustomPaint(
          size: MediaQuery.of(context).size,
          painter: _OrbPainter(t),
        );
      },
    );
  }
}

class _OrbPainter extends CustomPainter {
  const _OrbPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    void drawOrb(
      double cx,
      double cy,
      double radius,
      Color color,
      double phaseShift,
    ) {
      final x = cx + math.sin((t + phaseShift) * 2 * math.pi) * 40;
      final y = cy + math.cos((t + phaseShift) * 2 * math.pi) * 30;

      final paint = Paint()
        ..shader = RadialGradient(
          colors: [color.withOpacity(0.25), color.withOpacity(0)],
        ).createShader(Rect.fromCircle(
          center: Offset(x * size.width, y * size.height),
          radius: radius,
        ))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 60);

      canvas.drawCircle(
          Offset(x * size.width, y * size.height), radius, paint);
    }

    drawOrb(0.2, 0.2, 200, const Color(0xFF6C63FF), 0.0);
    drawOrb(0.8, 0.7, 250, const Color(0xFF3ECFCF), 0.33);
    drawOrb(0.5, 0.5, 180, const Color(0xFF8B5CF6), 0.66);
  }

  @override
  bool shouldRepaint(_OrbPainter old) => old.t != t;
}
