import 'package:flutter/material.dart';

import '../../models/resource_item.dart';
import 'checkerboard_image.dart';

class ResourceTile extends StatelessWidget {
  const ResourceTile({
    super.key,
    required this.item,
    required this.isSelected,
    required this.onTap,
    required this.onToggleExport,
  });

  final ResourceItem item;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onToggleExport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isSelected ? colorScheme.primary : colorScheme.outlineVariant,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CheckerboardImage(
                    bytes: item.snapshot.bytes,
                    cellSize: 8,
                    cacheWidth: 256,
                  ),
                  if (item.isModified)
                    const Positioned(
                      top: 4,
                      right: 4,
                      child: _Badge(
                        icon: Icons.edit,
                        tooltip: 'Изменено',
                        color: Colors.amber,
                      ),
                    ),
                  if (item.hasDiskOriginal)
                    Positioned(
                      top: 4,
                      right: item.isModified ? 26 : 4,
                      child: const _Badge(
                        icon: Icons.history,
                        tooltip: 'Есть оригинал',
                        color: Colors.lightBlue,
                      ),
                    ),
                  Positioned(
                    top: 4,
                    left: 4,
                    child: InkWell(
                      onTap: onToggleExport,
                      child: Checkbox(
                        value: item.selectedForExport,
                        onChanged: (_) => onToggleExport(),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 4,
                    right: 4,
                    child: _Badge(
                      icon: item.family == 'sprite'
                          ? Icons.image
                          : Icons.grid_on,
                      tooltip: item.family == 'sprite'
                          ? 'Спрайт (sprites/)'
                          : 'Текстура (textures/)',
                      color: item.family == 'sprite'
                          ? const Color(0xFFC98AFF)
                          : const Color(0xFF6EC96E),
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
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '${item.width}×${item.height}',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.hintColor),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.tooltip, required this.color});

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
