import 'package:flutter/foundation.dart';
import '../models/edan.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/database_helper.dart';

class EdanSyncService {
  static final EdanSyncService _instance = EdanSyncService._();
  static EdanSyncService get instance => _instance;
  EdanSyncService._();

  bool _isSyncing = false;

  final ValueNotifier<int> pendientes = ValueNotifier(0);
  final ValueNotifier<bool> sincronizando = ValueNotifier(false);
  final ValueNotifier<bool> sincronizandoMunicipio = ValueNotifier(false);

  bool get isSyncing => _isSyncing;

  /// Descarga los EDANs del municipio del usuario (todos los usuarios de ese
  /// municipio) y los guarda localmente. Se dispara tras login/registro de
  /// un rol UGR para que el nuevo responsable recupere el histórico.
  Future<void> recargarEdansMunicipio({
    required int idMunicipio,
    required int usuarioId,
  }) async {
    if (sincronizandoMunicipio.value) return;
    sincronizandoMunicipio.value = true;
    try {
      final lista = await ApiService.instance
          .listarEdansPorMunicipio(idMunicipio);
      for (final item in lista) {
        try {
          final edan = Edan.fromJson(item);
          final serverId = edan.idEdan ?? edan.idServer;
          if (serverId == null) continue;
          final existente =
              await DatabaseHelper.instance.getEdanByServerId(serverId);
          if (existente != null) {
            if (existente.pendienteActualizacion || !existente.sincronizado) {
              continue;
            }
            edan.idLocal = existente.idLocal;
            await DatabaseHelper.instance.updateEdan(edan);
            await DatabaseHelper.instance.markEdanAsSynced(
              existente.idLocal!,
              serverId,
            );
          } else {
            final idLocal = await DatabaseHelper.instance
                .insertEdan(edan, usuarioId: usuarioId);
            if (idLocal > 0) {
              await DatabaseHelper.instance
                  .markEdanAsSynced(idLocal, serverId);
            }
          }
        } catch (e) {
          debugPrint('Error cargando EDAN del municipio: $e');
        }
      }
      await recargarPendientes();
    } catch (e) {
      debugPrint('Error cargando EDANs del municipio: $e');
    } finally {
      sincronizandoMunicipio.value = false;
    }
  }

  Future<SyncResult> sincronizar() async {
    if (_isSyncing) {
      return SyncResult(
        exito: false,
        mensaje: 'Ya hay una sincronización en curso',
      );
    }

    _isSyncing = true;
    sincronizando.value = true;
    try {
      final userId = AuthService.instance.userId;
      if (userId == null) {
        return SyncResult(
          exito: false,
          mensaje: 'Usuario no autenticado',
        );
      }

      final result = SyncResult(exito: true);

      await _pullEdans(userId, result);
      await _pushDeletions(result);
      await _pushEdans(userId, result);

      return result;
    } catch (e) {
      debugPrint('Error en sincronización: $e');
      return SyncResult(
        exito: false,
        mensaje: 'Error: ${e.toString()}',
      );
    } finally {
      _isSyncing = false;
      sincronizando.value = false;
      await recargarPendientes();
    }
  }

  Future<void> recargarPendientes() async {
    try {
      pendientes.value =
          await DatabaseHelper.instance.countEdansPendientesSync();
    } catch (e) {
      debugPrint('Error recargando pendientes: $e');
    }
  }

  Future<void> _pullEdans(int userId, SyncResult result) async {
    try {
      final prefs = await DatabaseHelper.instance.getLastSyncDate();
      final fechaDesde = prefs != null ? DateTime.fromMillisecondsSinceEpoch(prefs) : null;

      final edansRemotos = await ApiService.instance.pullEdans(
        idUsuario: userId,
        fechaDesde: fechaDesde,
        skip: 0,
        limit: 100,
      );

      for (final edanJson in edansRemotos) {
        final edan = Edan.fromJson(edanJson);
        
        final existente = await DatabaseHelper.instance
            .getEdanByServerId(edan.idEdan ?? edan.idServer ?? 0);
        if (existente != null) {
          if (!existente.pendienteActualizacion && existente.sincronizado) {
            edan.idLocal = existente.idLocal;
            await DatabaseHelper.instance.updateEdan(edan);
            await DatabaseHelper.instance.markEdanAsSynced(
              existente.idLocal!,
              edan.idEdan ?? edan.idServer ?? existente.idServer ?? 0,
            );
          }
          result.actualizados++;
        } else {
          final idLocal = await DatabaseHelper.instance.insertEdan(edan, usuarioId: userId);
          final serverId = edan.idEdan ?? edan.idServer;
          if (serverId != null && idLocal > 0) {
            await DatabaseHelper.instance.markEdanAsSynced(idLocal, serverId);
          }
          result.creados++;
        }
      }

      if (edansRemotos.isNotEmpty) {
        await DatabaseHelper.instance.saveLastSyncDate(DateTime.now().millisecondsSinceEpoch);
      }
    } catch (e) {
      debugPrint('Error en pull: $e');
      result.mensaje = 'Error al recibir EDANs: ${e.toString()}';
      result.exito = false;
    }
  }

  Future<void> _pushDeletions(SyncResult result) async {
    try {
      final pendientes = await DatabaseHelper.instance.getEdansPendingDeletion();

      for (final edan in pendientes) {
        try {
          if (edan.idServer != null) {
            await ApiService.instance.deleteEdan(edan.idServer!);
          }
          await DatabaseHelper.instance.deleteEdan(edan.idLocal!);
          result.eliminados++;
        } catch (e) {
          debugPrint('Error eliminando EDAN ${edan.idLocal}: $e');
          result.fallidos++;
        }
      }
    } catch (e) {
      debugPrint('Error en push de eliminaciones: $e');
      result.mensaje = 'Error al eliminar EDANs: ${e.toString()}';
      result.exito = false;
    }
  }

  Future<void> _pushEdans(int userId, SyncResult result) async {
    try {
      final edansPendientes = await DatabaseHelper.instance.getUnsyncedEdans();
      
      if (edansPendientes.isEmpty) {
        return;
      }

      final edansJson = edansPendientes.map((e) {
        final json = e.toJson();
        json['id_usuario'] = userId;
        return json;
      }).toList();
      final porIdLocal = <int, Edan>{
        for (final e in edansPendientes)
          if (e.idLocal != null) e.idLocal!: e,
      };

      final respuesta = await ApiService.instance.syncEdans(edansJson);

      final datos = respuesta['data'];
      final items = datos is List ? datos : <dynamic>[];

      for (final item in items) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);
        final idLocal = _parseId(m['id_local']);
        final aplicado = m['aplicado'] == true;

        if (aplicado && idLocal != null) {
          final idServer = _parseId(m['id_edan']);
          if (idServer != null) {
            await DatabaseHelper.instance.markEdanAsSynced(idLocal, idServer);
            result.enviados++;
          }
          continue;
        }

        if (idLocal != null) {
          final error = _extractError(m);
          final errorTexto = error.toLowerCase();
          final esColisionCodigo = errorTexto.contains('codigo') &&
              (errorTexto.contains('unique') ||
                  errorTexto.contains('duplic') ||
                  errorTexto.contains('ya existe'));
          final edan = porIdLocal[idLocal];
          if (esColisionCodigo && edan != null) {
            final reintentado = await _regenerarCodigoYReintentar(edan, userId);
            if (reintentado) {
              result.enviados++;
            } else {
              result.fallidos++;
            }
          } else {
            final intentos = _parseId(m['intentos']) ?? 0;
            await DatabaseHelper.instance.updateEdanSyncAttempts(
              idLocal,
              intentos + 1,
              error,
            );
            result.fallidos++;
          }
        } else {
          result.fallidos++;
        }
      }
    } catch (e) {
      debugPrint('Error en push: $e');
      result.mensaje = 'Error al enviar EDANs: ${e.toString()}';
      result.exito = false;
    }
  }

  Future<bool> _regenerarCodigoYReintentar(Edan edan, int userId) async {
    try {
      final db = DatabaseHelper.instance;
      final municipioId =
          edan.idMunicipio ?? AuthService.instance.currentToken?.idMunicipio;
      final codigoIne = municipioId != null
          ? (await db.getCodigoIneMunicipio(municipioId)) ?? '000'
          : '000';
      final nuevoCodigo = await db.generarSiguienteCodigoEdan(
        year: DateTime.now().year,
        municipioId: municipioId ?? 0,
        codigoIne: codigoIne,
      );
      edan.codigoEdan = nuevoCodigo;
      await db.updateEdan(edan);

      final json = edan.toJson();
      json['id_usuario'] = userId;
      final respuesta = await ApiService.instance.syncEdans([json]);
      final datos = respuesta['data'];
      final items = datos is List ? datos : <dynamic>[];
      var aplicado = false;
      for (final item in items) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);
        if (m['aplicado'] == true) {
          aplicado = true;
          final idLocal = _parseId(m['id_local']);
          final idServer = _parseId(m['id_edan']);
          if (idLocal != null && idServer != null) {
            await DatabaseHelper.instance.markEdanAsSynced(idLocal, idServer);
          }
        }
      }
      return aplicado;
    } catch (e) {
      debugPrint(
          'Error reintentando EDAN ${edan.idLocal} tras colisión de código: $e');
      return false;
    }
  }
}

class SyncResult {
  bool exito;
  String mensaje;
  int creados = 0;
  int actualizados = 0;
  int enviados = 0;
  int fallidos = 0;
  int eliminados = 0;

  SyncResult({
    required this.exito,
    this.mensaje = '',
  });

  String get resumen {
    if (!exito) return mensaje;
    
    final partes = <String>[];
    if (creados > 0) partes.add('$creados creados');
    if (actualizados > 0) partes.add('$actualizados actualizados');
    if (enviados > 0) partes.add('$enviados enviados');
    if (eliminados > 0) partes.add('$eliminados eliminados');
    if (fallidos > 0) partes.add('$fallidos fallidos');
    
    if (partes.isEmpty) return 'Sin cambios';
    return 'Sincronización completada: ${partes.join(', ')}';
  }
}

int? _parseId(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  return int.tryParse(value.toString());
}

String _extractError(Map<String, dynamic> m) {
  final directo = m['error'];
  if (directo is String && directo.isNotEmpty) return directo;
  final data = m['data'];
  if (data is Map) {
    final ultimo = data['ultimo_error'];
    if (ultimo is String && ultimo.isNotEmpty) return ultimo;
  }
  return 'Error de sincronización';
}
