import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'package:cinepro_manager/src/app.dart';

void main() {
  testWidgets('shows the startup shell', (WidgetTester tester) async {
    await tester.pumpWidget(const CineProManagerApp());

    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
