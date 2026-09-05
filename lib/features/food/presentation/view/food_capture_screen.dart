import 'dart:io';
import 'dart:typed_data';

import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:fitness_os/features/food/data/food_meal_store.dart';
import 'package:fitness_os/features/food/domain/food_meal.dart';

/// Food capture screen: camera/gallery → optional fields → save.
class FoodCaptureScreen extends StatefulWidget {
  const FoodCaptureScreen({
    required this.store,
    required this.imagePicker,
    required this.processImage,
    this.pickOverride,
    this.syncPickOverride,
    this.imageBuilder,
    super.key,
  });

  final FoodMealStore store;
  final ImagePicker imagePicker;
  final Future<Uint8List> Function(File) processImage;

  /// Async pick override (production-like). Prefer [syncPickOverride] in widget tests.
  final Future<File?> Function(ImageSource source)? pickOverride;

  /// Sync pick override for widget tests (avoids async InkWell hang).
  final File? Function(ImageSource source)? syncPickOverride;

  /// Test seam: bypass [Image.file] decode in widget tests.
  final Widget Function(File)? imageBuilder;

  @override
  State<FoodCaptureScreen> createState() => _FoodCaptureScreenState();
}

class _FoodCaptureScreenState extends State<FoodCaptureScreen> {
  File? _selectedPhoto;
  final _nameController = TextEditingController();
  final _noteController = TextEditingController();
  final _kcalController = TextEditingController();
  String? _selectedSlot;
  bool _isSaving = false;

  static const _mealSlots = ['Breakfast', 'Lunch', 'Dinner', 'Snack'];

  @override
  void dispose() {
    _nameController.dispose();
    _noteController.dispose();
    _kcalController.dispose();
    super.dispose();
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
        _selectedPhoto = selected;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pick image: $e')),
      );
    }
  }

  Future<void> _saveMeal() async {
    if (_selectedPhoto == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a photo first')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      // Strip EXIF and compress
      final processedBytes = await widget.processImage(_selectedPhoto!);

      // Create meal with local capture time
      final now = DateTime.now();
      final dayKey = _formatDayKey(now);
      final id = _generateMealId(now);

      final name = _nameController.text.trim();
      final note = _noteController.text.trim();
      final kcalText = _kcalController.text.trim();
      final kcal = kcalText.isEmpty ? null : double.tryParse(kcalText);

      final meal = FoodMeal(
        id: id,
        dayKey: dayKey,
        capturedAtMs: now.millisecondsSinceEpoch,
        photoPath: 'food/meals/$dayKey/$id.jpg',
        name: name.isEmpty ? null : name,
        note: note.isEmpty ? null : note,
        kcal: kcal,
        slot: _selectedSlot?.toLowerCase(),
      );

      await widget.store.save(meal, processedBytes);

      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save meal: $e')),
      );
    }
  }

  String _formatDayKey(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  String _generateMealId(DateTime now) {
    return '${now.millisecondsSinceEpoch}';
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
          'Log meal',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: colors.ink,
          ),
        ),
        actions: [
          if (_selectedPhoto != null)
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
            // Photo section
            if (_selectedPhoto == null) ...[
              _buildPhotoPlaceholder(colors, theme),
              const SizedBox(height: 16),
              _buildImageSourceButtons(colors, theme),
            ] else ...[
              _buildPhotoPreview(colors),
              const SizedBox(height: 8),
              _buildChangePhotoButton(colors, theme),
            ],

            const SizedBox(height: 32),

            // Optional fields
            _buildOptionalFieldsSection(colors, theme),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoPlaceholder(FathomColors colors, ThemeData theme) {
    return Container(
      height: 240,
      decoration: BoxDecoration(
        color: colors.bgElev,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.line, width: 2),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.add_a_photo_outlined,
            size: 64,
            color: colors.inkFaint,
          ),
          const SizedBox(height: 16),
          Text(
            'Add a photo of your meal',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: colors.inkFaint,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageSourceButtons(FathomColors colors, ThemeData theme) {
    return Row(
      children: [
        Expanded(
          child: _buildSourceButton(
            colors,
            theme,
            label: 'Camera',
            icon: Icons.camera_alt_outlined,
            onTap: () => _pickImage(ImageSource.camera),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildSourceButton(
            colors,
            theme,
            label: 'Gallery',
            icon: Icons.photo_library_outlined,
            onTap: () => _pickImage(ImageSource.gallery),
          ),
        ),
      ],
    );
  }

  Widget _buildSourceButton(
    FathomColors colors,
    ThemeData theme, {
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: colors.accent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              Icon(icon, color: colors.bg, size: 32),
              const SizedBox(height: 8),
              Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.bg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoPreview(FathomColors colors) {
    final photo = _selectedPhoto!;
    
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: widget.imageBuilder != null
          ? widget.imageBuilder!(photo)
          : Image.file(
              photo,
              height: 240,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
    );
  }

  Widget _buildChangePhotoButton(FathomColors colors, ThemeData theme) {
    return TextButton.icon(
      onPressed: () {
        setState(() => _selectedPhoto = null);
      },
      icon: Icon(Icons.refresh, size: 18, color: colors.accent),
      label: Text(
        'Change photo',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: colors.accent,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildOptionalFieldsSection(FathomColors colors, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Optional details',
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
}
