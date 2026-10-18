import 'package:flutter/foundation.dart';
import '../models/edan.dart';
import '../services/api_service.dart';
import '../services/database_helper.dart';

class EdanSyncService {
  static final EdanSyncService _instance = EdanSyncService._();
  static EdanSyncService get instance => _instance;
  EdanSyncService._();


  final ValueNotifier<int> pendientes = ValueNotifier(0);
  final ValueNotifier<bool> sincronizando = ValueNotifier(false);
  final ValueNotifier<bool> sincronizandoMunicipio = ValueNotifier(false);


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

  Future<void> recargarPendientes() async {
    try {
      pendientes.value =
          await DatabaseHelper.instance.countEdansPendientesSync();
    } catch (e) {
      debugPrint('Error recargando pendientes: $e');
    }
  }

}
