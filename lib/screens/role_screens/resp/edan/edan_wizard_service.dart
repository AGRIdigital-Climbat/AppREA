import 'package:flutter/foundation.dart';

import '../../../../models/edan.dart';
import '../../../../services/auth_service.dart';
import '../../../../services/database_helper.dart';
import 'edan_seccion_estado.dart';

/// Servicio del wizard: gestiona la persistencia de una localidad EDAN
/// y el estado de guardado de cada sección.
class EdanWizardService {
  final DatabaseHelper _db;

  EdanWizardService({DatabaseHelper? db}) : _db = db ?? DatabaseHelper.instance;

  /// Guarda la localidad actual (crea si no tiene idLocal, o actualiza).
  Future<String?> persistir(EdanLocalidad localidad, {int? usuarioId}) async {
    if (localidad.idLocal != null) {
      await _db.updateLocalidad(localidad);
      return localidad.idLocal;
    }
    if (usuarioId == null) return null;
    final id = await _db.insertLocalidad(localidad, usuarioId: usuarioId);
    localidad.idLocal = id;
    return id;
  }

  /// Marca una sección como guardada localmente.
  void marcarGuardada(
    Map<String, EdanSeccionEstado> estados,
    String seccionId,
  ) {
    estados[seccionId] =
        (estados[seccionId] ?? EdanSeccionEstado(seccionId: seccionId)).copyWith(
      guardadaLocal: true,
      fechaGuardado: DateTime.now(),
    );
  }

  /// Cambia el estado de la localidad a "Enviado UGR" y persiste.
  Future<void> marcarEnviadoUgr(EdanLocalidad localidad) async {
    localidad.idEdanLocalidadEstado = UgrLocalidadEstado.enviadoUgr.id;
    localidad.estadoLocalidad = UgrLocalidadEstado.enviadoUgr;
    localidad.pendienteActualizacion = true;
    if (localidad.idLocal != null) {
      await _db.updateLocalidad(localidad);
    }
  }

  /// Marca todas las secciones como guardadas (al enviar).
  void marcarGuardadasTodas(
    Map<String, EdanSeccionEstado> estados,
    List<String> secciones,
  ) {
    for (final s in secciones) {
      marcarGuardada(estados, s);
    }
  }

  /// Obtiene el usuario logueado (para idUsuario e insert).
  int? usuarioId() => AuthService.instance.currentToken?.userId;

  void log(String msg) => debugPrint('[EdanWizard] $msg');
}
