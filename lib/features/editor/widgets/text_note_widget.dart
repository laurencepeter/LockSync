import 'package:flutter/material.dart';

/// Renders a text note element. When [isEditing], shows a TextField.
class TextNoteWidget extends StatefulWidget {
  const TextNoteWidget({
    super.key,
    required this.text,
    required this.color,
    required this.fontSize,
    required this.isEditing,
    required this.onTextChanged,
  });

  final String text;
  final Color color;
  final double fontSize;
  final bool isEditing;
  final void Function(String) onTextChanged;

  @override
  State<TextNoteWidget> createState() => _TextNoteWidgetState();
}

class _TextNoteWidgetState extends State<TextNoteWidget> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.text);
  }

  @override
  void didUpdateWidget(TextNoteWidget old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text && !widget.isEditing) {
      _ctrl.text = widget.text;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF1E1E3A);
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(10),
      child: widget.isEditing
          ? TextField(
              controller: _ctrl,
              autofocus: true,
              maxLines: null,
              expands: true,
              style: TextStyle(
                color: widget.color,
                fontSize: widget.fontSize,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: widget.onTextChanged,
            )
          : Text(
              widget.text.isEmpty ? 'Tap to edit…' : widget.text,
              style: TextStyle(
                color: widget.text.isEmpty
                    ? Colors.white30
                    : widget.color,
                fontSize: widget.fontSize,
                height: 1.4,
              ),
            ),
    );
  }
}
