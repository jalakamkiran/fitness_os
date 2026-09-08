import 'dart:io';

import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'package:fitness_os/features/food/domain/food_meal.dart';

/// Meal row widget with thumbnail, name/slot, and kcal.
class FoodMealRow extends StatelessWidget {
  const FoodMealRow({
    required this.meal,
    required this.onTap,
    this.rootOverride,
    this.imageBuilder,
    super.key,
  });

  final FoodMeal meal;
  final VoidCallback onTap;
  final Directory? Function()? rootOverride;
  
  /// Test seam: bypass async Image.file in tests.
  final Widget Function(File)? imageBuilder;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final theme = Theme.of(context);

    return Material(
      color: colors.bgElev,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Thumbnail
              FutureBuilder<File>(
                future: _resolvePhotoFile(),
                builder: (context, snapshot) {
                  if (snapshot.hasData) {
                    final photoFile = snapshot.data!;
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: imageBuilder != null
                          ? imageBuilder!(photoFile)
                          : Image.file(
                              photoFile,
                              width: 60,
                              height: 60,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _buildPlaceholder(colors),
                            ),
                    );
                  }
                  return _buildPlaceholder(colors);
                },
              ),
              const SizedBox(width: 12),

              // Meal info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name or placeholder
                    Text(
                      meal.name ?? 'Meal',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colors.ink,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),

                    // Slot
                    if (meal.slot != null)
                      Text(
                        _formatSlot(meal.slot!),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.inkFaint,
                        ),
                      ),
                  ],
                ),
              ),

              // Kcal
              if (meal.kcal != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: colors.bg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colors.line),
                  ),
                  child: Text(
                    '${meal.kcal!.round()} kcal',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.ink,
                    ),
                  ),
                ),

              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: colors.inkFaint, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder(FathomColors colors) {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.line),
      ),
      child: Icon(
        Icons.restaurant_outlined,
        color: colors.inkFaint,
        size: 28,
      ),
    );
  }

  Future<File> _resolvePhotoFile() async {
    final root = rootOverride?.call() ?? await getApplicationSupportDirectory();
    return File('${root.path}/${meal.photoPath}');
  }

  String _formatSlot(String slot) {
    return slot[0].toUpperCase() + slot.substring(1);
  }
}
