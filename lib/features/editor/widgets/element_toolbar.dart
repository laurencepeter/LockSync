import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';

/// Floating action toolbar for adding new elements and switching tools.
class ElementToolbar extends StatelessWidget {
  const ElementToolbar({
    super.key,
    required this.onAddTextNote,
    required this.onAddDrawingCanvas,
    required this.onChangeBackground,
    required this.onOpenMembers,
    required this.onOpenSettings,
  });

  final VoidCallback onAddTextNote;
  final VoidCallback onAddDrawingCanvas;
  final VoidCallback onChangeBackground;
  final VoidCallback onOpenMembers;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E).withOpacity(0.95),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToolButton(
            icon: Icons.text_fields_rounded,
            tooltip: 'Add Text Note',
            color: const Color(0xFF6C63FF),
            onTap: onAddTextNote,
          ),
          _ToolButton(
            icon: Icons.draw_rounded,
            tooltip: 'Add Drawing Canvas',
            color: const Color(0xFF43E97B),
            onTap: onAddDrawingCanvas,
          ),
          _ToolButton(
            icon: Icons.palette_rounded,
            tooltip: 'Change Background',
            color: const Color(0xFFFF6584),
            onTap: onChangeBackground,
          ),
          const SizedBox(width: 8),
          Container(
            width: 1,
            height: 28,
            color: Colors.white.withOpacity(0.12),
          ),
          const SizedBox(width: 8),
          _ToolButton(
            icon: Icons.people_rounded,
            tooltip: 'Connected Members',
            color: Colors.white54,
            onTap: onOpenMembers,
          ),
          _ToolButton(
            icon: Icons.settings_rounded,
            tooltip: 'Settings',
            color: Colors.white54,
            onTap: onOpenSettings,
          ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: color, size: 22),
        ),
      ),
    );
  }
}

/// Bottom sheet for picking a background colour.
class BackgroundColorPicker extends StatelessWidget {
  const BackgroundColorPicker({
    super.key,
    required this.onColorSelected,
  });

  final void Function(int colorArgb) onColorSelected;

  static const _colors = <Color>[
    Color(0xFF0D0D1A),
    Color(0xFF1A1A2E),
    Color(0xFF16213E),
    Color(0xFF0F3460),
    Color(0xFF533483),
    Color(0xFF2D6A4F),
    Color(0xFF1B4332),
    Color(0xFF370617),
    Color(0xFF6A040F),
    Color(0xFF03071E),
    Color(0xFF212529),
    Color(0xFFFFFFFF),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Background Colour',
            style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _colors
                .map((c) => GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                        onColorSelected(c.value);
                      },
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withOpacity(0.25),
                            width: 1.5,
                          ),
                        ),
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}
