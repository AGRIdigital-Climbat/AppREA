import 'package:flutter/material.dart';
import '../providers/reporte_provider.dart';
import '../services/edan/edan_store_v2.dart';
import '../services/edan_sync_service.dart';

/// Franja de progreso bajo el AppBar del UGR (rol 6): UNA sola (nunca se
/// apila ni tapa contenido — empuja). Fondo blanco, texto grafito, icono y
/// barra en rojo institucional, % a la derecha.
///
/// Prioridad (procesos propios del rol 6):
///  1. Histórico del municipio (`EdanSyncService.recargarEdansMunicipio`,
///     API `listarEdansPorMunicipio`): el GET primero (spinner) y luego
///     `'Guardando histórico del municipio X de Y'` con barra real.
///  2. Motor V2 (`sincronizandoNotifier` + `faseSync` + fotos): cubre la
///     primera descarga de los reportes propios tras login y la sincronización
///     manual/auto — el motor publica sus fases globalmente.
///  3. Arranque/catálogos (`ReporteProvider.isInitializing` /
///     `progresoCatalogos`): 'Cargando datos locales...' y las 9 fases de
///     catálogo con %.
/// Sin nada en curso, no pinta nada ([SizedBox.shrink]).
class UgrProgressFranja extends StatelessWidget {
  final ReporteProvider rp;

  const UgrProgressFranja({super.key, required this.rp});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        EdanSyncService.instance.sincronizandoMunicipio,
        EdanSyncService.instance.faseMunicipio,
        EdanSyncService.instance.municipioTotal,
        EdanSyncService.instance.municipioHechas,
        EdanStoreV2.instance.sincronizandoNotifier,
        EdanStoreV2.instance.faseSync,
        EdanStoreV2.instance.descargaFotosTotal,
        EdanStoreV2.instance.descargaFotosHechas,
      ]),
      builder: (context, _) {
        String? texto;
        double? progreso;
        final sync = EdanSyncService.instance;
        final store = EdanStoreV2.instance;
        if (sync.sincronizandoMunicipio.value) {
          final fase = sync.faseMunicipio.value;
          final total = sync.municipioTotal.value;
          final hechas = sync.municipioHechas.value;
          if (total > 0) {
            texto = 'Guardando histórico del municipio $hechas de $total';
            progreso = total == 0 ? null : hechas / total;
          } else {
            texto = fase.isNotEmpty ? fase : 'Consultando EDANs del municipio...';
          }
        } else if (store.sincronizandoNotifier.value) {
          final fase = store.faseSync.value;
          final total = store.descargaFotosTotal.value;
          final hechas = store.descargaFotosHechas.value;
          final esFotos = fase == 'Descargando fotos' && total > 0;
          texto = esFotos
              ? 'Descargando fotos $hechas de $total...'
              : (fase.isNotEmpty ? '$fase...' : 'Sincronizando...');
          progreso = esFotos ? hechas / total : null;
        } else if (rp.isInitializing || rp.progresoCatalogos != null) {
          texto = rp.downloadPhase.isNotEmpty
              ? rp.downloadPhase
              : 'Cargando datos locales...';
          progreso = rp.progresoCatalogos;
        }
        if (texto == null) return const SizedBox.shrink();
        return _contenidoFranja(texto: texto, progreso: progreso);
      },
    );
  }

  /// Mismo diseño que la franja del RESP (empuja el contenido, no lo tapa):
  /// fondo blanco, icono rojo, texto grafito, % o spinner a la derecha y
  /// barra roja con pista rosada cuando hay progreso conocido.
  Widget _contenidoFranja({
    required String texto,
    required double? progreso,
  }) {
    const rojo = Color(0xFFC0392B);
    final pct = progreso == null
        ? null
        : '${(progreso.clamp(0.0, 1.0) * 100).toInt()}%';
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(
                Icons.cloud_download_outlined,
                size: 18,
                color: rojo,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  texto,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1F2937),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (pct != null)
                Text(
                  pct,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: rojo,
                  ),
                )
              else
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: rojo,
                  ),
                ),
            ],
          ),
          if (progreso != null) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progreso.clamp(0.0, 1.0),
                minHeight: 5,
                backgroundColor: const Color(0xFFF3D9D4),
                valueColor: const AlwaysStoppedAnimation<Color>(rojo),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
