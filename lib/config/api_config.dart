class ApiConfig {
  static const String baseUrl = 'https://api.climbat.net/api/v1';
  
  static const String authEndpoint = '$baseUrl/auth';
  static const String sharedEndpoint = '$baseUrl/shared';
  static const String reaEndpoint = '$baseUrl/rea';
  static const String edanEndpoint = '$baseUrl/edan';
  static const String edanLocalidadesEndpoint = '$baseUrl/edan/localidades';
  static const String usuariosEndpoint = '$baseUrl/usuarios';
  static const String repositorioEndpoint = '$baseUrl/repositorio';

  // MotorIA - Asistente (túnel TryCloudflare, la URL cambia con el tiempo).
  static const String motorIaBaseUrl =
      'https://coal-lauren-coordination-sparc.trycloudflare.com';
}
