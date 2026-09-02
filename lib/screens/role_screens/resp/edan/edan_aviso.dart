import 'package:flutter/material.dart';

/// Aviso naranja informativo que se muestra sobre una subsección del wizard
/// EDAN cuando hay un botón "Agregar". Mismo estilo que la advertencia de la
/// página 04: fondo ámbar claro, borde ámbar, icono de información.
class EdanAvisoAfectaciones extends StatelessWidget {
  final String texto;

  const EdanAvisoAfectaciones({super.key, required this.texto});

  @override
  Widget build(BuildContext context) {

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFFB300)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 18, color: Color(0xFFB26A00)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF6B4A00),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
