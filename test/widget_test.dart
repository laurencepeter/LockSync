// Basic Flutter widget test for LockSync.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:locksync/main.dart';
import 'package:locksync/services/storage_service.dart';

void main() {
  testWidgets('App builds without errors', (WidgetTester tester) async {
    final storage = StorageService();
    await storage.init();
    await tester.pumpWidget(LockSyncApp(storage: storage));

    // Verify the app renders
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
