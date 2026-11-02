import 'package:flutter/material.dart';

import '../../../services/edan/edan_store_v2.dart';
import '../../../widgets/edan_galeria_view.dart';
import '../../../services/auth_service.dart';

/// Galería del rol 7 (RESP): sus propias fotos, agrupadas por localidad.
///
/// Toda la UI vive en el widget compartido [EdanGaleriaView] (que también
/// monta el UGR con alcance de municipio); aquí solo se inyecta el filtro
/// por usuario. `refresh()` sigue expuesto para `resp_screen`.
class RespGaleriaTab extends StatefulWidget {
  const RespGaleriaTab({super.key});

  @override
  State<RespGaleriaTab> createState() => RespGaleriaTabState();
}

class RespGaleriaTabState extends State<RespGaleriaTab> {
  final GlobalKey<EdanGaleriaViewState> _viewKey =
      GlobalKey<EdanGaleriaViewState>();

  void refresh() => _viewKey.currentState?.refresh();

  @override
  Widget build(BuildContext context) {
    return EdanGaleriaView(
      key: _viewKey,
      showAutor: false,
      carga: () async {
        final userId = AuthService.instance.userId;
        if (userId == null) return const [];
        return EdanStoreV2.instance.listarFotosGaleria(usuarioId: userId);
      },
    );
  }
}
