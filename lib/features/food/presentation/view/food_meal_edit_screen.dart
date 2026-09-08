import 'dart:io';
import 'dart:typed_data';

import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'package:fitness_os/features/food/data/food_meal_store.dart';
import 'package:fitness_os/features/food/domain/food_meal.dart';

/// Edit screen for existing meals: edit metadata, replace photo, or delete.
class FoodMealEditScreen extends StatefulWidget {
  const FoodMealEditScreen({
    required this.meal,
    required this.store,
    required this.imagePicker,
    this.processImage,
    this.pickOverride,
    this.syncPickOverride,
    this.imageBuilder,
    this.rootOverride,
    super.key,
  });

  final FoodMeal meal;
  final FoodMealStore store;
  final ImagePicker imagePicker;
  final Future<Uint8List> Function(File)? processImage;

  /// Async pick override (production-like). Prefer [syncPickOverride] in widget tests.
  final Future<File?> Function(ImageSource source)? pickOverride;

  /// Sync pick override for widget tests (avoids async InkWell hang).
  final File? Function(ImageSource source)? syncPickOverride;

  /// Test seam: bypass [Image.file] decode in widget tests.
  final Widget Function(File)? imageBuilder;

  /// Test seam: override root directory for photo paths.
  final Directory? Function()? rootOverride;

  @override
  State<FoodMealEditScreen> createState() => _FoodMealEditScreenState();
}

class _FoodMealEditScreenState extends State<FoodMealEditScreen> {
  late TextEditingController _nameController;
  late TextEditingController _noteController;
  late TextEditingController _kcalController;
  String? _selectedSlot;
  File? _newPhoto;
  bool _isSaving = false;

  static const _mealSlots = ['Breakfast', 'Lunch', 'Dinner', 'Snack'];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.meal.name ?? '');
    _noteController = TextEditingController(text: widget.meal.note ?? '');
    _kcalController = TextEditingController(
      text: widget.meal.kcal != null ? widget.meal.kcal!.toString() : '',
    );
    _selectedSlot = widget.meal.slot != null 
        ? _formatSlot(widget.meal.slot!)
        : null;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _noteController.dispose();
    _kcalController.dispose();
    super.dispose();
  }

  String _formatSlot(String slot) {
    return slot[0].toUpperCase() + slot.substring(1);
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final File? selected;
      final sync = widget.syncPickOverride;
      if (sync != null) {
        selected = sync(source);
      } else if (widget.pickOverride != null) {
        selected = await widget.pickOverride!(source);
      } else {
        final pickedFile = await widget.imagePicker.pickImage(source: source);
        selected = pickedFile == null ? null : File(pickedFile.path);
      }
      if (selected == null) return;

      if (!mounted) return;
      setState(() {
        _newPhoto = selected;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pick image: $e')),
      );
    }
  }

  Future<void> _saveMeal() async {
    setState(() => _isSaving = true);

    try {
      final name = _nameController.text.trim();
      final note = _noteController.text.trim();
      final kcalText = _kcalController.text.trim();
      final kcal = kcalText.isEmpty ? null : double.tryParse(kcalText);

      final updatedMeal = widget.meal.copyWith(
        name: name.isEmpty ? null : name,
        note: note.isEmpty ? null : note,
        kcal: kcal,
        slot: _selectedSlot?.toLowerCase(),
      );

      if (_newPhoto != null) {
        // Replace photo
        final processor = widget.processImage ?? _defaultProcessImage;
        final processedBytes = await processor(_newPhoto!);
        await widget.store.replacePhoto(updatedMeal, processedBytes);
      } else {
        // Update metadata only
        await widget.store.update(updatedMeal);
      }

      if (!mounted) return;
      Navigator.pop(context, true); // Return true to signal update
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save changes: $e')),
      );
    }
  }

  Future<void> _deleteMeal() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete meal'),
        content: const Text('Are you sure you want to delete this meal?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await widget.store.delete(widget.meal.id);
      if (!mounted) return;
      Navigator.pop(context, true); // Return true to signal update
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete meal: $e')),
      );
    }
  }

  Future<Uint8List> _defaultProcessImage(File file) async {
    final bytes = await file.readAsBytes();
    final image = img.decodeImage(bytes);
    if (image == null) {
      throw Exception('Failed to decode image');
    }
    final stripped = img.encodeJpg(image, quality: 85);
    return Uint8List.fromList(stripped);
  }

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: colors.ink),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Edit meal',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: colors.ink,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _saveMeal,
            child: _isSaving
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(colors.accent),
                    ),
                  )
                : Text(
                    'Save',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.accent,
                    ),
                  ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Photo preview
            _buildPhotoPreview(colors, theme),
            const SizedBox(height: 8),
            _buildReplacePhotoButton(colors, theme),
            const SizedBox(height: 32),

            // Fields
            _buildFieldsSection(colors, theme),
            const SizedBox(height: 32),

            // Delete button
            _buildDeleteButton(colors, theme),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoPreview(FathomColors colors, ThemeData theme) {
    final photoFile = _newPhoto ?? _resolvePhotoFile();

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: FutureBuilder<File>(
        future: photoFile is Future<File> ? photoFile : Future.value(photoFile),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return widget.imageBuilder != null
                ? widget.imageBuilder!(snapshot.data!)
                : Image.file(
                    snapshot.data!,
                    height: 240,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _buildPhotoPlaceholder(colors),
                  );
          }
          return _buildPhotoPlaceholder(colors);
        },
      ),
    );
  }

  Widget _buildPhotoPlaceholder(FathomColors colors) {
    return Container(
      height: 240,
      decoration: BoxDecoration(
        color: colors.bgElev,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.line),
      ),
      child: Icon(
        Icons.restaurant_outlined,
        size: 64,
        color: colors.inkFaint,
      ),
    );
  }

  Widget _buildReplacePhotoButton(FathomColors colors, ThemeData theme) {
    return TextButton.icon(
      onPressed: () {
        showModalBottomSheet(
          context: context,
          builder: (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.camera_alt_outlined),
                  title: const Text('Take photo'),
                  onTap: () {
                    Navigator.pop(context);
                    _pickImage(ImageSource.camera);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Choose from gallery'),
                  onTap: () {
                    Navigator.pop(context);
                    _pickImage(ImageSource.gallery);
                  },
                ),
              ],
            ),
          ),
        );
      },
      icon: Icon(Icons.refresh, size: 18, color: colors.accent),
      label: Text(
        'Replace photo',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: colors.accent,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildFieldsSection(FathomColors colors, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Meal details',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: colors.ink,
          ),
        ),
        const SizedBox(height: 16),

        // Name field
        _buildTextField(
          colors,
          theme,
          controller: _nameController,
          label: 'Meal name',
          hint: 'e.g., Chicken salad',
        ),
        const SizedBox(height: 16),

        // Kcal field
        _buildTextField(
          colors,
          theme,
          controller: _kcalController,
          label: 'Calories (kcal)',
          hint: 'e.g., 450',
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 16),

        // Meal slot dropdown
        _buildMealSlotDropdown(colors, theme),
        const SizedBox(height: 16),

        // Note field
        _buildTextField(
          colors,
          theme,
          controller: _noteController,
          label: 'Notes',
          hint: 'Optional notes about this meal',
          maxLines: 3,
        ),
      ],
    );
  }

  Widget _buildTextField(
    FathomColors colors,
    ThemeData theme, {
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType? keyboardType,
    int? maxLines,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: colors.ink,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines ?? 1,
          style: theme.textTheme.bodyMedium?.copyWith(color: colors.ink),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: theme.textTheme.bodyMedium?.copyWith(
              color: colors.inkFaint,
            ),
            filled: true,
            fillColor: colors.bgElev,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: colors.line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: colors.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: colors.accent, width: 2),
            ),
            contentPadding: const EdgeInsets.all(12),
          ),
        ),
      ],
    );
  }

  Widget _buildMealSlotDropdown(FathomColors colors, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Meal time',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: colors.ink,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: colors.bgElev,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.line),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedSlot,
              isExpanded: true,
              hint: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'Select meal time',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.inkFaint,
                  ),
                ),
              ),
              icon: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Icon(Icons.arrow_drop_down, color: colors.ink),
              ),
              style: theme.textTheme.bodyMedium?.copyWith(color: colors.ink),
              dropdownColor: colors.bgElev,
              items: _mealSlots.map((slot) {
                return DropdownMenuItem(
                  value: slot,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(slot),
                  ),
                );
              }).toList(),
              onChanged: (value) {
                setState(() => _selectedSlot = value);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDeleteButton(FathomColors colors, ThemeData theme) {
    return OutlinedButton.icon(
      onPressed: _deleteMeal,
      icon: const Icon(Icons.delete_outline),
      label: const Text('Delete meal'),
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.hot,
        side: BorderSide(color: colors.hot),
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  dynamic _resolvePhotoFile() {
    if (_newPhoto != null) return _newPhoto;
    
    return Future(() async {
      final root = widget.rootOverride?.call() ?? await getApplicationSupportDirectory();
      return File('${root.path}/${widget.meal.photoPath}');
    });
  }
}
