import 'package:flutter_test/flutter_test.dart';
import 'package:rea/config/app_roles.dart';

void main() {
  // ─────────────────────────────────────────────────────
  // ACCESO A LA APP: solo roles 6 (UGR) y 7 (RESP)
  // ─────────────────────────────────────────────────────
  group('AppRoles.puedeIngresar', () {
    test('rol 6 (UGR Municipio) → permitido', () {
      expect(AppRoles.puedeIngresar(6), isTrue);
    });

    test('rol 7 (Responsable Local) → permitido', () {
      expect(AppRoles.puedeIngresar(7), isTrue);
    });

    test('rol 8 (Alcalde) → rechazado', () {
      expect(AppRoles.puedeIngresar(8), isFalse);
    });

    test('roles 1-5 (superadmin, admin, VIDECI, UGR sectores, DGR) → rechazados', () {
      for (final idRol in [1, 2, 3, 4, 5]) {
        expect(AppRoles.puedeIngresar(idRol), isFalse, reason: 'El rol $idRol deberia estar bloqueado');
      }
    });

    test('rol 9 (VIDECI Departamental) → rechazado', () {
      expect(AppRoles.puedeIngresar(9), isFalse);
    });

    test('rol nulo (payload incompleto) → rechazado (fail closed)', () {
      expect(AppRoles.puedeIngresar(null), isFalse);
    });

    test('roles >= 10 → rechazados', () {
      for (final idRol in [10, 11, 99]) {
        expect(AppRoles.puedeIngresar(idRol), isFalse, reason: 'El rol $idRol deberia estar bloqueado');
      }
    });

    test('ningun rol fuera de {6,7} esta permitido', () {
      for (var idRol = 1; idRol <= 20; idRol++) {
        final esperado = AppRoles.permitidosEnApp.contains(idRol);
        expect(AppRoles.puedeIngresar(idRol), esperado, reason: 'Fallo con el rol $idRol');
      }
    });
  });

  // ─────────────────────────────────────────────────────
  // Excepción y mensaje de rechazo
  // ─────────────────────────────────────────────────────
  group('RolNoPermitidoException', () {
    test('guarda el rol recibido', () {
      expect(const RolNoPermitidoException(8).idRol, 8);
    });

    test('acepta rol nulo', () {
      expect(const RolNoPermitidoException(null).idRol, isNull);
    });

    test('no filtra el nombre del rol, solo el identificador', () {
      expect(const RolNoPermitidoException(8).toString(), contains('8'));
    });

    test('el mensaje al usuario no revela el rol numerico', () {
      expect(AppRoles.mensajeSinAcceso, isNot(contains('6')));
      expect(AppRoles.mensajeSinAcceso, isNot(contains('7')));
    });

    test('el mensaje al usuario menciona el acesso por la web', () {
      expect(AppRoles.mensajeSinAcceso.toLowerCase(), contains('web'));
    });
  });
}
