import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/storage_service.dart';
import '../services/websocket_service.dart';
import '../theme.dart';
import '../widgets/animated_gradient_bg.dart';
import '../widgets/glass_card.dart';

// Travel accent colour — distinct from the couple-pairing purple.
const _kTravelAccent = Color(0xFF00B4D8);

class TravelGroupScreen extends StatelessWidget {
  const TravelGroupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WebSocketService>();
    final groups = ws.travelGroups;

    return Scaffold(
      body: AnimatedGradientBg(
        child: SafeArea(
          child: Column(
            children: [
              // ── Header ──────────────────────────────────────────────
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
                    const Column(
                      children: [
                        Text(
                          'Travel Groups',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'shared itineraries & packing lists',
                          style: TextStyle(
                              color: _kTravelAccent,
                              fontSize: 11,
                              letterSpacing: 0.3),
                        ),
                      ],
                    ),
                    const Spacer(),
                    const SizedBox(width: 48),
                  ],
                ),
              ),

              // ── Body ────────────────────────────────────────────────
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    // Security note
                    _SecurityBadge(),
                    const SizedBox(height: 16),

                    if (groups.isEmpty) ...[
                      const SizedBox(height: 32),
                      _EmptyState(),
                      const SizedBox(height: 24),
                    ] else ...[
                      for (final g in groups) ...[
                        _GroupTile(
                          group: g,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => _GroupDetailScreen(groupId: g.id),
                            ),
                          ),
                          onDelete: () async {
                            final ok = await _confirmDelete(context, g.name);
                            if (ok == true && context.mounted) {
                              await context
                                  .read<WebSocketService>()
                                  .deleteTravelGroup(g.id);
                            }
                          },
                        ),
                        const SizedBox(height: 8),
                      ],
                      const SizedBox(height: 8),
                    ],

                    // ── Create / Join ────────────────────────────────
                    _CreateJoinCard(),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool?> _confirmDelete(BuildContext context, String name) =>
      showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Leave group?',
              style: TextStyle(color: Colors.white)),
          content: Text('Remove "$name" from this device?',
              style: const TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove'),
            ),
          ],
        ),
      );
}

// ─── Security badge ───────────────────────────────────────────────────────────
class _SecurityBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.teal.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.teal.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          const Icon(Icons.shield_outlined,
              size: 16, color: Colors.tealAccent),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: const TextStyle(
                    color: Colors.white60, fontSize: 12),
                children: const [
                  TextSpan(
                    text: 'Group codes are 8-digit, ',
                  ),
                  TextSpan(
                    text: 'expire in 5 minutes',
                    style: TextStyle(
                        color: Colors.tealAccent,
                        fontWeight: FontWeight.w600),
                  ),
                  TextSpan(
                    text:
                        ', and are rate-limited. Once used, your membership is secured by a signed JWT valid for 30 days.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Empty state ─────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(36),
      child: Column(
        children: [
          Icon(Icons.flight_rounded,
              size: 56, color: _kTravelAccent.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          const Text(
            'No travel groups yet',
            style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Create a group for your trip and invite everyone\nwith a single 8-digit code.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4), fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ─── Group tile ───────────────────────────────────────────────────────────────
class _GroupTile extends StatelessWidget {
  final TravelGroup group;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _GroupTile(
      {required this.group, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final memberCount = group.memberDisplayNames.length + 1;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: _kTravelAccent.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: _kTravelAccent.withValues(alpha: 0.22)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _kTravelAccent.withValues(alpha: 0.15),
              ),
              child: const Icon(Icons.flight_rounded,
                  size: 20, color: _kTravelAccent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$memberCount member${memberCount == 1 ? '' : 's'} · '
                    '${group.itinerary.length} stop${group.itinerary.length == 1 ? '' : 's'}',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 12),
                  ),
                ],
              ),
            ),
            if (group.isHost)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _kTravelAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('HOST',
                    style: TextStyle(
                        color: _kTravelAccent,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8)),
              ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded,
                  color: Colors.white38, size: 20),
              color: const Color(0xFF1A1A2E),
              onSelected: (v) {
                if (v == 'leave') onDelete();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'leave',
                  child: Row(
                    children: [
                      Icon(Icons.exit_to_app_rounded,
                          size: 18, color: Colors.redAccent),
                      SizedBox(width: 8),
                      Text('Leave group',
                          style: TextStyle(color: Colors.redAccent)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Create / Join card ───────────────────────────────────────────────────────
class _CreateJoinCard extends StatefulWidget {
  @override
  State<_CreateJoinCard> createState() => _CreateJoinCardState();
}

class _CreateJoinCardState extends State<_CreateJoinCard> {
  bool _expanded = false;
  bool _isCreating = true; // true = create, false = join
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();
  bool _loading = false;
  String? _pendingGroupCode; // code shown after creation
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    final ws = context.read<WebSocketService>();
    _sub = ws.onGroupSync.listen((msg) {
      // nothing needed here — group list updates via notifyListeners
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    setState(() => _loading = true);
    context.read<WebSocketService>().createTravelGroup(name);
    // Listen for the group_created confirmation via the travelGroups list
    // updating (notifyListeners in _handleGroupFormed). Show success after
    // a short delay — a proper flow would listen to onGroupSync.
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) {
      setState(() {
        _loading = false;
        _expanded = false;
        _nameController.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Group "${name}" created! '
              'Share the code with your travel companions.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: _kTravelAccent.withValues(alpha: 0.9),
        ),
      );
    }
  }

  Future<void> _join() async {
    final code = _codeController.text.trim();
    if (code.length != 8) return;
    setState(() => _loading = true);
    context.read<WebSocketService>().joinTravelGroup(code);
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) {
      setState(() {
        _loading = false;
        _expanded = false;
        _codeController.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Joining group…'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Toggle button
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: _expanded
                  ? _kTravelAccent.withValues(alpha: 0.12)
                  : Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _expanded
                    ? _kTravelAccent.withValues(alpha: 0.4)
                    : Colors.white.withValues(alpha: 0.06),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.add_circle_outline_rounded,
                    color: _expanded ? _kTravelAccent : Colors.white38,
                    size: 22),
                const SizedBox(width: 12),
                Text(
                  _expanded
                      ? 'Create or join a travel group'
                      : 'Start or join a trip group…',
                  style: TextStyle(
                    color: _expanded ? Colors.white : Colors.white54,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Icon(
                  _expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  color: Colors.white38,
                ),
              ],
            ),
          ),
        ),

        if (_expanded) ...[
          const SizedBox(height: 8),
          GlassCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Create / Join toggle
                Row(
                  children: [
                    _TabChip(
                      label: 'Create Group',
                      icon: Icons.add_rounded,
                      selected: _isCreating,
                      onTap: () => setState(() => _isCreating = true),
                    ),
                    const SizedBox(width: 8),
                    _TabChip(
                      label: 'Join Group',
                      icon: Icons.link_rounded,
                      selected: !_isCreating,
                      onTap: () => setState(() => _isCreating = false),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                if (_isCreating) ...[
                  Text('Group name',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _nameController,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'e.g. Bali Trip 2025, Europe Squad…',
                      hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.3)),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.06),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                            color: _kTravelAccent, width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kTravelAccent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _loading ? null : _create,
                      icon: _loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white),
                            )
                          : const Icon(Icons.flight_takeoff_rounded,
                              size: 18),
                      label: Text(_loading
                          ? 'Creating…'
                          : 'Create Group'),
                    ),
                  ),
                ] else ...[
                  Text('Enter 8-digit group code',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _codeController,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    maxLength: 8,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 4),
                    textAlign: TextAlign.center,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: '00000000',
                      hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.2),
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 4),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.06),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                            color: _kTravelAccent, width: 1.5),
                      ),
                    ),
                    onChanged: (v) {
                      if (v.length == 8) _join();
                    },
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kTravelAccent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _loading ? null : _join,
                      icon: _loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white),
                            )
                          : const Icon(Icons.link_rounded, size: 18),
                      label: Text(_loading ? 'Joining…' : 'Join Group'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ─── Small toggle chip ────────────────────────────────────────────────────────
class _TabChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _TabChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? _kTravelAccent.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? _kTravelAccent.withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.06),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 15,
                color: selected ? _kTravelAccent : Colors.white38),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white38,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Group detail screen — itinerary, packing list, announcements, members
// ═══════════════════════════════════════════════════════════════════════════════
class _GroupDetailScreen extends StatefulWidget {
  final String groupId;
  const _GroupDetailScreen({required this.groupId});

  @override
  State<_GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<_GroupDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  StreamSubscription? _syncSub;
  final _inputController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    final ws = context.read<WebSocketService>();
    _syncSub = ws.onGroupSync.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _syncSub?.cancel();
    _inputController.dispose();
    super.dispose();
  }

  TravelGroup? _group(WebSocketService ws) {
    try {
      return ws.travelGroups.firstWhere((g) => g.id == widget.groupId);
    } catch (_) {
      return null;
    }
  }

  void _addItem(WebSocketService ws, String listType) {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    final group = _group(ws);
    if (group == null) return;

    final newItem = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'text': text,
      'done': false,
      'addedBy': ws.storage.displayName ?? 'You',
    };

    List<Map<String, dynamic>> updated;
    String syncType;
    switch (listType) {
      case 'itinerary':
        updated = [...group.itinerary, newItem];
        syncType = 'itinerary';
      case 'packing':
        updated = [...group.packingList, newItem];
        syncType = 'packing';
      default:
        updated = [...group.announcements, newItem];
        syncType = 'announcement';
    }

    ws.sendGroupSync(widget.groupId, {
      'syncType': syncType,
      'items': updated,
    });
    // Optimistically update local storage
    if (listType == 'itinerary') group.itinerary = updated;
    if (listType == 'packing') group.packingList = updated;
    if (listType == 'announcement') group.announcements = updated;
    ws.storage.saveTravelGroup(group);

    _inputController.clear();
    setState(() {});
  }

  void _toggleItem(
      WebSocketService ws, String listType, String itemId) {
    final group = _group(ws);
    if (group == null) return;

    List<Map<String, dynamic>> list;
    switch (listType) {
      case 'itinerary':
        list = group.itinerary;
      case 'packing':
        list = group.packingList;
      default:
        list = group.announcements;
    }
    final updated = list.map((item) {
      if (item['id'] == itemId) {
        return {...item, 'done': !(item['done'] as bool? ?? false)};
      }
      return item;
    }).toList();

    final syncType = listType == 'itinerary'
        ? 'itinerary'
        : listType == 'packing'
            ? 'packing'
            : 'announcement';
    ws.sendGroupSync(widget.groupId, {'syncType': syncType, 'items': updated});

    if (listType == 'itinerary') group.itinerary = updated;
    if (listType == 'packing') group.packingList = updated;
    if (listType == 'announcement') group.announcements = updated;
    ws.storage.saveTravelGroup(group);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WebSocketService>();
    final group = _group(ws);

    if (group == null) {
      return const Scaffold(
          body: Center(
              child: Text('Group not found',
                  style: TextStyle(color: Colors.white))));
    }

    final memberCount = group.memberDisplayNames.length + 1;

    return Scaffold(
      body: AnimatedGradientBg(
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    Column(
                      children: [
                        Text(
                          group.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '$memberCount member${memberCount == 1 ? '' : 's'}',
                          style: TextStyle(
                              color:
                                  _kTravelAccent.withValues(alpha: 0.8),
                              fontSize: 12),
                        ),
                      ],
                    ),
                    const Spacer(),
                    // Members popover
                    IconButton(
                      icon: const Icon(Icons.people_outline_rounded,
                          color: Colors.white70),
                      onPressed: () => _showMembers(context, group),
                    ),
                  ],
                ),
              ),

              // Tab bar
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: TabBar(
                  controller: _tabs,
                  indicator: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: _kTravelAccent,
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white38,
                  labelStyle: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13),
                  tabs: const [
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.map_outlined, size: 14),
                          SizedBox(width: 4),
                          Text('Itinerary'),
                        ],
                      ),
                    ),
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.luggage_outlined, size: 14),
                          SizedBox(width: 4),
                          Text('Packing'),
                        ],
                      ),
                    ),
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.campaign_outlined, size: 14),
                          SizedBox(width: 4),
                          Text('Updates'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Tab content
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    _ListTab(
                      items: group.itinerary,
                      listType: 'itinerary',
                      emptyLabel: 'No stops added yet',
                      hintText: 'Add a destination or activity…',
                      inputController: _inputController,
                      onAdd: () => _addItem(ws, 'itinerary'),
                      onToggle: (id) => _toggleItem(ws, 'itinerary', id),
                    ),
                    _ListTab(
                      items: group.packingList,
                      listType: 'packing',
                      emptyLabel: 'Packing list is empty',
                      hintText: 'Add something to pack…',
                      inputController: _inputController,
                      onAdd: () => _addItem(ws, 'packing'),
                      onToggle: (id) => _toggleItem(ws, 'packing', id),
                    ),
                    _ListTab(
                      items: group.announcements,
                      listType: 'announcement',
                      emptyLabel: 'No updates yet',
                      hintText: 'Post an update to the group…',
                      inputController: _inputController,
                      onAdd: () => _addItem(ws, 'announcement'),
                      onToggle: (id) => _toggleItem(ws, 'announcement', id),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMembers(BuildContext context, TravelGroup group) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _MembersSheet(group: group),
    );
  }
}

// ─── Shared list tab ─────────────────────────────────────────────────────────
class _ListTab extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final String listType;
  final String emptyLabel;
  final String hintText;
  final TextEditingController inputController;
  final VoidCallback onAdd;
  final void Function(String id) onToggle;

  const _ListTab({
    required this.items,
    required this.listType,
    required this.emptyLabel,
    required this.hintText,
    required this.inputController,
    required this.onAdd,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Input row
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: inputController,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: hintText,
                    hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.3),
                        fontSize: 13),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                          color: _kTravelAccent, width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                  onSubmitted: (_) => onAdd(),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onAdd,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _kTravelAccent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.add_rounded,
                      color: Colors.white, size: 22),
                ),
              ),
            ],
          ),
        ),

        // List
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Text(
                    emptyLabel,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.3),
                        fontSize: 14),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  itemCount: items.length,
                  itemBuilder: (ctx, i) {
                    final item = items[i];
                    final done = item['done'] as bool? ?? false;
                    return _ItemTile(
                      text: item['text'] as String? ?? '',
                      addedBy: item['addedBy'] as String?,
                      done: done,
                      onToggle: () => onToggle(item['id'] as String),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _ItemTile extends StatelessWidget {
  final String text;
  final String? addedBy;
  final bool done;
  final VoidCallback onToggle;

  const _ItemTile({
    required this.text,
    required this.addedBy,
    required this.done,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: done
              ? Colors.white.withValues(alpha: 0.03)
              : _kTravelAccent.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: done
                ? Colors.white.withValues(alpha: 0.05)
                : _kTravelAccent.withValues(alpha: 0.18),
          ),
        ),
        child: Row(
          children: [
            Icon(
              done
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 20,
              color: done ? _kTravelAccent : Colors.white38,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text,
                    style: TextStyle(
                      color: done
                          ? Colors.white38
                          : Colors.white.withValues(alpha: 0.9),
                      fontSize: 14,
                      decoration: done
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                    ),
                  ),
                  if (addedBy != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Added by $addedBy',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.3),
                          fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Members bottom sheet ─────────────────────────────────────────────────────
class _MembersSheet extends StatelessWidget {
  final TravelGroup group;
  const _MembersSheet({required this.group});

  @override
  Widget build(BuildContext context) {
    final ws = context.read<WebSocketService>();
    final myName = ws.storage.displayName ?? 'You (this device)';
    final others = group.memberDisplayNames.entries.toList();

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${others.length + 1} member${others.length + 1 == 1 ? '' : 's'}',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          _MemberRow(
              name: myName, isMe: true, isHost: group.isHost),
          for (final e in others)
            _MemberRow(
              name: e.value,
              isMe: false,
              isHost: false,
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  final String name;
  final bool isMe;
  final bool isHost;
  const _MemberRow(
      {required this.name, required this.isMe, required this.isHost});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: _kTravelAccent.withValues(alpha: 0.2),
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(
                  color: _kTravelAccent,
                  fontWeight: FontWeight.w700,
                  fontSize: 14),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isMe ? '$name (you)' : name,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
          if (isHost)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _kTravelAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('HOST',
                  style: TextStyle(
                      color: _kTravelAccent,
                      fontSize: 10,
                      fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }
}
