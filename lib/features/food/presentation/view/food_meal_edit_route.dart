import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:image_picker/image_picker.dart';

import 'package:fitness_os/app/routing/app_router.dart';
import 'package:fitness_os/features/food/data/food_meal_store.dart';
import 'package:fitness_os/features/food/domain/food_meal.dart';
import 'package:fitness_os/features/food/presentation/view/food_meal_edit_screen.dart';

class FoodMealEditRoute {
  static const String path = '/food_meal_edit';

  static void register() {
    AppRouter.register(
      path,
      (context) {
        final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
        final meal = args['meal'] as FoodMeal;
        
        return FoodMealEditScreen(
          meal: meal,
          store: GetIt.I<FoodMealStore>(),
          imagePicker: ImagePicker(),
          processImage: args['processImage'] as Future<Uint8List> Function(File)?,
        );
      },
    );
  }

  static void go(BuildContext context, FoodMeal meal, {Future<Uint8List> Function(File)? processImage}) {
    Navigator.pushNamed(
      context,
      path,
      arguments: {
        'meal': meal,
        'processImage': processImage,
      },
    );
  }
}
