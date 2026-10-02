/// El system prompt de Groq.
///
/// El prompt se arma con las constantes del borrador, así que la prueba
/// comprueba que realmente incluye TODO el vocabulario: si el modelo no conoce
/// una clave, no la va a usar, y el validador la descarta.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:rea/models/edan_borrador_ia.dart';
import 'package:rea/services/edan_ia/edan_groq_prompt.dart';

void main() {
  String prompt({
  List<EdanProgresoSeccion>? pendientes,
  EdanBorradorIa? borrador,
}) =>
    edanGroqInstruccion(
      borrador: borrador,
        pendientes: pendientes ??
            [
              const EdanProgresoSeccion('danos-agricultura', 'Daños en agricultura', 0),
              const EdanProgresoSeccion('proteccion', 'Protección', 0.2),
            ],
        progreso: progresoGlobal(EdanBorradorIa()),
      );

  group('el prompt incluye todo el vocabulario del formulario', () {
    test('grupos etarios', () {
      final p = prompt();
      for (final g in kEdanGruposEdad) {
        expect(p, contains(g));
      }
    });

    test('grupos de protección', () {
      final p = prompt();
      for (final g in kEdanGruposProteccion) {
        expect(p, contains(g));
      }
    });

    test('necesidades humanitarias', () {
      final p = prompt();
      for (final n in kEdanNecesidadesHumanitarias) {
        expect(p, contains(n));
      }
    });

    test('tipos de evento y servicios básicos', () {
      final p = prompt();
      for (final e in kEdanClavesEvento) {
        expect(p, contains(e));
      }
      for (final s in kEdanServiciosBasicos.keys) {
        expect(p, contains(s));
      }
    });

    test('las nueve listas 1:n con sus campos', () {
      final p = prompt();
      for (final clave in const [
        'infraVial',
        'infraPublica',
        'saludDanios',
        'educacion',
        'danosVivienda',
        'agricultura',
        'pecuario',
        'comunidades',
      ]) {
        expect(p, contains(clave));
      }
      expect(p, contains('animalesAfectados'));
      expect(p, contains('hasAfectadas'));
      expect(p, contains('suspensionClases'));
    });
  });

  group('el prompt previene el tono de robot', () {
    test('dice explícitamente que no es un formulario con voz', () {
      final p = prompt();
      expect(p, contains('No sos un formulario con voz'));
      expect(p, contains('no le recitás secciones'));
    });

    test('prohíbe el vocabulario de sistema en la respuesta', () {
      // "Registré", "completé" y "campo" son las palabras que hacen sonar a
      // máquina una respuesta que debería sonar a persona.
      final p = prompt();
      // La parte del bloque de estado se prueba aparte, porque sin borrador el
      // bloque no va en el prompt.
      // La corrida real contra Groq mostró que los términos sueltos no
      // alcanzan: el modelo decía "Entiendo" y "Anoté" hasta que se listaron
      // uno por uno.
      for (final apertura in const [
        '"Entiendo"',
        '"Entendido"',
        '"Anoté"',
        '"Registré"',
      ]) {
        expect(p, contains(apertura), reason: 'falta prohibir $apertura');
      }
    });

    test('prohíbe recitar la ficha en cada respuesta', () {
      // La corrida real contra Groq pasó cinco turnos y a partir del tercero la
      // respuesta empezaba a repetir "350 personas, 80 familias, el puente de
      // la ruta 1..." en cada turno. Contexto sí, pero usado como lectura en voz
      // alta, que es ruido puro.
      final p = prompt();
      expect(p, contains('lo único que necesitás responder'));
      expect(p, contains('El que recita cada tres segundos'));
    });

    test('el bloque de estado es memoria, no texto para mostrar', () {
      // Sin borrador el bloque no va, así que esta prueba necesita el borrador.
      final p = prompt(borrador: EdanBorradorIa()..municipio = 'Yapacaní');
      expect(p, contains('es tu memoria, no un texto para mostrar'));
      expect(p, contains('La persona ya sabe todo'));
    });

    test('los tres lugares van a su nivel, no al último que se dijo', () {
      // La corrida real encontró esto: con "soy de Yapacaní, en Santa Cruz, lo
      // del municipio de Ichilo" el modelo ponía `municipio: Ichilo`.
      final p = prompt();
      expect(p, contains('son niveles distintos'));
      expect(p, contains('Ichilo es la **provincia**'));
      expect(p, contains('Yapacaní es el **municipio**'));
    });

    test('la regla de una pregunta cuenta signos, no intenciones', () {
      final p = prompt();
      expect(p, contains('un solo signo `?`'));
    });

    test('la pregunta se escribe dentro de la respuesta', () {
      // Medido contra el puente real: 7 de 7 turnos con `siguiente_pregunta`
      // en `null` y ninguna frase terminada en `?`, con lo que la entrevista se
      // clavaba. La pregunta tiene que salir de la prosa del modelo, que es
      // donde le suena natural, no de un campo aparte.
      final p = prompt();
      expect(p, contains('La pregunta va adentro de la frase'));
      expect(p, contains('**Tu mensaje termina en `?`.**'));
      expect(p, contains('Todos tus mensajes terminan en una pregunta'));
    });

    test('solo deja de preguntar cuando se cierra', () {
      final p = prompt();
      expect(p, contains('La **única** vez que tu mensaje no termina en `?`'));
      expect(p, contains('`siguiente_pregunta` en `null`'));
      // Antes había una salida que habilitaba no preguntar nada cada turno y
      // el modelo la usaba siempre.
      expect(p, isNot(contains('dejá que termine')));
    });

    test('manda a preguntar por lo que surja, no por la lista', () {
      final p = prompt();
      expect(p, contains('No la primera que falte de la'));
      expect(p, contains('No estás atado a ese orden'));
    });

    test('da ejemplos de seguimiento natural', () {
      final p = prompt();
      expect(p, contains('si pararon las clases'));
      expect(p, contains('paso'));
    });

    test('los pendientes se presentan como información, no como guion', () {
      // Si la lista se lee como guion, el modelo la recorre como un checklist.
      final p = prompt();
      expect(p, contains('información tuya, no un guion'));
      expect(p, isNot(contains('Secciones que todavía faltan')));
    });

    test('las fotos siguen yendo al paso aparte', () {
      expect(prompt(), contains('fotos y las coordenadas se piden al final'));
      expect(prompt(), contains('en un paso aparte donde la'));
    });
  });

  group('el prompt mantiene las fronteras', () {
    test('prohíbe inventar y nombra las claves de sincronización', () {
      final p = prompt();
      expect(p, contains('No inventes cifras'));
      for (final clave in const ['id_seccion', 'sincronizado', 'editado']) {
        expect(p, contains(clave));
      }
    });

    test('exige el JSON y limita a una pregunta', () {
      final p = prompt();
      expect(p, contains('"siguiente_pregunta"'));
      expect(p, contains('Una pregunta por mensaje'));
    });

    test('explica el desglose de protección: total sin repartir', () {
      expect(prompt(), contains('no repartas ni supongas el desglose'));
    });
  });

  group('el prompt refleja el estado de la ficha', () {
    test('lista lo que falta por su título, sin clave técnica', () {
      // La clave de sección ('danos-agricultura') es interna: si aparece en el
      // bloque de pendientes, el modelo puede terminar recitándola. El resto del
      // prompt sí menciona 'proteccion', pero como nombre de campo del parche.
      final pendientes = pendientesDe(prompt());
      expect(pendientes, contains('- Daños en agricultura'));
      expect(pendientes, contains('- Protección'));
      expect(pendientes, isNot(contains('danos-agricultura')));
      expect(pendientes, isNot(contains('proteccion')));
    });

    test('si no falta nada, lo dice explícitamente', () {
      expect(edanGroqInstruccion(pendientes: const []),
          contains('la ficha ya está completa'));
    });

    test('solo lista lo ya anotado, no todo el progreso', () {
      final b = EdanBorradorIa()..municipio = 'Yapacaní'..totalAfectada = 350;
      final p = edanGroqInstruccion(
        pendientes: const [
          EdanProgresoSeccion('danos-agricultura', 'Agricultura', 0),
        ],
        progreso: progresoGlobal(b),
      );
      // `progresoGlobal` titula la cabecera como "Datos generales".
      expect(anotadoEn(p), contains('- Datos generales'));
      // Y lo que está al 0% no se ofrece como "ya anotado".
      expect(anotadoEn(p), isNot(contains('Agricultura')));
    });
  });
}

/// Lo que el prompt ofrece preguntar: el bloque de pendientes, sin el resto.
String pendientesDe(String prompt) => _bloque(
      prompt,
      desde: '# Lo que todavía falta',
      hasta: 'Lo que ya está anotado',
    );

/// Lo que el prompt da por ya anotado.
String anotadoEn(String prompt) =>
    _bloque(prompt, desde: 'Lo que ya está anotado', hasta: r'$');

String _bloque(String prompt, {required String desde, required String hasta}) {
  final i = prompt.indexOf(desde);
  if (i < 0) return '';
  final resto = prompt.substring(i + desde.length);
  final j = resto.indexOf(hasta);
  return j < 0 ? resto : resto.substring(0, j);
}
