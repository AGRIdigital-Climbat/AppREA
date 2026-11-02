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

  /// Progreso del histórico del municipio (proceso propio del rol 6) para la
  /// franja de UGR: fase legible + `hechas de total` por EDAN procesado.
  /// `total == 0` = la lista todavía no llegó (el GET está en vuelo).
  final ValueNotifier<String> faseMunicipio = ValueNotifier('');
  final ValueNotifier<int> municipioTotal = ValueNotifier(0);
  final ValueNotifier<int> municipioHechas = ValueNotifier(0);


  /// Descarga los EDANs del municipio del usuario (todos los usuarios de ese
  /// municipio) y los guarda localmente. Se dispara tras login/registro de
  /// un rol UGR para que el nuevo responsable recupere el histórico.
  Future<void> recargarEdansMunicipio({
    required int idMunicipio,
    required int usuarioId,
  }) async {
    if (sincronizandoMunicipio.value) return;
    sincronizandoMunicipio.value = true;
    faseMunicipio.value = 'Consultando EDANs del municipio...';
    municipioTotal.value = 0;
    municipioHechas.value = 0;
    try {
      final lista = await ApiService.instance
          .listarEdansPorMunicipio(idMunicipio);
      municipioTotal.value = lista.length;
      faseMunicipio.value = 'Guardando histórico del municipio';
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
        // Se cuenta también el ítem que falló: lo que mide la barra es
        // avance del lote, no éxitos.
        municipioHechas.value = municipioHechas.value + 1;
      }
      await recargarPendientes();
    } catch (e) {
      debugPrint('Error cargando EDANs del municipio: $e');
    } finally {
      sincronizandoMunicipio.value = false;
      faseMunicipio.value = '';
      municipioTotal.value = 0;
      municipioHechas.value = 0;
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
