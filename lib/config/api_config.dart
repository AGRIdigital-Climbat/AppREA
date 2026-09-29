class ApiConfig {
  static const String baseUrl = 'https://api.climbat.net/api/v2';

  static const String authEndpoint = '$baseUrl/auth';
  static const String sharedEndpoint = '$baseUrl/shared';
  static const String edanEndpoint = '$baseUrl/edan';
  static const String edanLocalidadesEndpoint = '$baseUrl/edan/localidades';

  static const String usuariosEndpoint = '$baseUrl/usuarios';
  static const String repositorioEndpoint = '$baseUrl/repositorio';
  static const String firmaDigitalEndpoint = '$baseUrl/firma-digital';

  // MotorIA - Asistente Jurídico (RAG, túnel TryCloudflare).
  static const String ragBaseUrl =
      'https://sci-supporting-vienna-skins.trycloudflare.com';
  static const String ragApiKey =
      '5NyaftKXfKrdWWLiT90hYm6ideMHTaz83VTBP1FgV1g';

  // Puente de IA (EDAN). Comparte el túnel y la clave (`API_AUTH_TOKEN`) con el
  // RAG de arriba: `/puente` es el proxy genérico, `/chat` hace RAG. El túnel
  // cambia en cada reinicio del servidor.
  static const String puenteBaseUrl = ragBaseUrl;
  static const String puenteApiKey = ragApiKey;
  static const int puenteMaxTokens = 4096;
  static const double puenteTemperatura = 0.3;

  // Asistente de llenado IA (Groq)
  static const String groqBaseUrl = 'https://api.groq.com/openai/v1';
  static const String groqModel = 'openai/gpt-oss-20b';
  static const int groqMaxTokens = 4096;
  static const double groqTemperature = 0.3;
  static const String groqApiKey =
      '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';
}
