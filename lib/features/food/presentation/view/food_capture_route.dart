import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import 'package:fitness_os/app/routing/app_router.dart';
import 'package:fitness_os/features/food/data/food_meal_store.dart';
import 'package:fitness_os/features/food/data/food_notification_scheduler.dart';
import 'package:fitness_os/features/food/presentation/view/food_capture_screen.dart';

class FoodCaptureRoute {
  static const String path = '/food_capture';

  static void register() {
    AppRouter.register(
      path,
      (context) {
        // Extract slot from route arguments if present
        final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
        final slot = args?['slot'] as String?;
        
        return FoodCaptureScreen(
          store: GetIt.I<FoodMealStore>(),
          scheduler: GetIt.I<FoodNotificationScheduler>(),
          imagePicker: ImagePicker(),
          processImage: FoodCaptureRoute.stripExifAndCompress,
          initialSlot: slot,
        );
      },
    );
  }

  static void go(BuildContext context, {String? slot}) {
    Navigator.pushNamed(
      context, 
      path,
      arguments: slot != null ? {'slot': slot} : null,
    );
  }

  /// Strip EXIF data and re-compress JPEG to remove metadata.
  static Future<Uint8List> stripExifAndCompress(File file) async {
    final bytes = await file.readAsBytes();
    
    // Decode image
    final image = img.decodeImage(bytes);
    if (image == null) {
      throw Exception('Failed to decode image');
    }

    // Re-encode as JPEG without metadata (quality 85 for size/quality balance)
    final stripped = img.encodeJpg(image, quality: 85);
    return Uint8List.fromList(stripped);
  }
}
