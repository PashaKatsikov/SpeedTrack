/// Central registry of all bundled image assets.
class AppAssets {
  static const String _add = 'assets/CCTV_Speed_Track_additional_assets';
  static const String _game = 'assets/CCTV_Speed_Track_gameplay_assets';

  // Branding / screens
  static const String gameName = '$_add/Game_Name.webp';
  static const String verticalLoading = '$_add/Vertical_Loading_Screen.webp';
  static const String horizontalLoading = '$_add/Horizontal_Loading_Screen.webp';

  // Backgrounds (stage variety)
  static const List<String> backgrounds = [
    '$_game/bg3_asset.webp',
    '$_game/bg2_asset.webp',
    '$_game/bg1_asset.webp',
  ];

  // Player car
  static const String playerCar = '$_game/car7_asset.webp';

  // Traffic cars pool
  static const List<String> trafficCars = [
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
  static List<String> get allGameplay => [
        ...backgrounds,
        playerCar,
        ...trafficCars,
        policeCar,
        coin,
        oil,
      ];
}
