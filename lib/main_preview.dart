import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'config/theme.dart';
import 'widgets/custom_button.dart';
import 'widgets/custom_text_field.dart';
import 'widgets/status_badge.dart';

void main() {
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.lightTheme,
    locale: const Locale('es', 'BO'),
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [
      Locale('es', 'BO'),
      Locale('en', 'US'),
    ],
    home: const PreviewScreen(),
  ));
}

class PreviewScreen extends StatelessWidget {
  const PreviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('EDAN - Widget Preview')),
      body: ListView(
        padding: const EdgeInsets.all(8),
        children: [
          _section('CustomButton'),
          Padding(
            padding: const EdgeInsets.all(16),
            child: CustomButton(
              text: 'Enviar Reporte',
              onPressed: () {},
              icon: Icons.send,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: CustomButton(
              text: 'Enviar Reporte',
              onPressed: () {},
              isLoading: true,
              icon: Icons.send,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: CustomButton(
              text: 'Cancelar',
              onPressed: () {},
              isOutlined: true,
            ),
          ),
          _section('CustomTextField'),
          const Padding(
            padding: EdgeInsets.all(16),
            child: CustomTextField(
              label: 'Nombre completo',
              hint: 'Ingrese su nombre',
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: CustomTextField(
              label: 'Nombre completo',
              hint: 'Ingrese su nombre',
              controller: TextEditingController(text: 'Carlos Rios'),
            ),
          ),
          _section('StatusBadge'),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: const [
                StatusBadge(text: 'Pendiente', color: AppColors.pending),
                StatusBadge(text: 'Sincronizado', color: AppColors.completed),
                StatusBadge(text: 'Error de sync', color: AppColors.error),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: AppColors.primary,
        ),
      ),
    );
  }
}
