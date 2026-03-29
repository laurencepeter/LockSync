import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../services/websocket_service.dart';
import '../theme.dart';
import '../widgets/animated_gradient_bg.dart';
import 'moments_screen.dart';

// ─── Widget Drawer (FAB bottom sheet) ────────────────────────────────
class WidgetDrawer extends StatelessWidget {
  const WidgetDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Add Widget',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),
            _WidgetOption(
              icon: Icons.shopping_cart_rounded,
              title: 'Grocery Checklist',
              subtitle: 'Shared shopping list with checkboxes',
              color: Colors.green,
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const GroceryScreen()),
                );
              },
            ),
            _WidgetOption(
              icon: Icons.movie_rounded,
              title: 'Movie Watchlist',
              subtitle: 'Track movies & shows to watch together',
              color: Colors.orange,
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const WatchlistScreen()),
                );
              },
            ),
            _WidgetOption(
              icon: Icons.notifications_active_rounded,
              title: 'Reminders',
              subtitle: 'Set reminders for your partner',
              color: Colors.blue,
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const RemindersScreen()),
                );
              },
            ),
            _WidgetOption(
              icon: Icons.timer_rounded,
              title: 'Countdown Timer',
              subtitle: 'Count down to a special date',
              color: Colors.purple,
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CountdownScreen()),
                );
              },
            ),
            _WidgetOption(
              icon: Icons.photo_camera_rounded,
              title: 'Moments',
              subtitle: 'Share photos & videos that disappear after viewing',
              color: Colors.pink,
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MomentsScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _WidgetOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _WidgetOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: Colors.white.withValues(alpha: 0.3)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Grocery Checklist ───────────────────────────────────────────────
class GroceryScreen extends StatefulWidget {
  const GroceryScreen({super.key});

  @override
  State<GroceryScreen> createState() => _GroceryScreenState();
}

class _GroceryScreenState extends State<GroceryScreen> {
  final _controller = TextEditingController();
  List<Map<String, dynamic>> _items = [];
  StreamSubscription? _syncSub;

  @override
  void initState() {
    super.initState();
    _loadItems();
    _listenForSync();
  }

  void _loadItems() {
    final storage = context.read<WebSocketService>().storage;
    _items = List<Map<String, dynamic>>.from(storage.groceryList);
  }

  void _listenForSync() {
    final ws = context.read<WebSocketService>();
    _syncSub = ws.onWidgetSync.listen((data) {
      if (data['syncType'] == 'grocery' && mounted) {
        setState(() {
          _items = List<Map<String, dynamic>>.from(
                    (data['items'] as List? ?? []).whereType<Map>());
        });
        _saveLocal();
      }
    });
  }

  void _saveLocal() {
    context.read<WebSocketService>().storage.setGroceryList(_items);
  }

  void _saveAndSync() {
    _saveLocal();
    context
        .read<WebSocketService>()
        .sendWidgetSync('grocery', {'items': _items});
  }

  void _addItem() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final storage = context.read<WebSocketService>().storage;
    setState(() {
      _items.add({
        'text': text,
        'checked': false,
        'addedBy': storage.displayName ?? 'Me',
      });
    });
    _controller.clear();
    _saveAndSync();
  }

  @override
  void dispose() {
    _controller.dispose();
    _syncSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedGradientBg(
        child: SafeArea(
          child: Column(
            children: [
              // Header
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
                    const Text(
                      'Grocery List',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.delete_sweep_rounded),
                      onPressed: () {
                        setState(() =>
                            _items.removeWhere((i) => i['checked'] == true));
                        _saveAndSync();
                      },
                      tooltip: 'Clear checked',
                    ),
                  ],
                ),
              ),

              // Add item row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Add an item...',
                          hintStyle: TextStyle(
                              color: Colors.white.withValues(alpha: 0.3)),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.05),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                        ),
                        onSubmitted: (_) => _addItem(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _addItem,
                      icon: const Icon(Icons.add_rounded),
                      style: IconButton.styleFrom(
                        backgroundColor: LockSyncTheme.primaryColor,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // List
              Expanded(
                child: _items.isEmpty
                    ? Center(
                        child: Text(
                          'No items yet.\nAdd something to get started!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.3)),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _items.length,
                        itemBuilder: (ctx, i) {
                          final item = _items[i];
                          return Dismissible(
                            key: ValueKey('$i-${item['text']}'),
                            direction: DismissDirection.endToStart,
                            onDismissed: (_) {
                              setState(() => _items.removeAt(i));
                              _saveAndSync();
                            },
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              child: const Icon(Icons.delete_rounded,
                                  color: Colors.red),
                            ),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ListTile(
                                leading: Checkbox(
                                  value: item['checked'] as bool,
                                  onChanged: (v) {
                                    setState(() => item['checked'] = v);
                                    _saveAndSync();
                                  },
                                  activeColor: LockSyncTheme.accentColor,
                                ),
                                title: Text(
                                  item['text'] as String,
                                  style: TextStyle(
                                    color: item['checked'] == true
                                        ? Colors.white30
                                        : Colors.white,
                                    decoration: item['checked'] == true
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                                subtitle: Text(
                                  'Added by ${item['addedBy'] ?? 'Unknown'}',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.3),
                                    fontSize: 11,
                                  ),
                                ),
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

// ─── Movie Watchlist ─────────────────────────────────────────────────
class WatchlistScreen extends StatefulWidget {
  const WatchlistScreen({super.key});

  @override
  State<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends State<WatchlistScreen> {
  final _controller = TextEditingController();
  List<Map<String, dynamic>> _items = [];
  StreamSubscription? _syncSub;

  @override
  void initState() {
    super.initState();
    final storage = context.read<WebSocketService>().storage;
    _items = List<Map<String, dynamic>>.from(storage.watchlist);
    _listenForSync();
  }

  void _listenForSync() {
    final ws = context.read<WebSocketService>();
    _syncSub = ws.onWidgetSync.listen((data) {
      if (data['syncType'] == 'watchlist' && mounted) {
        setState(() {
          _items = List<Map<String, dynamic>>.from(
                    (data['items'] as List? ?? []).whereType<Map>());
        });
        _saveLocal();
      }
    });
  }

  void _saveLocal() {
    context.read<WebSocketService>().storage.setWatchlist(_items);
  }

  void _saveAndSync() {
    _saveLocal();
    context
        .read<WebSocketService>()
        .sendWidgetSync('watchlist', {'items': _items});
  }

  void _addItem() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _items.add({
        'title': text,
        'watched': false,
        'rating': 0,
      });
    });
    _controller.clear();
    _saveAndSync();
  }

  @override
  void dispose() {
    _controller.dispose();
    _syncSub?.cancel();
    super.dispose();
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
                    const Text(
                      'Watchlist',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Add movie or show...',
                          hintStyle: TextStyle(
                              color: Colors.white.withValues(alpha: 0.3)),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.05),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                        ),
                        onSubmitted: (_) => _addItem(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _addItem,
                      icon: const Icon(Icons.add_rounded),
                      style: IconButton.styleFrom(
                        backgroundColor: LockSyncTheme.primaryColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _items.isEmpty
                    ? Center(
                        child: Text(
                          'No movies yet.\nAdd something to watch together!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.3)),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _items.length,
                        itemBuilder: (ctx, i) {
                          final item = _items[i];
                          final watched = item['watched'] as bool;
                          final rating = (item['rating'] as num?)?.toInt() ?? 0;

                          return Dismissible(
                            key: ValueKey('$i-${item['title']}'),
                            direction: DismissDirection.endToStart,
                            onDismissed: (_) {
                              setState(() => _items.removeAt(i));
                              _saveAndSync();
                            },
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              child: const Icon(Icons.delete_rounded,
                                  color: Colors.red),
                            ),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  GestureDetector(
                                    onTap: () {
                                      setState(
                                          () => item['watched'] = !watched);
                                      _saveAndSync();
                                    },
                                    child: Icon(
                                      watched
                                          ? Icons.check_circle_rounded
                                          : Icons.radio_button_unchecked_rounded,
                                      color: watched
                                          ? LockSyncTheme.accentColor
                                          : Colors.white30,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      item['title'] as String,
                                      style: TextStyle(
                                        color: watched
                                            ? Colors.white30
                                            : Colors.white,
                                        decoration: watched
                                            ? TextDecoration.lineThrough
                                            : null,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                  // Star rating
                                  if (watched)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: List.generate(5, (star) {
                                        return GestureDetector(
                                          onTap: () {
                                            setState(() =>
                                                item['rating'] = star + 1);
                                            _saveAndSync();
                                          },
                                          child: Icon(
                                            star < rating
                                                ? Icons.star_rounded
                                                : Icons.star_outline_rounded,
                                            color: Colors.amber,
                                            size: 20,
                                          ),
                                        );
                                      }),
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

// ─── Reminders ───────────────────────────────────────────────────────
class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  List<Map<String, dynamic>> _reminders = [];
  StreamSubscription? _syncSub;

  @override
  void initState() {
    super.initState();
    final storage = context.read<WebSocketService>().storage;
    _reminders = List<Map<String, dynamic>>.from(storage.reminders);
    _listenForSync();
  }

  void _listenForSync() {
    final ws = context.read<WebSocketService>();
    _syncSub = ws.onWidgetSync.listen((data) {
      if (data['syncType'] == 'reminder' && mounted) {
        setState(() {
          _reminders = List<Map<String, dynamic>>.from(
                    (data['items'] as List? ?? []).whereType<Map>());
        });
        _saveLocal();
      }
    });
  }

  void _saveLocal() {
    context.read<WebSocketService>().storage.setReminders(_reminders);
  }

  void _saveAndSync() {
    _saveLocal();
    context
        .read<WebSocketService>()
        .sendWidgetSync('reminder', {'items': _reminders});
  }

  void _addReminder() {
    final msgController = TextEditingController();
    DateTime? selectedDate;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('New Reminder',
              style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: msgController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Reminder message...',
                  hintStyle: TextStyle(color: Colors.white30),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () async {
                  final date = await showDatePicker(
                    context: ctx,
                    firstDate: DateTime.now(),
                    lastDate:
                        DateTime.now().add(const Duration(days: 365)),
                  );
                  if (date != null) {
                    if (!ctx.mounted) return;
                    final time = await showTimePicker(
                      context: ctx,
                      initialTime: TimeOfDay.now(),
                    );
                    setDialogState(() {
                      selectedDate = DateTime(
                        date.year,
                        date.month,
                        date.day,
                        time?.hour ?? 12,
                        time?.minute ?? 0,
                      );
                    });
                  }
                },
                icon: const Icon(Icons.calendar_today_rounded, size: 18),
                label: Text(
                  selectedDate != null
                      ? DateFormat('MMM d, y h:mm a').format(selectedDate!)
                      : 'Set date & time (optional)',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (msgController.text.trim().isEmpty) return;
                final storage = context.read<WebSocketService>().storage;
                setState(() {
                  _reminders.add({
                    'message': msgController.text.trim(),
                    'date': selectedDate?.toIso8601String(),
                    'setBy': storage.displayName ?? 'Partner',
                    'dismissed': false,
                  });
                });
                _saveAndSync();
                Navigator.pop(ctx);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    super.dispose();
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
                    const Text(
                      'Reminders',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              Expanded(
                child: _reminders.isEmpty
                    ? Center(
                        child: Text(
                          'No reminders yet.\nTap + to add one!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.3)),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _reminders.length,
                        itemBuilder: (ctx, i) {
                          final r = _reminders[i];
                          final dismissed = r['dismissed'] as bool? ?? false;
                          return Dismissible(
                            key: ValueKey('$i-${r['message']}'),
                            direction: DismissDirection.endToStart,
                            onDismissed: (_) {
                              setState(() => _reminders.removeAt(i));
                              _saveAndSync();
                            },
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              child: const Icon(Icons.delete_rounded,
                                  color: Colors.red),
                            ),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: dismissed
                                    ? Colors.white.withValues(alpha: 0.03)
                                    : Colors.blue.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: dismissed
                                      ? Colors.white.withValues(alpha: 0.05)
                                      : Colors.blue.withValues(alpha: 0.2),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.notifications_active_rounded,
                                        color: dismissed
                                            ? Colors.white24
                                            : Colors.blue,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'From ${r['setBy'] ?? 'Partner'}',
                                        style: TextStyle(
                                          color: dismissed
                                              ? Colors.white24
                                              : Colors.blue,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const Spacer(),
                                      if (!dismissed)
                                        GestureDetector(
                                          onTap: () {
                                            setState(
                                                () => r['dismissed'] = true);
                                            _saveAndSync();
                                          },
                                          child: const Icon(
                                            Icons.check_circle_outline_rounded,
                                            color: Colors.blue,
                                            size: 22,
                                          ),
                                        ),
                                      const SizedBox(width: 4),
                                      GestureDetector(
                                        onTap: () {
                                          setState(
                                              () => _reminders.removeAt(i));
                                          _saveAndSync();
                                        },
                                        child: Icon(
                                          Icons.delete_outline_rounded,
                                          color: Colors.white
                                              .withValues(alpha: 0.3),
                                          size: 20,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    r['message'] as String,
                                    style: TextStyle(
                                      color: dismissed
                                          ? Colors.white30
                                          : Colors.white,
                                      fontSize: 16,
                                      decoration: dismissed
                                          ? TextDecoration.lineThrough
                                          : null,
                                    ),
                                  ),
                                  if (r['date'] != null) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      DateFormat('MMM d, y h:mm a')
                                          .format(DateTime.parse(r['date'])),
                                      style: TextStyle(
                                        color: Colors.white
                                            .withValues(alpha: 0.4),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
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
      floatingActionButton: FloatingActionButton(
        onPressed: _addReminder,
        backgroundColor: LockSyncTheme.primaryColor,
        child: const Icon(Icons.add_rounded),
      ),
    );
  }
}

// ─── Countdown Timer ─────────────────────────────────────────────────
class CountdownScreen extends StatefulWidget {
  const CountdownScreen({super.key});

  @override
  State<CountdownScreen> createState() => _CountdownScreenState();
}

class _CountdownScreenState extends State<CountdownScreen> {
  List<Map<String, dynamic>> _countdowns = [];
  Timer? _ticker;
  StreamSubscription? _syncSub;

  @override
  void initState() {
    super.initState();
    final storage = context.read<WebSocketService>().storage;
    _countdowns = List<Map<String, dynamic>>.from(storage.countdowns);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _listenForSync();
  }

  void _listenForSync() {
    final ws = context.read<WebSocketService>();
    _syncSub = ws.onWidgetSync.listen((data) {
      if (data['syncType'] == 'countdown' && mounted) {
        setState(() {
          _countdowns = List<Map<String, dynamic>>.from(
                    (data['items'] as List? ?? []).whereType<Map>());
        });
        _saveLocal();
      }
    });
  }

  void _saveLocal() {
    context.read<WebSocketService>().storage.setCountdowns(_countdowns);
  }

  void _saveAndSync() {
    _saveLocal();
    context
        .read<WebSocketService>()
        .sendWidgetSync('countdown', {'items': _countdowns});
  }

  void _addCountdown() {
    final labelController = TextEditingController();
    DateTime? selectedDate;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('New Countdown',
              style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: labelController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Event name (e.g., Our Trip!)',
                  hintStyle: TextStyle(color: Colors.white30),
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () async {
                  final date = await showDatePicker(
                    context: ctx,
                    firstDate: DateTime.now(),
                    lastDate:
                        DateTime.now().add(const Duration(days: 3650)),
                  );
                  if (date != null) {
                    setDialogState(() => selectedDate = date);
                  }
                },
                icon: const Icon(Icons.calendar_today_rounded, size: 18),
                label: Text(
                  selectedDate != null
                      ? DateFormat('MMM d, y').format(selectedDate!)
                      : 'Pick a date',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (labelController.text.trim().isEmpty ||
                    selectedDate == null) { return; }
                setState(() {
                  _countdowns.add({
                    'label': labelController.text.trim(),
                    'date': selectedDate!.toIso8601String(),
                  });
                });
                _saveAndSync();
                Navigator.pop(ctx);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _syncSub?.cancel();
    super.dispose();
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
                    const Text(
                      'Countdowns',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              Expanded(
                child: _countdowns.isEmpty
                    ? Center(
                        child: Text(
                          'No countdowns yet.\nTap + to count down to something special!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.3)),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _countdowns.length,
                        itemBuilder: (ctx, i) {
                          final c = _countdowns[i];
                          final targetDate = DateTime.parse(c['date']);
                          final now = DateTime.now();
                          final diff = targetDate.difference(now);
                          final isPast = diff.isNegative;

                          return Dismissible(
                            key: ValueKey('$i-${c['label']}'),
                            direction: DismissDirection.endToStart,
                            onDismissed: (_) {
                              setState(() => _countdowns.removeAt(i));
                              _saveAndSync();
                            },
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              child: const Icon(Icons.delete_rounded,
                                  color: Colors.red),
                            ),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    LockSyncTheme.primaryColor
                                        .withValues(alpha: 0.15),
                                    LockSyncTheme.accentColor
                                        .withValues(alpha: 0.08),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: LockSyncTheme.primaryColor
                                      .withValues(alpha: 0.2),
                                ),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    c['label'] as String,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    DateFormat('MMMM d, y')
                                        .format(targetDate),
                                    style: TextStyle(
                                      color:
                                          Colors.white.withValues(alpha: 0.5),
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  if (isPast)
                                    const Text(
                                      'This event has passed!',
                                      style: TextStyle(
                                        color: Colors.amber,
                                        fontSize: 16,
                                      ),
                                    )
                                  else
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceEvenly,
                                      children: [
                                        _CountdownUnit(
                                            value: diff.inDays,
                                            label: 'Days'),
                                        _CountdownUnit(
                                            value: diff.inHours % 24,
                                            label: 'Hours'),
                                        _CountdownUnit(
                                            value: diff.inMinutes % 60,
                                            label: 'Min'),
                                        _CountdownUnit(
                                            value: diff.inSeconds % 60,
                                            label: 'Sec'),
                                      ],
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
      floatingActionButton: FloatingActionButton(
        onPressed: _addCountdown,
        backgroundColor: LockSyncTheme.primaryColor,
        child: const Icon(Icons.add_rounded),
      ),
    );
  }
}

class _CountdownUnit extends StatelessWidget {
  final int value;
  final String label;
  const _CountdownUnit({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value.toString().padLeft(2, '0'),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
