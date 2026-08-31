import 'package:flutter_test/flutter_test.dart';
import 'package:rea/models/edan.dart';
import 'package:rea/services/edan_secciones_registry.dart';

/// Reproduce el escenario del Bug 2: guardar página 04 (salud), simular el
/// round-trip de SQLite (toJson -> datos_json -> fromJson) y verificar que la
/// completitud de la sección siga marcándose al reabrir el wizard.
void main() {
  bool seccionCompleta04(EdanLocalidad l) =>
      l.establecimientosSalud.isNotEmpty ||
      (l.necesidadSalud?.numeroPersonas ?? 0) > 0;

  test('page04 con establecimiento -> completa tras round-trip (reabrir)', () {
    final loc = EdanLocalidad(impSalud: true);
    loc.establecimientosSalud.add(EdanEstablecimientoSalud(
      idSeccion: 'es-abc',
      nombreEstablecimiento: 'Hospital Test',
    ));

    // Guardar en SQLite = jsonEncode(toJson)
    final datosJson = loc.toJson();

    // Reabrir = EdanLocalidad.fromJson(datosJson)
    final reabierto = EdanLocalidad.fromJson(datosJson);

    expect(reabierto.establecimientosSalud.length, 1,
        reason: 'Los establecimientos deben sobrevivir al round-trip');
    expect(seccionCompleta04(reabierto), true,
        reason: 'La sección 04 debe seguir marcada completada al reabrir');
  });

  test('page04 con solo N personas -> completa tras round-trip', () {
    final loc = EdanLocalidad(impSalud: true);
    loc.necesidadSalud?.numeroPersonas = 40;

    final reabierto = EdanLocalidad.fromJson(loc.toJson());

    expect(reabierto.necesidadSalud?.numeroPersonas, 40,
        reason: 'numeroPersonas debe sobrevivir al round-trip');
    expect(seccionCompleta04(reabierto), true);
  });

  test('page04 vacía -> NO completa tras round-trip', () {
    final loc = EdanLocalidad(impSalud: true);
    final reabierto = EdanLocalidad.fromJson(loc.toJson());
    expect(seccionCompleta04(reabierto), false);
  });

  test('paginasWizard incluye las rutas 1:1 que la página 04 edita', () {
    final rutas = EdanSeccionesRegistry.rutasDePagina('04').toSet();
    expect(rutas, containsAll(['salud-establecimientos', 'necesidad-salud']));
  });

  test('paginasWizard incluye las rutas 1:1 que la página 03 edita', () {
    final rutas = EdanSeccionesRegistry.rutasDePagina('03').toSet();
    expect(rutas, containsAll(['impacto-poblacion', 'primera-respuesta']));
  });

  test('todas las rutas de seccion están mapeadas a al menos una página', () {
    final rutasUsadas = <String>{};
    for (final key in EdanSeccionesRegistry.paginasWizard.keys) {
      rutasUsadas.addAll(EdanSeccionesRegistry.rutasDePagina(key));
    }
    rutasUsadas.remove(EdanSeccionesRegistry.cabecera);
    final todas = EdanSeccionesRegistry.rutasV2Todas().toSet();
    final faltantes = todas.difference(rutasUsadas);
    expect(faltantes, isEmpty,
        reason: 'Toda ruta v2 debe estar mapeada a una página del wizard: $faltantes');
  });
}
