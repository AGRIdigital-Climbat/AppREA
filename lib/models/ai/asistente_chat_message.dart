class AsistenteFuente {
  final int documentoId;
  final String titulo;
  final String tipo;
  final List<String> numerals;
  final double similitud;

  const AsistenteFuente({
    required this.documentoId,
    required this.titulo,
    required this.tipo,
    required this.numerals,
    required this.similitud,
  });

  factory AsistenteFuente.fromJson(Map<String, dynamic> json) =>
      AsistenteFuente(
        documentoId: json['documento_id'] as int,
        titulo: json['titulo'] as String? ?? '',
        tipo: json['tipo'] as String? ?? '',
        numerals: (json['numerals'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
        similitud: (json['similitud'] as num?)?.toDouble() ?? 0,
      );
}

class AsistenteCita {
  final int documentoId;
  final String titulo;
  final String numeral;

  const AsistenteCita({
    required this.documentoId,
    required this.titulo,
    required this.numeral,
  });

  factory AsistenteCita.fromJson(Map<String, dynamic> json) => AsistenteCita(
        documentoId: json['documento_id'] as int,
        titulo: json['titulo'] as String? ?? '',
        numeral: json['numeral'] as String? ?? '',
      );
}

class AsistenteChatMessage {
  final String role;
  final String content;
  final List<AsistenteFuente>? fuentes;
  final Map<String, AsistenteCita>? citas;

  const AsistenteChatMessage({
    required this.role,
    required this.content,
    this.fuentes,
    this.citas,
  });

  Map<String, String> toMap() => {'role': role, 'content': content};
}
