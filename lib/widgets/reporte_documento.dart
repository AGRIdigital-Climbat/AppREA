import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../config/theme.dart';

class ReporteDocumento extends StatelessWidget {
  final String titulo;
  final String? subtitulo;
  final String? fechaCabecera;
  final IconData? icono;
  final Widget? chip;
  final Widget? cabezalExtra;
  final List<ReporteDocSeccion> secciones;
  final String? footerNota;
  final String? footerFecha;

  const ReporteDocumento({
    super.key,
    required this.titulo,
    this.subtitulo,
    this.fechaCabecera,
    this.icono,
    this.chip,
    this.cabezalExtra,
    required this.secciones,
    this.footerNota,
    this.footerFecha,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CabezalColor(
            titulo: titulo,
            subtitulo: subtitulo,
            fecha: fechaCabecera,
            icono: icono,
            chip: chip,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(4),
            ),
          ),
          ?cabezalExtra,
          _buildBody(),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < secciones.length; i++) ...[
            if (i > 0) ...[
              const SizedBox(height: 16),
              const ReporteDocDivider(),
              const SizedBox(height: 16),
            ],
            ReporteDocSectionTitle(secciones[i].titulo),
            const SizedBox(height: 8),
            for (final campo in secciones[i].campos)
              ReporteDocRow(label: campo.label, value: campo.value),
            if (secciones[i].contenido != null) ...[
              const SizedBox(height: 12),
              secciones[i].contenido!,
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(4),
          bottomRight: Radius.circular(4),
        ),
        border: Border(
          top: BorderSide(color: AppColors.divider),
        ),
      ),
      child: Column(
        children: [
          if (footerNota != null && footerNota!.isNotEmpty) ...[
            Text(
              footerNota!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 4),
          ],
          if (footerFecha != null && footerFecha!.isNotEmpty)
            Text(
              footerFecha!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary.withValues(alpha: 0.5),
              ),
            ),
        ],
      ),
    );
  }
}

class ReporteDocSeccion {
  final String titulo;
  final List<ReporteDocCampo> campos;
  final Widget? contenido;

  const ReporteDocSeccion({
    required this.titulo,
    this.campos = const [],
    this.contenido,
  });
}

class ReporteDocCampo {
  final String label;
  final String value;

  const ReporteDocCampo(this.label, this.value);
}

class ReporteDocSectionTitle extends StatelessWidget {
  final String title;

  const ReporteDocSectionTitle(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.bold,
        color: PaletteScope.of(context).primary,
        letterSpacing: 0.8,
      ),
    );
  }
}

class ReporteDocRow extends StatelessWidget {
  final String label;
  final String value;

  const ReporteDocRow({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary.withValues(alpha: 0.8),
                fontFamily: 'monospace',
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ReporteDocDivider extends StatelessWidget {
  const ReporteDocDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      color: AppColors.divider,
    );
  }
}

class ReporteDocMapa extends StatelessWidget {
  final double lat;
  final double lon;
  final double height;

  const ReporteDocMapa({
    super.key,
    required this.lat,
    required this.lon,
    this.height = 180,
  });

  @override
  Widget build(BuildContext context) {
    final primary = PaletteScope.of(context).primary;
    // Coordenadas no-finitas (NaN/Infinity o fuera de rango) harían que
    // flutter_map reviente en CADA frame ("north latitude ... NaN"): si el
    // dato viene malo, se pinta un placeholder en vez del mapa.
    final coordsOk = lat.isFinite &&
        lon.isFinite &&
        lat.abs() <= 90 &&
        lon.abs() <= 180;
    if (!coordsOk) {
      return Container(
        height: height,
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.location_off_outlined,
                  color: AppColors.textSecondary, size: 28),
              SizedBox(height: 4),
              Text(
                'Coordenadas no disponibles',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: height,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: LatLng(lat, lon),
            initialZoom: 16,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.none,
            ),
          ),
          children: [
            TileLayer(
              // Sin clave (2026-11-02): ArcGIS exigía API key; OSM es libre.
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.climbat.edan',
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: LatLng(lat, lon),
                  width: 40,
                  height: 40,
                  child: Icon(
                    Icons.location_on,
                    color: primary,
                    size: 36,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class CabezalColor extends StatelessWidget {
  final String titulo;
  final String? subtitulo;
  final String? fecha;
  final IconData? icono;
  final Widget? chip;
  final BorderRadius? borderRadius;

  const CabezalColor({
    super.key,
    required this.titulo,
    this.subtitulo,
    this.fecha,
    this.icono,
    this.chip,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final primary = PaletteScope.of(context).primary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
      decoration: BoxDecoration(
        color: primary,
        borderRadius: borderRadius ?? BorderRadius.zero,
      ),
      child: Column(
        children: [
          if (icono != null) ...[
            Icon(icono, color: Colors.white, size: 32),
            const SizedBox(height: 8),
          ],
          Text(
            titulo,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 1.2,
            ),
          ),
          if (subtitulo != null && subtitulo!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtitulo!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.8),
                letterSpacing: 0.5,
              ),
            ),
          ],
          if (fecha != null && fecha!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              fecha!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ],
          if (chip != null) ...[
            const SizedBox(height: 12),
            chip!,
          ],
        ],
      ),
    );
  }
}
