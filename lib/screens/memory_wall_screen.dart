import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../services/websocket_service.dart';
import '../theme.dart';
import '../widgets/animated_gradient_bg.dart';

class MemoryWallScreen extends StatefulWidget {
  const MemoryWallScreen({super.key});

  @override
  State<MemoryWallScreen> createState() => _MemoryWallScreenState();
}

class _MemoryWallScreenState extends State<MemoryWallScreen> {
  List<Map<String, dynamic>> _memories = [];

  @override
  void initState() {
    super.initState();
    _loadMemories();
  }

  void _loadMemories() {
    final storage = context.read<WebSocketService>().storage;
    _memories = storage.memories;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedGradientBg(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    Text(
                      'Memory Wall',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const Spacer(),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              Expanded(
                child: _memories.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.photo_library_outlined,
                              size: 64,
                              color: Colors.white.withValues(alpha: 0.15),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No memories yet.\nSave canvas snapshots from the canvas screen!',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.3)),
                            ),
                          ],
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(16),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.85,
                        ),
                        itemCount: _memories.length,
                        itemBuilder: (ctx, i) {
                          final memory = _memories[i];
                          final timestamp = memory['timestamp'] as String?;
                          final dateStr = timestamp != null
                              ? DateFormat('MMM d, y')
                                  .format(DateTime.parse(timestamp))
                              : 'Unknown date';

                          return GestureDetector(
                            onLongPress: () {
                              showDialog(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  backgroundColor: const Color(0xFF1A1A2E),
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(20)),
                                  title: const Text('Delete Memory?',
                                      style:
                                          TextStyle(color: Colors.white)),
                                  content: const Text(
                                    'This cannot be undone.',
                                    style: TextStyle(color: Colors.white60),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx),
                                      child: const Text('Cancel'),
                                    ),
                                    ElevatedButton(
                                      onPressed: () {
                                        final storage = context
                                            .read<WebSocketService>()
                                            .storage;
                                        storage.deleteMemory(i);
                                        setState(() {
                                          _memories.removeAt(i);
                                        });
                                        Navigator.pop(ctx);
                                      },
                                      style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.red),
                                      child: const Text('Delete'),
                                    ),
                                  ],
                                ),
                              );
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    LockSyncTheme.primaryColor
                                        .withValues(alpha: 0.15),
                                    LockSyncTheme.accentColor
                                        .withValues(alpha: 0.08),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.08),
                                ),
                              ),
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.bookmark_rounded,
                                    color: LockSyncTheme.accentColor
                                        .withValues(alpha: 0.5),
                                  ),
                                  const Spacer(),
                                  Text(
                                    dateStr,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Tap to restore\nLong-press to delete',
                                    style: TextStyle(
                                      color:
                                          Colors.white.withValues(alpha: 0.4),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
