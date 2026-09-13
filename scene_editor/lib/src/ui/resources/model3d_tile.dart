import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:pet_engine_v2/pet_engine_v2.dart';

/// A «Модели» catalog tile: an icon card (no GPU preview in v1) with the
/// model's name, format and size.
///
/// Interaction mirrors the object rows in the left panel: a single click
/// selects immediately (the InkWell tap is the only recognizer, so it never
/// waits out [kDoubleTapTimeout]), while a double click — detected on raw
/// pointer-down events — opens the viewer ([onOpen]).
class Model3dTile extends StatefulWidget {
  const Model3dTile({
    super.key,
    required this.entry,
    required this.isSelected,
    required this.onTap,
    required this.onOpen,
  });

  final Model3dEntry entry;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onOpen;

  @override
  State<Model3dTile> createState() => _Model3dTileState();
}

class _Model3dTileState extends State<Model3dTile> {
  DateTime? _lastPointerDown;

  void _onPointerDown(PointerDownEvent e) {
    final isPrimary =
        e.kind == PointerDeviceKind.touch ||
        (e.buttons & kPrimaryMouseButton) != 0;
    if (!isPrimary) return;
    final now = DateTime.now();
    final isDouble =
        _lastPointerDown != null &&
        now.difference(_lastPointerDown!) < kDoubleTapTimeout;
    _lastPointerDown = isDouble ? null : now;
    if (isDouble) widget.onOpen();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entry = widget.entry;
    final colorScheme = theme.colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: widget.isSelected
              ? colorScheme.primary
              : colorScheme.outlineVariant,
          width: widget.isSelected ? 2 : 1,
        ),
      ),
      child: Listener(
        onPointerDown: _onPointerDown,
        child: InkWell(
          onTap: widget.onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(
                      color: const Color(0xFF2A2F39),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.view_in_ar,
                        size: 56,
                        color: Colors.white24,
                      ),
                    ),
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: _Badge(
                        icon: entry.isFolder
                            ? Icons.folder_outlined
                            : Icons.diamond_outlined,
                        tooltip: entry.isFolder
                            ? 'Модель 3D (3d_models/ — папка glTF)'
                            : 'Модель 3D (3d_models/ — файл GLB)',
                        color: const Color(0xFFF2A93B),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${entry.kindLabel} • ${entry.sizeLabel}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.hintColor,
                      ),
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
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.icon,
    required this.tooltip,
    required this.color,
  });

  final IconData icon;
  final String tooltip;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 14, color: color),
      ),
    );
  }
}
