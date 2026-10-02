import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Distingue "no se pudo hablar con el servidor" de "el servidor rechazó el
/// dato".
///
/// Sin esta distincion la UI no puede hacer nada inteligente: ambas cosas
/// llegan como `exito == false` y se pintan de rojo igual. Pero no son lo
/// mismo para quien esta en campo:
///   - Fallo de red: no se perdio nada, esta todo en SQLite, y la app reintenta
///     sola al volver la conexion. Mostrar un error rojo aqui es castigar al
///     usuario por algo que el sistema ya resuelve sin que el intervenga.
///   - Rechazo del servidor: alguien de arriba decidio que el dato va mal
///     (unicidad 1:1, 403 por localidad consolidada, regla de negocio). Eso si
///     necesita verse y necesita que el usuario lo mire.
///
/// El criterio es el tipo de excepcion: las de transporte (no se abrio el
/// socket, expiro el timeout, TLS fallo) son de red. Un 4xx/5xx o un error de
/// validacion viajan como excepcion de la API y no matchean ninguna de estas.
bool esFalloDeRed(Object e) {
  if (e is SocketException) return true;
  if (e is HttpException) return true;
  if (e is TimeoutException) return true;
  if (e is http.ClientException) return true;
  // `HandshakeException` y familia envuelven el fallo real; el mensaje es la
  // unica senal disponible sin romper la cadena de causas.
  final mensaje = e.toString().toLowerCase();
  const pistasTransporte = [
    'failed host lookup',
    'connection refused',
    'connection reset',
    'connection closed',
    'network is unreachable',
    'no address associated',
    'broken pipe',
    'handshake',
    'socketexception',
  ];
  return pistasTransporte.any(mensaje.contains);
}
