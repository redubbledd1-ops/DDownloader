import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:downoader/main.dart';

void main() {
  testWidgets('App shows URL field and download button', (WidgetTester tester) async {
    await tester.pumpWidget(const DownoaderApp());

    expect(find.text('Download'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('MP4'), findsOneWidget);
    expect(find.text('MP3'), findsOneWidget);
  });
}
