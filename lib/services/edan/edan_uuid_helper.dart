import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

/// Helper centralizado para generar identificadores UUID y hashes de archivos
/// usados por la capa offline V2 de EDAN.
class EdanUuidHelper {
  EdanUuidHelper._();

  static const Uuid _uuid = Uuid();

  /// Genera un UUIDv4 (identidad de vida del registro).
  static String generarUuid() => _uuid.v4();

  /// Alias semántico para la cabecera/formulario.
  static String generarUuidEdanLocalidad() => generarUuid();

  /// Alias semántico para una fila de sección o vivienda.
  static String generarUuidRegistro() => generarUuid();

  /// Alias semántico para una fotografía.
  static String generarUuidFotografia() => generarUuid();

  /// Valida si [valor] tiene forma de UUID canónico (8-4-4-4-12 hex).
  /// A propósito NO exige versión 4 ni variante RFC: el servidor guarda
  /// `uuid_registro` reales fuera de v4 estricto (p. ej. variante `e`) y
  /// deben aceptarse igual; lo que se rechaza son los `id_seccion` legacy
  /// con prefijo (`po_…`), que nunca tienen esta forma.
  static bool esUuidValido(String? valor) {
    if (valor == null || valor.isEmpty) return false;
    const pattern =
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
        r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
    return RegExp(pattern).hasMatch(valor);
  }

  /// Calcula SHA-256 de un archivo local **en streaming** (por chunks, sin
  /// cargar los ~10 MB en RAM de una sola vez). Devuelve `null` si no existe.
  static Future<String?> sha256Archivo(String ruta) async {
    final file = File(ruta);
    if (!await file.exists()) return null;
    final sink = _DigestSink();
    final input = sha256.startChunkedConversion(sink);
    await for (final chunk in file.openRead()) {
      input.add(chunk);
    }
    input.close();
    final digest = sink.digest;
    return digest?.toString();
  }

  /// Calcula SHA-256 de bytes en memoria.
  static String sha256Bytes(Uint8List bytes) =>
      sha256.convert(bytes).toString();

  /// Genera un ID de dispositivo (uuid de instalación) o reutiliza el existente.
  /// El resultado se almacena en SQLite `config` bajo la clave `id_dispositivo`.
  static String generarIdDispositivo() => generarUuid();
}

/// Sink mínimo que conserva el [Digest] final de una conversión por chunks
/// (reemplaza a `AccumulatorSink`, no exportado por `crypto` 3.x).
class _DigestSink implements Sink<Digest> {
  Digest? digest;

  @override
  void add(Digest data) => digest = data;

  @override
  void close() {}
}
