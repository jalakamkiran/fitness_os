import 'package:flutter/material.dart';

class BpScaffold extends StatelessWidget {
  final Widget body;

  const BpScaffold({
    super.key,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: body),
    );
  }
}