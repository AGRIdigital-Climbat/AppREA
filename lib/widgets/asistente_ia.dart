import 'dart:async';
import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../services/motor_ia_service.dart';

/// Abre el chat del asistente IA en un bottom sheet modal.
/// Envuelve el contenido en el [PaletteScope] del contexto para conservar el tema.
Future<void> showAsistenteIa(BuildContext context) {
  final palette = PaletteScope.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => PaletteScope(
      palette: palette,
      child: Theme(
        data: AppTheme.buildTheme(palette),
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: FractionallySizedBox(
            heightFactor: 0.88,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Expanded(child: AsistenteIaChat()),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// FAB pequeño de acceso al asistente IA. Pensado para apilarse sobre el FAB
/// principal (u ocupar su lugar cuando no lo hay): siempre visible y abierto
/// desde cualquier pantalla sin depender del AppBar.
class AsistenteIaFab extends StatelessWidget {
  final Color? fabColor;
  const AsistenteIaFab({super.key, this.fabColor});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.small(
      tooltip: 'Asistente IA',
      backgroundColor: fabColor ?? PaletteScope.of(context).primary,
      foregroundColor: Colors.white,
      onPressed: () => showAsistenteIa(context),
      child: const Icon(Icons.smart_toy_outlined),
    );
  }
}

/// Chat del asistente IA reutilizable. Requiere estar bajo un widget con
/// altura acotada (por ejemplo, dentro de un [Expanded]).
class AsistenteIaChat extends StatefulWidget {
  const AsistenteIaChat({super.key});

  @override
  State<AsistenteIaChat> createState() => _AsistenteIaChatState();
}

class _AsistenteIaChatState extends State<AsistenteIaChat> {
  final TextEditingController _chatCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  String _pregunta = '';
  String _chatRespuesta = '';
  List<MotorFuente> _chatFuentes = const [];
  bool _chatCargando = false;
  bool _chatDegradado = false;
  int _tokensRecibidos = 0;
  StreamSubscription<MotorRespuesta>? _chatSub;
  Timer? _fallbackTimer;

  static const List<String> _ejemplos = [
    '¿Qué datos lleva la sección de salud?',
    '¿Qué es un damnificado?',
    '¿Cómo envío el reporte al UGR?',
  ];

  @override
  void dispose() {
    _chatSub?.cancel();
    _fallbackTimer?.cancel();
    _scrollCtrl.dispose();
    _chatCtrl.dispose();
    super.dispose();
  }

  Future<void> _enviarPregunta() async {
    final pregunta = _chatCtrl.text.trim();
    if (pregunta.isEmpty || _chatCargando) return;
    await _enviar(pregunta);
  }

  Future<void> _enviarEjemplo(String pregunta) async {
    if (_chatCargando) return;
    await _enviar(pregunta);
  }

  Future<void> _enviar(String pregunta) async {
    FocusScope.of(context).unfocus();
    _chatCtrl.clear();
    await _chatSub?.cancel();
    setState(() {
      _pregunta = pregunta;
      _chatRespuesta = '';
      _chatFuentes = const [];
      _chatCargando = true;
      _chatDegradado = false;
      _tokensRecibidos = 0;
    });
    _scrollAlFinal();

    _fallbackTimer?.cancel();
    _fallbackTimer = Timer(const Duration(seconds: 60), () async {
      if (!mounted || _tokensRecibidos > 0 || !_chatCargando) return;
      try {
        final r = await MotorIA.instance.buscar(pregunta);
        if (!mounted) return;
        setState(() {
          _chatCargando = false;
          _chatRespuesta = r.texto;
          _chatFuentes = r.fuentes;
          _chatDegradado = true;
        });
        _scrollAlFinal();
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _chatCargando = false;
          _chatRespuesta =
              'El asistente no respondió. Intenta de nuevo más tarde.';
        });
      }
    });

    try {
      _chatSub = MotorIA.instance.chatStream(pregunta).listen(
        (r) {
          if (!mounted) return;
          setState(() {
            _tokensRecibidos++;
            _chatCargando = false;
            if (r.fuentes.isNotEmpty) _chatFuentes = r.fuentes;
            if (r.texto.isNotEmpty) _chatRespuesta = r.texto;
          });
          _scrollAlFinal();
        },
        onError: (Object _) {
          if (!mounted) return;
          setState(() {
            _chatCargando = false;
            if (_chatRespuesta.isEmpty) {
              _chatRespuesta =
                  'El asistente no respondió. Intenta de nuevo más tarde.';
            }
          });
        },
        onDone: () {
          if (!mounted) return;
          setState(() => _chatCargando = false);
        },
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _chatCargando = false;
        _chatRespuesta =
            'El asistente no respondió. Intenta de nuevo más tarde.';
      });
    }
  }

  void _scrollAlFinal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final primary = PaletteScope.of(context).primary;
    final accent = Palettes.edan.accent;
    final mostrandoConversacion =
        _pregunta.isNotEmpty || _chatRespuesta.isNotEmpty;
    return Column(
      children: [
        _buildHeader(primary, accent),
        Expanded(
          child: mostrandoConversacion
              ? _buildConversacion(primary, accent)
              : _buildBienvenida(primary),
        ),
        _buildInput(primary),
      ],
    );
  }

  Widget _buildHeader(Color primary, Color accent) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primary, accent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.smart_toy_outlined, color: primary, size: 20),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Asistente IA',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'Pregunta sobre el EDAN o las normas',
                  style: TextStyle(fontSize: 11.5, color: Colors.white),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Cerrar',
            onPressed: () => Navigator.of(context).maybePop(),
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.close, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _buildBienvenida(Color primary) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 12),
        Center(
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.smart_toy_outlined, color: primary, size: 34),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '¿En qué te ayudamos?',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: primary,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Pregunta sobre el EDAN, las normas o cómo llenar tu reporte. '
          'Recibirás respuestas con las fuentes consultadas.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.5,
            height: 1.5,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 20),
        for (final e in _ejemplos) ...[
          _buildEjemploChip(primary, e),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _buildEjemploChip(Color primary, String texto) {
    return Material(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _enviarEjemplo(texto),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(
            children: [
              Icon(Icons.lightbulb_outline, size: 16, color: primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  texto,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const Icon(
                Icons.north_west,
                size: 14,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConversacion(Color primary, Color accent) {
    return ListView(
      controller: _scrollCtrl,
      padding: const EdgeInsets.all(16),
      children: [
        _buildBurbujaUsuario(primary, accent, _pregunta),
        const SizedBox(height: 10),
        if (_chatCargando && _chatRespuesta.isEmpty)
          _buildEscribiendo(primary)
        else ...[
          _buildBurbujaAsistente(primary, _chatRespuesta),
          if (_chatDegradado) ...[
            const SizedBox(height: 8),
            Text(
              'El asistente tardó demasiado; se muestran resultados de búsqueda.',
              style: TextStyle(
                fontSize: 11,
                color: primary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          if (_chatFuentes.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Fuentes consultadas',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: primary,
              ),
            ),
            const SizedBox(height: 8),
            for (final f in _chatFuentes) _buildFuente(f, primary),
          ],
        ],
      ],
    );
  }

  Widget _buildBurbujaUsuario(Color primary, Color accent, String texto) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [primary, accent],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(4),
          ),
        ),
        child: Text(
          texto,
          style: const TextStyle(fontSize: 13, color: Colors.white, height: 1.4),
        ),
      ),
    );
  }

  Widget _buildEscribiendo(Color primary) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Text(
              'El asistente está pensando…',
              style: TextStyle(fontSize: 12, color: primary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBurbujaAsistente(Color primary, String texto) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.smart_toy_outlined, size: 16, color: primary),
                const SizedBox(width: 6),
                Text(
                  'Asistente',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              texto,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
                height: 1.5,
              ),
            ),
            if (_chatCargando) ...[
              const SizedBox(height: 8),
              const Row(
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 6),
                  Text(
                    'Escribiendo…',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFuente(MotorFuente f, Color primary) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.description_outlined, size: 18, color: primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  f.titulo,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (f.numerals.isNotEmpty)
                  Text(
                    f.numerals.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInput(Color primary) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _chatCtrl,
              enabled: !_chatCargando,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _enviarPregunta(),
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Escribe tu pregunta…',
                isDense: true,
                filled: true,
                fillColor: AppColors.background,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(color: primary, width: 1.5),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: primary.withValues(alpha: 0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: IconButton(
              onPressed: _chatCargando ? null : _enviarPregunta,
              style: IconButton.styleFrom(
                backgroundColor: primary,
                disabledBackgroundColor: AppColors.divider,
                foregroundColor: Colors.white,
                shape: const CircleBorder(),
              ),
              icon: _chatCargando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send),
            ),
          ),
        ],
      ),
    );
  }
}
