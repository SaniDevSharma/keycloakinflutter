import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/auth_service.dart';
import '../widgets/activity_item.dart';
import '../widgets/stat_card.dart';
import 'login_screen.dart';

/// Main dashboard screen shown after successful Keycloak login.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.userInfo});

  final UserInfo userInfo;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  bool _isLoggingOut = false;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _handleLogout() async {
    setState(() => _isLoggingOut = true);
    try {
      await AuthService.instance.logout();
    } finally {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const LoginScreen(),
          transitionsBuilder: (_, animation, __, child) => FadeTransition(
            opacity: animation,
            child: child,
          ),
          transitionDuration: const Duration(milliseconds: 400),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E1A),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: CustomScrollView(
          slivers: [
            _buildSliverAppBar(),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  const SizedBox(height: 24),
                  _buildWelcomeCard(),
                  const SizedBox(height: 28),
                  _buildSectionTitle('Overview'),
                  const SizedBox(height: 14),
                  _buildStatsGrid(),
                  const SizedBox(height: 28),
                  _buildSectionTitle('Recent Activity'),
                  const SizedBox(height: 14),
                  _buildActivityList(),
                  const SizedBox(height: 28),
                  _buildSectionTitle('Quick Actions'),
                  const SizedBox(height: 14),
                  _buildQuickActions(),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── App Bar ──────────────────────────────────────

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      backgroundColor: const Color(0xFF0B0E1A),
      expandedHeight: 70,
      floating: true,
      pinned: true,
      elevation: 0,
      automaticallyImplyLeading: false,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6C63FF), Color(0xFF3ECFCF)],
                    ),
                  ),
                  child: const Icon(Icons.dashboard_rounded,
                      color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                Text(
                  'Dashboard',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            _isLoggingOut
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white54,
                    ),
                  )
                : GestureDetector(
                    onTap: _handleLogout,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(20),
                        border:
                            Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.logout_rounded,
                              color: Colors.white60, size: 15),
                          const SizedBox(width: 6),
                          Text(
                            'Logout',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: Colors.white60,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  // ── Welcome card ─────────────────────────────────

  Widget _buildWelcomeCard() {
    final initials = _getInitials(widget.userInfo.name);
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1F35), Color(0xFF151929)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFF6C63FF), Color(0xFF3ECFCF)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6C63FF).withOpacity(0.4),
                  blurRadius: 20,
                ),
              ],
            ),
            child: Center(
              child: Text(
                initials,
                style: GoogleFonts.inter(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hello, ${widget.userInfo.givenName ?? widget.userInfo.name}!',
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.userInfo.email.isNotEmpty
                      ? widget.userInfo.email
                      : widget.userInfo.preferredUsername,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: Colors.white.withOpacity(0.5),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3ECFCF).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.verified_rounded,
                          color: Color(0xFF3ECFCF), size: 13),
                      const SizedBox(width: 5),
                      Text(
                        'Authenticated via Keycloak',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: const Color(0xFF3ECFCF),
                          fontWeight: FontWeight.w600,
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
    );
  }

  // ── Stats grid ───────────────────────────────────

  Widget _buildStatsGrid() {
    final cards = [
      (
        icon: Icons.people_alt_rounded,
        label: 'Total Users',
        value: '12,847',
        trend: '+8.3%',
        gradient: const LinearGradient(
          colors: [Color(0xFF6C63FF), Color(0xFF8B5CF6)],
        ),
      ),
      (
        icon: Icons.bar_chart_rounded,
        label: 'Sessions',
        value: '4,291',
        trend: '+12%',
        gradient: const LinearGradient(
          colors: [Color(0xFF3ECFCF), Color(0xFF06B6D4)],
        ),
      ),
      (
        icon: Icons.shield_rounded,
        label: 'Auth Events',
        value: '98.7%',
        trend: '↑ 0.4%',
        gradient: const LinearGradient(
          colors: [Color(0xFF10B981), Color(0xFF059669)],
        ),
      ),
      (
        icon: Icons.token_rounded,
        label: 'DPoP Tokens',
        value: '3,508',
        trend: '+5.1%',
        gradient: const LinearGradient(
          colors: [Color(0xFFF59E0B), Color(0xFFEF4444)],
        ),
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: 1.05,
      ),
      itemCount: cards.length,
      itemBuilder: (_, i) {
        final c = cards[i];
        return StatCard(
          icon: c.icon,
          label: c.label,
          value: c.value,
          gradient: c.gradient,
          trend: c.trend,
        );
      },
    );
  }

  // ── Activity list ────────────────────────────────

  Widget _buildActivityList() {
    final activities = [
      (
        icon: Icons.login_rounded,
        title: 'Successful Login',
        subtitle: 'DPoP proof validated · realm: TestSSO',
        time: 'Now',
        color: const Color(0xFF6C63FF),
      ),
      (
        icon: Icons.token_rounded,
        title: 'Access Token Issued',
        subtitle: 'DPoP-bound token · expires in 5 min',
        time: '1m ago',
        color: const Color(0xFF3ECFCF),
      ),
      (
        icon: Icons.refresh_rounded,
        title: 'Token Refreshed',
        subtitle: 'Silent refresh · new DPoP nonce',
        time: '6m ago',
        color: const Color(0xFF10B981),
      ),
      (
        icon: Icons.security_rounded,
        title: 'Key Pair Generated',
        subtitle: 'EC P-256 · stored in secure enclave',
        time: '10m ago',
        color: const Color(0xFFF59E0B),
      ),
      (
        icon: Icons.cloud_done_rounded,
        title: 'API Request',
        subtitle: 'GET /userinfo · 200 OK',
        time: '11m ago',
        color: const Color(0xFF8B5CF6),
      ),
    ];

    return Column(
      children: activities
          .map((a) => ActivityItem(
                icon: a.icon,
                title: a.title,
                subtitle: a.subtitle,
                time: a.time,
                iconColor: a.color,
              ))
          .toList(),
    );
  }

  // ── Quick actions ─────────────────────────────────

  Widget _buildQuickActions() {
    final actions = [
      (icon: Icons.person_rounded, label: 'Profile', color: const Color(0xFF6C63FF)),
      (icon: Icons.settings_rounded, label: 'Settings', color: const Color(0xFF3ECFCF)),
      (icon: Icons.analytics_rounded, label: 'Reports', color: const Color(0xFF10B981)),
      (icon: Icons.notifications_rounded, label: 'Alerts', color: const Color(0xFFF59E0B)),
    ];

    return Row(
      children: actions.map((a) {
        return Expanded(
          child: GestureDetector(
            onTap: () {},
            child: Container(
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                color: a.color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: a.color.withOpacity(0.2)),
              ),
              child: Column(
                children: [
                  Icon(a.icon, color: a.color, size: 26),
                  const SizedBox(height: 8),
                  Text(
                    a.label,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.white70,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── Section title ─────────────────────────────────

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: GoogleFonts.inter(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : 'U';
  }
}
