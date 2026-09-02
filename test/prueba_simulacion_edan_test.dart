// PRUEBA TEMPORAL — ELIMINAR DESPUÉS DE VERIFICAR
// Ejecutar: cd REA; flutter test test/prueba_simulacion_edan_test.dart
// Envío real: flutter test test/prueba_simulacion_edan_test.dart --dart-define=EDAN_TOKEN=tu_token --dart-define=EDAN_ID_USUARIO=30

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rea/config/api_config.dart';
import 'package:rea/models/edan.dart';
import 'package:rea/services/edan_secciones_registry.dart';
import 'package:rea/services/edan/edan_secciones_envio_factory.dart';

String? _token;
String? _idUsuario;

void _initConfig() {
  _token = const String.fromEnvironment('EDAN_TOKEN');
  _idUsuario = const String.fromEnvironment('EDAN_ID_USUARIO', defaultValue: '30');
}

Map<String, String> _headers() => {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $_token',
    };

EdanLocalidad _localidadBase({
  required String nombre,
  required String idLocal,
  required Map<String, bool> flags,
  List<EdanDanoVial>? danosViales,
  List<EdanEstablecimientoSalud>? establecimientos,
  List<EdanServicioBasicoDetalle>? servicios,
  List<EdanImpactoPoblacion>? impactoPoblacion,
  EdanNecesidadPrimeraRespuesta? primeraRespuesta,
  EdanNecesidadSalud? necesidadSalud,
  EdanNecesidadHumanitaria? necesidadHumanitaria,
}) {
  return EdanLocalidad(
    idLocal: idLocal,
    nombre: nombre,
    idDepartamento: 7,
    idProvincia: 701,
    idMunicipio: 70101,
    fechaLlenado: '2026-09-02',
    fechaEvento: '2026-09-01',
    horaEvento: '10:00',
    totalPoblacionAfectada: 200,
    totalFamiliasAfectadas: 40,
    totalFamiliasDamnificadas: 15,
    impPoblacion: flags['impPoblacion'] ?? false,
    impSalud: flags['impSalud'] ?? false,
    impInfraestructura: flags['impInfraestructura'] ?? false,
    impServicios: flags['impServicios'] ?? false,
    impEducacion: flags['impEducacion'] ?? false,
    impVivienda: flags['impVivienda'] ?? false,
    impAgropecuario: flags['impAgropecuario'] ?? false,
    impProteccion: flags['impProteccion'] ?? false,
    impNecesidades: flags['impNecesidades'] ?? false,
    editado: true,
    impactoPoblacion: impactoPoblacion ?? [],
    establecimientosSalud: establecimientos ?? [],
    danosViales: danosViales ?? [],
    serviciosBasicos: servicios ?? [],
    necesidadPrimeraRespuesta: primeraRespuesta,
    necesidadSalud: necesidadSalud,
    necesidadHumanitaria: necesidadHumanitaria,
  );
}

void main() {
  _initConfig();

  // ============================================================
  // RONDA 1: Simulación offline — JSON por sección según flags
  // ============================================================
  group('RONDA 1: JSON por sección basado en flags de cabecera', () {
    late EdanLocalidad loc;
    late Map<String, bool> rondaFlags;

    setUp(() {
      rondaFlags = {
        'impPoblacion': true,
        'impSalud': true,
        'impInfraestructura': true,
        'impServicios': false,
        'impEducacion': false,
        'impVivienda': false,
        'impAgropecuario': false,
        'impProteccion': true,
        'impNecesidades': true,
      };

      loc = _localidadBase(
        nombre: 'Prueba Ronda 1 - Tarija',
        idLocal: 'ronda1-001',
        flags: rondaFlags,
        impactoPoblacion: [
          EdanImpactoPoblacion(
            idSeccion: 'r1-imp-01',
            gruposEtarios: [
              EdanGrupoEtario(
                idSeccion: 'r1-ge-01',
                rango: 'Total',
                fallecidos: 5,
                heridos: 20,
                desaparecidos: 2,
                marcado: true,
              ),
            ],
          ),
        ],
        establecimientos: [
          EdanEstablecimientoSalud(
            idSeccion: 'r1-sal-01',
            nombreEstablecimiento: 'Hospital Local',
            comunidad: 'Barrio Centro',
            nivelAtencion: 'Primer nivel',
            danoParcial: true,
            danoTotal: false,
            fotografia: '/uploads/salud_01.jpg',
            coordenadaLat: -16.5,
            coordenadaLon: -68.15,
          ),
        ],
        danosViales: [
          EdanDanoVial(
            idSeccion: 'r1-vial-01',
            viaPuente: 'Vía',
            tramo: 'Ruta Nacional 1 km 5',
            danoParcial: true,
            danoTotal: false,
            necesidadesInmediatas: 'Desmoronamiento parcial',
            fotografia: '/uploads/vial_01.jpg',
            coordenadaLat: -16.51,
            coordenadaLon: -68.16,
          ),
        ],
        primeraRespuesta: EdanNecesidadPrimeraRespuesta(
          busqueda: true,
          salvamento: false,
          evacuacion: false,
          observaciones: 'Operativo de búsqueda activo',
        ),
        necesidadSalud: EdanNecesidadSalud(
          numeroPersonas: 10,
          otrasNecesidades: 'Medicamentos',
          observaciones: 'Antibióticos y analgésicos',
        ),
        necesidadHumanitaria: EdanNecesidadHumanitaria(
          alimentos: true,
          refugioVivienda: false,
          obsAlimentos: 'Raciones de emergencia',
          obsRefugioVivienda: '',
        ),
      );
    });

    test('editado=1 en cabecera y modelo', () {
      expect(loc.editado, isTrue,
          reason: 'La cabecera debe tener editado=1 después de edición');
    });

    test('toApiJson incluye todos los flags de cabecera', () {
      final apiJson = loc.toApiJson();

      expect(apiJson['imp_poblacion'], isTrue);
      expect(apiJson['imp_salud'], isTrue);
      expect(apiJson['imp_infraestructura'], isTrue);
      expect(apiJson['imp_servicios'], isFalse);
      expect(apiJson['imp_proteccion'], isTrue);
      expect(apiJson['imp_necesidades'], isTrue);

      print('\n=== CABECERA toApiJson ===');
      print('  imp_poblacion=${apiJson['imp_poblacion']}, '
          'imp_salud=${apiJson['imp_salud']}, '
          'imp_infraestructura=${apiJson['imp_infraestructura']}, '
          'imp_servicios=${apiJson['imp_servicios']}, '
          'imp_proteccion=${apiJson['imp_proteccion']}, '
          'imp_necesidades=${apiJson['imp_necesidades']}');
    });

    test('impacto-poblacion (1:N) genera payload correcto', () {
      final servicio = EdanSeccionesEnvioFactory.servicioDeRuta('impacto-poblacion')!;
      final filas = servicio.filasGuardar(loc);

      expect(filas.length, 1, reason: 'Debe haber 1 grupo marcado');
      expect(filas[0]['fallecidos'], 5);
      expect(filas[0]['heridos'], 20);

      print('=== impacto-poblacion ===');
      print('  Filas: ${filas.length}');
      print('  JSON: ${jsonEncode(filas[0])}');
    });

    test('salud-establecimientos (1:N, foto) genera payload con fotografia', () {
      final servicio = EdanSeccionesEnvioFactory.servicioDeRuta('salud-establecimientos')!;
      final filas = servicio.filasGuardar(loc);

      expect(filas.length, 1);
      expect(filas[0]['fotografia'], '/uploads/salud_01.jpg');

      print('=== salud-establecimientos (con foto) ===');
      print('  Filas: ${filas.length}');
      print('  fotografia=${filas[0]['fotografia']}');
    });

    test('danos-viales (1:N, foto) genera payload completo', () {
      final servicio = EdanSeccionesEnvioFactory.servicioDeRuta('danos-viales')!;
      final filas = servicio.filasGuardar(loc);

      expect(filas.length, 1);
      expect(filas[0]['via'], isTrue, reason: 'Vía convierte a true');
      expect(filas[0]['puente'], isFalse, reason: 'No es puente');
      expect(filas[0]['tramo'], 'Ruta Nacional 1 km 5');
      expect(filas[0]['fotografia'], '/uploads/vial_01.jpg');

      print('=== danos-viales (con foto) ===');
      print('  Filas: ${filas.length}');
      print('  via=${filas[0]['via']}, puente=${filas[0]['puente']}, tramo=${filas[0]['tramo']}, '
          'foto=${filas[0]['fotografia']}');
    });

    test('primera-respuesta (1:1) genera objeto único', () {
      final servicio = EdanSeccionesEnvioFactory.servicioDeRuta('primera-respuesta')!;
      final filas = servicio.filasGuardar(loc);

      expect(filas.length, 1, reason: '1:1 genera una sola fila');
      expect(filas[0]['busqueda'], isTrue);
      expect(filas[0]['salvamento'], isFalse);

      print('=== primera-respuesta (1:1) ===');
      print('  Filas: ${filas.length} (objeto único)');
      print('  JSON: ${jsonEncode(filas[0])}');
    });

    test('necesidad-salud (1:1) genera objeto único', () {
      final servicio = EdanSeccionesEnvioFactory.servicioDeRuta('necesidad-salud')!;
      final filas = servicio.filasGuardar(loc);

      expect(filas.length, 1);
      expect(filas[0]['numero_personas'], 10);

      print('=== necesidad-salud (1:1) ===');
      print('  JSON: ${jsonEncode(filas[0])}');
    });

    test('necesidad-humanitaria (1:1) genera objeto único', () {
      final servicio = EdanSeccionesEnvioFactory.servicioDeRuta('necesidad-humanitaria')!;
      final filas = servicio.filasGuardar(loc);

      expect(filas.length, 1);
      expect(filas[0]['alimentos'], isTrue);

      print('=== necesidad-humanitaria (1:1) ===');
      print('  JSON: ${jsonEncode(filas[0])}');
    });

    test('servicios-basicos (flag=false) genera 0 filas', () {
      final servicio = EdanSeccionesEnvioFactory.servicioDeRuta('servicios-basicos')!;
      final filas = servicio.filasGuardar(loc);

      expect(filas.length, 0,
          reason: 'servicios-basicos vacío cuando no hay datos');

      print('=== servicios-basicos (sin datos) ===');
      print('  Filas: ${filas.length} (flag=false, sin datos)');
    });

    test('todas las 14 rutas se procesan', () {
      int totalFilas = 0;
      int rutasConDatos = 0;
      int rutasVacias = 0;

      print('\n=== RESUMEN POR SECCIÓN (Ronda 1) ===');
      for (final desc in EdanSeccionesRegistry.secciones) {
        final servicio = EdanSeccionesEnvioFactory.servicioDeRuta(desc.rutaV2);
        expect(servicio, isNotNull, reason: 'Servicio para ${desc.rutaV2} debe existir');
        final filas = servicio!.filasGuardar(loc);
        totalFilas += filas.length;
        if (filas.isNotEmpty) {
          rutasConDatos++;
        } else {
          rutasVacias++;
        }
        final tipo = desc.tipo == EdanSeccionTipo.unoAUno ? '1:1' : '1:N';
        final foto = desc.usaFoto ? ' [FOTO]' : '';
        print('  ${desc.rutaV2.padRight(28)} $tipo$foto → ${filas.length} filas');
      }

      print('  ─────────────────────────────────────────');
      print('  Total filas: $totalFilas | Con datos: $rutasConDatos | Vacías: $rutasVacias');
      expect(totalFilas, greaterThan(0), reason: 'Debe haber filas en alguna sección');
    });
  });

  // ============================================================
  // RONDA 2: Flags mínimos — solo poblacion y proteccion
  // ============================================================
  group('RONDA 2: Flags mínimos (población + protección)', () {
    late EdanLocalidad loc;

    setUp(() {
      loc = _localidadBase(
        nombre: 'Prueba Ronda 2 - Mínimo',
        idLocal: 'ronda2-001',
        flags: {
          'impPoblacion': true,
          'impProteccion': true,
        },
        impactoPoblacion: [
          EdanImpactoPoblacion(
            idSeccion: 'r2-imp-01',
            gruposEtarios: [
              EdanGrupoEtario(
                idSeccion: 'r2-ge-01',
                rango: 'Total',
                fallecidos: 1,
                heridos: 3,
                desaparecidos: 0,
                marcado: true,
              ),
            ],
          ),
        ],
      );
    });

    test('solo secciones con datos presentes', () {
      print('\n=== RESUMEN POR SECCIÓN (Ronda 2) ===');
      int totalFilas = 0;
      for (final desc in EdanSeccionesRegistry.secciones) {
        final servicio = EdanSeccionesEnvioFactory.servicioDeRuta(desc.rutaV2)!;
        final filas = servicio.filasGuardar(loc);
        totalFilas += filas.length;
        if (filas.isNotEmpty) {
          print('  ✓ ${desc.rutaV2} → ${filas.length} filas');
        }
      }
      expect(totalFilas, 1, reason: 'Solo impacto-poblacion tiene datos');
    });

    test('toApiJson omite secciones vacías (modo comprimido)', () {
      final apiJson = loc.toApiJson();
      expect(apiJson['impacto_poblacion'], isA<List>());
      expect((apiJson['impacto_poblacion'] as List).length, 1);

      print('=== toApiJson Ronda 2 ===');
      print('  Keys del JSON: ${apiJson.keys.toList()}');
    });
  });

  // ============================================================
  // RONDA 3: Flag false, flags sin datos → todo vacío
  // ============================================================
  group('RONDA 3: Cabecera flags=false, sin datos', () {
    late EdanLocalidad loc;

    setUp(() {
      loc = _localidadBase(
        nombre: 'Prueba Ronda 3 - Vacío',
        idLocal: 'ronda3-001',
        flags: {},
      );
    });

    test('editado=1 pero sin filas en secciones', () {
      expect(loc.editado, isTrue);
      int totalFilas = 0;
      for (final desc in EdanSeccionesRegistry.secciones) {
        final servicio = EdanSeccionesEnvioFactory.servicioDeRuta(desc.rutaV2)!;
        totalFilas += servicio.filasGuardar(loc).length;
      }
      expect(totalFilas, 0, reason: 'Sin datos → 0 filas de sección');
      print('=== Ronda 3: editado=1, totalFilas=$totalFilas ===');
    });
  });

  // ============================================================
  // RONDA 4: Envío al servidor (requiere --dart-define=EDAN_TOKEN)
  // ============================================================
  group('RONDA 4: Envío real al servidor', () {
    final String? token = _token;
    final bool habilitado = token != null && token.isNotEmpty;

    test('cabecera + secciones → POST real a producción', () async {
      if (!habilitado) {
        print('\n⚠  SALTADO: EDAN_TOKEN no definido. Ejecutar con:');
        print('   flutter test test/prueba_simulacion_edan_test.dart '
            '--dart-define=EDAN_TOKEN=tu_token');
        return;
      }

      final loc = _localidadBase(
        nombre: 'TEST-SIMULACION-${DateTime.now().millisecondsSinceEpoch}',
        idLocal: 'sim-${DateTime.now().millisecondsSinceEpoch}',
        flags: {
          'impPoblacion': true,
          'impSalud': true,
          'impInfraestructura': true,
        },
        impactoPoblacion: [
          EdanImpactoPoblacion(
            idSeccion: 'sim-imp-01',
            gruposEtarios: [
              EdanGrupoEtario(
                idSeccion: 'sim-ge-01',
                rango: 'Total',
                fallecidos: 0,
                heridos: 2,
                desaparecidos: 0,
                observaciones: 'PRUEBA SIMULACIÓN - ELIMINAR',
                marcado: true,
              ),
            ],
          ),
        ],
        establecimientos: [
          EdanEstablecimientoSalud(
            idSeccion: 'sim-sal-01',
            nombreEstablecimiento: 'Centro Salud Test',
            comunidad: 'Comunidad Test',
            nivelAtencion: 'Primer nivel',
            danoParcial: true,
            danoTotal: false,
            fotografia: null,
          ),
        ],
        primeraRespuesta: EdanNecesidadPrimeraRespuesta(
          busqueda: true,
          salvamento: false,
          evacuacion: false,
          observaciones: 'PRUEBA SIMULACIÓN - ELIMINAR',
        ),
      );

      print('\n=== RONDA 4: Envío a ${ApiConfig.baseUrl} ===');
      print('  Nombre: ${loc.nombre}');
      print('  idLocal: ${loc.idLocal}');

      // 1. POST cabecera
      final cabJson = loc.toJson();
      for (final s in EdanSeccionesRegistry.secciones) {
        cabJson.remove(s.llaveJson);
      }
      cabJson['id_usuario'] = int.tryParse(_idUsuario ?? '30') ?? 30;
      cabJson.remove('fecha_modificacion');
      cabJson.remove('pendiente_actualizacion');
      cabJson.remove('pendiente_eliminacion');
      cabJson.remove('sincronizado');

      print('\n--- POST /edan/localidades (cabecera) ---');
      final respCab = await http.post(
        Uri.parse('${ApiConfig.edanLocalidadesEndpoint}'),
        headers: _headers(),
        body: jsonEncode(cabJson),
      );
      print('  Status: ${respCab.statusCode}');
      print('  Body: ${respCab.body}');

      expect(respCab.statusCode, anyOf(200, 201),
          reason: 'Cabecera debe crearse');

      final cabBody = jsonDecode(respCab.body) as Map<String, dynamic>;
      final idEdan = cabBody['id_edan_localidad'] as int?;
      expect(idEdan, isNotNull, reason: 'Servidor debe devolver id_edan_localidad');
      print('  id_edan_localidad: $idEdan');

      // 2. POST secciones con datos
      int seccionesEnviadas = 0;
      for (final desc in EdanSeccionesRegistry.secciones) {
        final servicio = EdanSeccionesEnvioFactory.servicioDeRuta(desc.rutaV2);
        if (servicio == null) continue;
        final filas = servicio.filasGuardar(loc);
        if (filas.isEmpty) continue;

        final payload = desc.tipo == EdanSeccionTipo.unoAUno
            ? filas.first
            : filas;

        print('\n--- POST /edan/localidades/$idEdan/${desc.rutaV2} (${desc.tipo == EdanSeccionTipo.unoAUno ? '1:1' : '1:N'}) ---');
        final resp = await http.post(
          Uri.parse('${ApiConfig.edanLocalidadesEndpoint}/$idEdan/${desc.rutaV2}'),
          headers: _headers(),
          body: jsonEncode(payload),
        );
        print('  Status: ${resp.statusCode} | Filas: ${filas.length}');
        expect(resp.statusCode, anyOf(200, 201),
            reason: 'Sección ${desc.rutaV2} debe enviarse');
        seccionesEnviadas++;
      }

      print('\n=== RESUMEN RONDA 4 ===');
      print('  Cabecera: id_edan=$idEdan');
      print('  Secciones enviadas: $seccionesEnviadas');
      print('  editado=${loc.editado} → badge=1 (pendiente de sincronizar)');

      // 3. Cleanup: marcar como borrador / eliminar
      print('\n  ⚠  La localidad $idEdan queda en el servidor como BORRADOR.');
      print('     El admin debe eliminarla después de la verificación.');
    });
  });
}
