import 'package:flutter/material.dart';

import '../app_assets.dart';
import '../app_theme.dart';
import '../game/game_screen.dart';
import '../storage.dart';
import '../widgets.dart';
import 'web_page.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  static const String privacyUrl =
      'https://speedtrrack.com/privacy-policy.html';
  static const String supportUrl = 'https://speedtrrack.com/support.html';

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  Future<void> _play() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const GameScreen()),
    );
    if (mounted) setState(() {}); // refresh best score after a run
  }

  void _openWeb(String title, String url) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => WebPage(title: title, url: url)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final best = Storage.instance.bestScore;
    final totalCoins = Storage.instance.totalCoins;

    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(AppAssets.backgrounds[1], fit: BoxFit.cover),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.45),
                  Colors.black.withValues(alpha: 0.75),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Image.asset(AppAssets.gameName, fit: BoxFit.contain),
                ),
                const Spacer(),
                _statsCard(best, totalCoins),
                const SizedBox(height: 30),
                NeonButton(
                  label: 'Play',
                  icon: Icons.play_arrow_rounded,
                  width: 260,
                  onTap: _play,
                ),
                const SizedBox(height: 22),
                _buildHowToPlay(),
                const Spacer(),
                _bottomLinks(),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statsCard(int best, int coins) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.neonBlue.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _stat('BEST SCORE', '$best', AppColors.neonCyan),
          Container(
            width: 1,
            height: 34,
            margin: const EdgeInsets.symmetric(horizontal: 20),
            color: Colors.white24,
          ),
          _stat('COINS', '$coins', AppColors.gold),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Color color) {
    return Column(
      children: [
        Text(label,
            style: AppText.label(10,
                color: AppColors.textDim, weight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(value, style: AppText.title(24, color: color)),
      ],
    );
  }

  Widget _buildHowToPlay() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 32),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'Tap or swipe left / right to change lanes.\n'
        'Dodge traffic, grab coins and fuel cells!',
        textAlign: TextAlign.center,
        style: AppText.label(12.5,
            color: AppColors.textDim, weight: FontWeight.w600),
      ),
    );
  }

  Widget _bottomLinks() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _linkButton(Icons.privacy_tip_outlined, 'Privacy Policy',
            () => _openWeb('Privacy Policy', MenuScreen.privacyUrl)),
        const SizedBox(width: 16),
        _linkButton(Icons.support_agent, 'Support',
            () => _openWeb('Support', MenuScreen.supportUrl)),
      ],
    );
  }

  Widget _linkButton(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppColors.textDim),
            const SizedBox(width: 6),
            Text(label,
                style: AppText.label(12.5,
                    color: AppColors.textDim, weight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
