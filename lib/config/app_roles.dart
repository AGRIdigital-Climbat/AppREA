/// Catalogo de roles y politica de acceso a la app movil.
///
/// Antes estos numeros vivian sueltos (literales magicos) en varios archivos.
/// Cualquiera que necesite saber "quien puede entrar" debe usar este archivo.
class AppRoles {
  const AppRoles._();

  /// Unidad de Gestion de Recurso (UGR) a nivel municipal.
  static const int ugrMunicipio = 6;

  /// Responsable Local (RESP).
  static const int respLocal = 7;

  /// Unicos roles autorizados a iniciar sesion en la app movil.
  static const Set<int> permitidosEnApp = {ugrMunicipio, respLocal};

  /// Message mostrado cuando las credenciales son validas pero el rol
  /// no tiene acceso a la app movil.
  static const String mensajeSinAcceso =
      'No puedes ingresar a esta aplicación con tu rol. '
      'Por favor, ingresa a través de la plataforma web.';

  /// `true` solo para los roles autorizados a usar la app movil.
  /// Un `idRol` nulo (payload incompleto del servidor) se rechaza.
  static bool puedeIngresar(int? idRol) =>
      idRol != null && permitidosEnApp.contains(idRol);
}

/// Se lanza cuando las credenciales son validas pero el rol del usuario
/// no esta en [AppRoles.permitidosEnApp].
///
/// Permite que las capas superiores distingan "credenciales incorrectas" de
/// "usuario valido sin acceso a la app", sin depender de textos.
class RolNoPermitidoException implements Exception {
  const RolNoPermitidoException(this.idRol);

  final int? idRol;

  @override
  String toString() => 'RolNoPermitidoException(idRol: $idRol)';
}
