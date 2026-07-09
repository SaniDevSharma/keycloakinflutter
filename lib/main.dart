import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'screens/dashboard_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';
import 'services/dpop_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialise the DPoP key pair (loads from storage or generates new one).
  await DpopService.instance.init();

  runApp(const KeycloakApp());
}

class KeycloakApp extends StatelessWidget {
  const KeycloakApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Keycloak SSO App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C63FF),
          brightness: Brightness.dark,
        ),
        textTheme: GoogleFonts.interTextTheme(
          ThemeData(brightness: Brightness.dark).textTheme,
        ),
        useMaterial3: true,
      ),
      home: const _SplashRouter(),
    );
  }
}

/// Checks stored token state and routes to Dashboard or Login.
class _SplashRouter extends StatefulWidget {
  const _SplashRouter();

  @override
  State<_SplashRouter> createState() => _SplashRouterState();
}

class _SplashRouterState extends State<_SplashRouter> {
  @override
  void initState() {
    super.initState();
    _route();
  }

  Future<void> _route() async {
    await Future.delayed(const Duration(milliseconds: 800)); // show splash

    final isLoggedIn = await AuthService.instance.isLoggedIn;

    if (!mounted) return;

    if (isLoggedIn) {
      // Try silent token refresh to validate the stored session.
      try {
        final userInfo = await AuthService.instance.refreshToken();
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => DashboardScreen(userInfo: userInfo),
          ),
        );
        return;
      } catch (_) {
        // Refresh failed — fall through to login.
      }
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E1A),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animated logo
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFF6C63FF), Color(0xFF3ECFCF)],
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
            ),
            const SizedBox(height: 24),
            Text(
              'Keycloak SSO',
              style: GoogleFonts.inter(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Secure · DPoP · RFC 9449',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: Colors.white.withOpacity(0.4),
              ),
            ),
            const SizedBox(height: 48),
            const SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation(Color(0xFF6C63FF)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
