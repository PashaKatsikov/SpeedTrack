import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight persistence for the best score / total coins.
class Storage {
  Storage._();
  static final Storage instance = Storage._();

  static const _kBest = 'best_score';
  static const _kCoins = 'total_coins';

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  int get bestScore => _prefs?.getInt(_kBest) ?? 0;
  int get totalCoins => _prefs?.getInt(_kCoins) ?? 0;

  Future<void> submitRun({required int score, required int coins}) async {
    await init();
    if (score > bestScore) {
      await _prefs!.setInt(_kBest, score);
    }
    await _prefs!.setInt(_kCoins, totalCoins + coins);
  }
}
