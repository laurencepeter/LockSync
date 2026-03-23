import 'package:flutter/material.dart';

void main() {
  runApp(const LockSyncApp());
}

class LockSyncApp extends StatelessWidget {
  const LockSyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LockSync',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const LockSyncHome(),
    );
  }
}

class LockSyncHome extends StatelessWidget {
  const LockSyncHome({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('LockSync')),
      body: const Center(
        child: Text('LockSync — synchronized lockscreen editor'),
      ),
    );
  }
}
