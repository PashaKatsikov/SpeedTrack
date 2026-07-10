/// Central registry of all bundled image assets.
///
/// [FINGERPRINT] The folder segment `CCTV_Speed_Track_additional_assets`
/// appears as a literal string in the compiled APK. Two apps sharing
/// the same folder segment is an instant cross-submission tell for
/// store scanners — keep this project's folder name unique. If a
/// future project reuses this codebase, rename the folder and update
/// both `_add` below AND the `flutter.assets` entry in `pubspec.yaml`.
class AppAssets {
  AppAssets._();

  static const String _add = 'assets/CCTV_Speed_Track_additional_assets';
  static const String _game = 'assets/CCTV_Speed_Track_gameplay_assets';

  // Branding / loading
  static const String gameName = '$_add/Game_Name.webp';
  static const String verticalLoading = '$_add/Vertical_Loading_Screen.webp';
  static const String horizontalLoading =
      '$_add/Horizontal_Loading_Screen.webp';

  // Push notification opt-in screen
  static const String verticalNotifications =
      '$_add/Vertical_Notifications_Screen.webp';
  static const String horizontalNotifications =
      '$_add/Horizontal_Notifications_Screen.webp';

  // No-Wifi screen
  static const String verticalNoWifi = '$_add/Vertical_Nowifi_Screen.webp';
  static const String horizontalNoWifi = '$_add/Horizontal_Nowifi_Screen.webp';

  // Gameplay backgrounds (stage variety)
  static const List<String> backgrounds = <String>[
    '$_game/bg3_asset.webp',
    '$_game/bg2_asset.webp',
    '$_game/bg1_asset.webp',
  ];

  // Player car
  static const String playerCar = '$_game/car7_asset.webp';

  // Traffic cars pool
  static const List<String> trafficCars = <String>[
    '$_game/car1_asset.webp',
    '$_game/car2_asset.webp',
    '$_game/car3_asset.webp',
    '$_game/car4_asset.webp',
    '$_game/car5_asset.webp',
    '$_game/car6_asset.webp',
    '$_game/car8_asset.webp',
    '$_game/taxi_car_asset.webp',
  ];

  static const String policeCar = '$_game/police_car_asset.webp';

  // Collectibles
  static const String coin = '$_game/coin_asset.webp';
  static const String oil = '$_game/oil_future_asset.webp';

  /// Everything that must be decoded before gameplay starts.
  static List<String> get allGameplay => <String>[
        ...backgrounds,
        playerCar,
        ...trafficCars,
        policeCar,
        coin,
        oil,
      ];
}
