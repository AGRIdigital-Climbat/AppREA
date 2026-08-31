import 'package:flutter/material.dart';

/// Envoltorio de una página del wizard: agrega scroll y desplaza el contenido.
///
/// Cada "página" del PageView usa este wrapper para poder hacer scroll
/// vertical dentro de un PageView horizontal.
class EdanSectionPage extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const EdanSectionPage({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: padding,
      child: child,
    );
  }
}
