import 'dart:convert';
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

  bool get isSyncing => _isSyncing;

  Future<SyncResult> sincronizar() async {
    if (_isSyncing) {
      return SyncResult(
        exito: false,
        mensaje: 'Ya hay una sincronización en curso',
      );
    }

    _isSyncing = true;
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
        
        final existente = await DatabaseHelper.instance.getEdanByServerId(edan.idServer ?? 0);
        if (existente != null) {
          await DatabaseHelper.instance.updateEdan(edan);
          result.actualizados++;
        } else {
          await DatabaseHelper.instance.insertEdan(edan, usuarioId: userId);
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

      final respuesta = await ApiService.instance.syncEdans(edansJson);

      final datos = respuesta['data'] as Map<String, dynamic>?;
      final procesados = datos?['procesados'] as List? ?? [];
      final fallidos = datos?['fallidos'] as List? ?? [];

      for (final item in procesados) {
        final idLocal = item['id_local'] as int?;
        final idServer = item['id_server'] as int?;
        
        if (idLocal != null && idServer != null) {
          await DatabaseHelper.instance.markEdanAsSynced(idLocal, idServer);
          result.enviados++;
        }
      }

      for (final item in fallidos) {
        final idLocal = item['id_local'] as int?;
        final error = item['error'] as String?;
        
        if (idLocal != null) {
          final intentos = (item['intentos'] as int?) ?? 0;
          await DatabaseHelper.instance.updateEdanSyncAttempts(
            idLocal,
            intentos + 1,
            error ?? 'Error desconocido',
          );
          result.fallidos++;
        }
      }
    } catch (e) {
      debugPrint('Error en push: $e');
      result.mensaje = 'Error al enviar EDANs: ${e.toString()}';
      result.exito = false;
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
    if (fallidos > 0) partes.add('$fallidos fallidos');
    
    if (partes.isEmpty) return 'Sin cambios';
    return 'Sincronización completada: ${partes.join(', ')}';
  }
}
