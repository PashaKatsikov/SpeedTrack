import 'package:flutter_test/flutter_test.dart';

import 'package:cctvspeedtrack/main.dart';

void main() {
  testWidgets('App builds without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const SpeedTrackApp());
    expect(find.byType(SpeedTrackApp), findsOneWidget);
  });
}
