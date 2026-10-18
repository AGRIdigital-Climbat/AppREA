import 'dart:io';

import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';

/// Un hallazgo del diagnóstico de pendientes (para el botón debug del AppBar).
///
/// Dice QUÉ está atascado y POR QUÉ, en lenguaje accionable, para no tener
/// que adivinar entre "sin cambios" y el badge marcado.
class DiagnosticoPendiente {
  const DiagnosticoPendiente({
    required this.titulo,
    required this.motivo,
    this.nivel = 'aviso',
  });

  /// Qué está pendiente (formulario, cola, foto...).
  final String titulo;

  /// Por qué no avanza (dueña sin confirmar, backoff, 401, huérfana...).
  final String motivo;

  /// `ok` (verde), `aviso` (naranja) o `error` (rojo).
  final String nivel;
}

/// Lee SQLite (solo lectura + `File.exists`) y explica cada trabajo pendiente
/// del sync: formularios por enviar, cola con su estado/intentos/error,
/// fotos bloqueadas por su dueña, archivo ausente o backoff, y borrados por
/// propagar. Si no hay nada, devuelve un único `ok`.
Future<List<DiagnosticoPendiente>> diagnosticarPendientes({
  DatabaseHelper? dbHelper,
}) async {
  final helper = dbHelper ?? DatabaseHelper.instance;
  final out = <DiagnosticoPendiente>[];
  final Database db;
  try {
    db = await helper.database;
  } catch (e) {
    return [
      DiagnosticoPendiente(
        titulo: 'Base de datos',
        motivo: 'No se pudo abrir SQLite: $e',
        nivel: 'error',
      )
    ];
  }

  // 1) Formularios por enviar (el motor los empuja directo por /completo).
  try {
    final forms = await db.query(
      'formularios',
      columns: [
        'uuid_edan_localidad',
        'localidad',
        'id_edan_localidad_estado',
        'pending_submit',
        'estado_destino',
      ],
      where: 'pendiente_push = 1',
      orderBy: 'fecha_modificacion DESC',
      limit: 50,
    );
    for (final f in forms) {
      final nombre = f['localidad'] as String?;
      final tituloNombre =
          (nombre == null || nombre.isEmpty) ? '(sin nombre)' : nombre;
      final extras = <String>[
        'estado ${f['id_edan_localidad_estado'] ?? '?'}',
        if ((f['pending_submit'] as num?)?.toInt() == 1)
          'envío pendiente${f['estado_destino'] != null ? ' → estado ${f['estado_destino']}' : ''}',
      ];
      out.add(DiagnosticoPendiente(
        titulo: 'Formulario por enviar: $tituloNombre',
        motivo: 'Se subirá por POST /completo en el próximo sync '
            '(${extras.join(' · ')}). Si el sync dice "sin cambios", el push '
            'está fallando: ver el detalle del error abajo.',
      ));
    }
  } catch (_) {}

  // 2) Cola de sincronización (D pendientes, rechazos).
  try {
    final cola = await db.query(
      'cola_sincronizacion',
      orderBy: 'fecha_registro ASC',
      limit: 100,
    );
    for (final c in cola) {
      final tabla = c['tabla'] ?? '?';
      final accion = c['accion'] ?? '?';
      final uuid = (c['uuid_registro'] as String?) ?? '?';
      final estado = (c['estado'] as String?) ?? '?';
      final intentos = (c['intentos'] as num?)?.toInt() ?? 0;
      final error = (c['ultimo_error'] as String?) ?? '';
      final proximo = (c['fecha_proximo_intento'] as String?) ?? '';
      final corta =
          uuid.length > 13 ? '${uuid.substring(0, 13)}…' : uuid;
      switch (estado) {
        case 'pendiente':
        case 'subiendo':
          out.add(DiagnosticoPendiente(
            titulo: 'En cola: $tabla $accion $corta',
            motivo: 'Estado $estado, $intentos intento(s)'
                '${error.isNotEmpty ? ' · último error: $error' : ''}'
                '${proximo.isNotEmpty ? ' · reintenta después de $proximo' : ''}',
          ));
        case 'conflicto':
          // LWW: estado imposible (el servidor ya no devuelve 409). Se trata
          // como pendiente reintentable genérico para no dejarlo sin explicar.
          out.add(DiagnosticoPendiente(
            titulo: 'En cola: $tabla $accion $corta',
            motivo: 'Estado conflicto heredado, $intentos intento(s)'
                '${error.isNotEmpty ? ' · último error: $error' : ''}'
                '${proximo.isNotEmpty ? ' · reintenta después de $proximo' : ''}',
          ));
        case 'rechazado':
          out.add(DiagnosticoPendiente(
            titulo: 'Rechazado: $tabla $corta',
            motivo: 'Dato o regla inválida (no reintenta solo): '
                '${error.isNotEmpty ? error : '(sin detalle)'}',
            nivel: 'error',
          ));
        default:
          out.add(DiagnosticoPendiente(
            titulo: 'En cola ($estado): $tabla $corta',
            motivo: error.isNotEmpty ? error : 'estado $estado',
          ));
      }
    }
  } catch (_) {}

  // 3) Fotos en cola: dueña, archivo y backoff, uno por uno.
  try {
    final fotos = await db.query(
      'cola_fotos',
      orderBy: 'intentos ASC',
      limit: 100,
    );
    for (final f in fotos) {
      final uuid = (f['uuid_fotografia'] as String?) ?? '?';
      final corta =
          uuid.length > 13 ? '${uuid.substring(0, 13)}…' : uuid;
      final duena = (f['uuid_registro'] as String?) ?? '';
      final estado = (f['estado'] as String?) ?? '?';
      final intentos = (f['intentos'] as num?)?.toInt() ?? 0;
      final error = (f['ultimo_error'] as String?) ?? '';
      final proximo = (f['fecha_proximo_intento'] as String?) ?? '';
      final ruta = (f['ruta_local'] as String?) ?? '';

      var duenaTxt = 'dueña $duena';
      var confirmada = false;
      if (duena.isNotEmpty) {
        final s = await db.query(
          'filas_seccion',
          columns: ['estado_sync'],
          where: 'uuid_registro = ?',
          whereArgs: [duena],
          limit: 1,
        );
        if (s.isEmpty) {
          final v = await db.query(
            'viviendas',
            columns: ['uuid_registro'],
            where: 'uuid_registro = ?',
            whereArgs: [duena],
            limit: 1,
          );
          duenaTxt = v.isEmpty
              ? 'SIN FILA DUEÑA (huérfana: se purgará si no hay nada por guardar)'
              : 'dueña vivienda (ver estado de su fila padre)';
          if (v.isNotEmpty) {
            final padre = await db.rawQuery(
              'SELECT s.estado_sync AS e FROM filas_seccion s '
              'JOIN viviendas vv ON vv.uuid_dano_vivienda = s.uuid_registro '
              'WHERE vv.uuid_registro = ? LIMIT 1',
              [duena],
            );
            confirmada = padre.isNotEmpty && padre.first['e'] == 'confirmado';
            duenaTxt += confirmada ? ' confirmada' : ' SIN confirmar';
          }
        } else {
          confirmada = s.first['estado_sync'] == 'confirmado';
          duenaTxt += confirmada ? ' confirmada' : ' SIN confirmar';
        }
      }
      var archivoTxt = 'archivo ?';
      if (ruta.isNotEmpty) {
        try {
          archivoTxt =
              await File(ruta).exists() ? 'archivo OK' : 'ARCHIVO AUSENTE';
        } catch (_) {
          archivoTxt = 'archivo ?';
        }
      }
      final esError = estado == 'rechazado' ||
          (!confirmada && duena.isNotEmpty) ||
          archivoTxt == 'ARCHIVO AUSENTE';
      out.add(DiagnosticoPendiente(
        titulo: 'Foto en cola: $corta',
        motivo: '$duenaTxt · $archivoTxt · estado $estado, '
            '$intentos intento(s)'
            '${error.isNotEmpty ? ' · $error' : ''}'
            '${proximo.isNotEmpty ? ' · reintenta después de $proximo' : ''}'
            '${!confirmada && duena.isNotEmpty ? ' → sube cuando su fila se confirme (sincronice el formulario primero)' : ''}',
        nivel: esError ? 'error' : 'aviso',
      ));
    }
  } catch (_) {}

  // 4) Borrados de foto por propagar.
  try {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM fotografias '
      "WHERE borrado_logico = 1 AND ruta_servidor IS NOT NULL AND ruta_servidor != ''",
    );
    final n = (rows.first['c'] as num?)?.toInt() ?? 0;
    if (n > 0) {
      out.add(DiagnosticoPendiente(
        titulo: 'Borrados de foto por propagar: $n',
        motivo: 'Viajan como DELETE /fotografias en el próximo sync.',
      ));
    }
  } catch (_) {}

  // 5) Watermark (para saber desde dónde reanuda el pull).
  try {
    final wm = await helper.getConfig('sync_watermark_v2');
    out.add(DiagnosticoPendiente(
      titulo: 'Watermark del pull',
      motivo: (wm == null || wm.isEmpty)
          ? 'vacío: el próximo pull será restauración completa'
          : wm,
      nivel: 'ok',
    ));
  } catch (_) {}

  if (out.length == 1) {
    // Solo quedó el watermark: nada pendiente.
    return [
      const DiagnosticoPendiente(
        titulo: 'Sin trabajo pendiente',
        motivo: 'Colas vacías y ningún formulario por enviar. Si el listado '
            'muestra "pendiente", es la tarjeta (snapshot) y no la DB: '
            'recargue la pestaña.',
        nivel: 'ok',
      ),
      out.first,
    ];
  }
  return out;
}
