import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../config/theme.dart';
import '../../models/ai/asistente_chat_message.dart';
import '../../providers/asistente_ia_provider.dart';
import '../../services/ai/asistente_ia_service.dart';
import '../../services/ai/asistente_voz_service.dart';

class AsistenteIABottomSheet extends StatefulWidget {
  final AsistenteIAProvider provider;

  const AsistenteIABottomSheet({super.key, required this.provider});

  @override
  State<AsistenteIABottomSheet> createState() => _AsistenteIABottomSheetState();
}

class _AsistenteIABottomSheetState extends State<AsistenteIABottomSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _textController = TextEditingController();
  final Set<int> _fuentesExpandidas = {};
  bool _started = false;

  AsistenteIAProvider get _provider => widget.provider;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _iniciarSiEsNecesario();
    });
  }

  Future<void> _iniciarSiEsNecesario() async {
    if (_provider.isActive || _started) return;
    _started = true;

    if (!AsistenteIAService.instance.hasApiKey) {
      _mostrarDialogoApiKey();
      return;
    }

    await _provider.init();
    if (!mounted) return;
    await _provider.iniciarConversacion();
  }

  void _mostrarDialogoApiKey() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Configurar token del Motor IA'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Token de autenticacion',
            border: OutlineInputBorder(),
          ),
          obscureText: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              final token = controller.text.trim();
              if (token.isEmpty) return;
              await AsistenteIAService.instance.setApiKey(token);
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              _started = false;
              await _iniciarSiEsNecesario();
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _scrollController.dispose();
    _textController.dispose();
    super.dispose();
  }

  void _scrollAlFinal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _enviarTexto() {
    final texto = _textController.text.trim();
    if (texto.isEmpty || _provider.isProcessing) return;
    _textController.clear();
    _provider.enviarPregunta(texto);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _provider,
      builder: (context, _) {
        _scrollAlFinal();

        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
            height: MediaQuery.of(context).size.height * 0.7,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                _buildHandle(),
                _buildHeader(),
                const Divider(height: 1),
                _buildModoBar(),
                const Divider(height: 1),
                Expanded(child: _buildMensajes()),
                if (_provider.isListening &&
                    _provider.textoEscuchado.isNotEmpty)
                  _buildTextoEscuchado(_provider.textoEscuchado),
                if (_provider.vozHabilitada &&
                    _provider.esperandoParaHablar &&
                    !_provider.isListening)
                  _buildPresioneParaHablar(),
                _buildInputArea(),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHandle() {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(Icons.smart_toy, color: Palettes.edan.primary, size: 22),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Asistente con IA',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
          if (_provider.isProcessing)
            IconButton(
              icon: const Icon(Icons.stop_circle, color: Color(0xFFEF4444)),
              tooltip: 'Cancelar respuesta',
              onPressed: () => _provider.cancelarPeticion(),
            ),
          if (_provider.isSpeaking)
            IconButton(
              icon: const Icon(Icons.volume_off, color: Color(0xFFEF4444)),
              tooltip: 'Callar',
              onPressed: () => _provider.detenerHabla(),
            ),
          if (_provider.isActive)
            IconButton(
              icon: const Icon(Icons.close, color: Colors.grey),
              tooltip: 'Cerrar asistente',
              onPressed: () {
                _provider.cancelar();
                Navigator.pop(context);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildModoBar() {
    final vozOn = _provider.vozHabilitada;
    final color = vozOn ? Palettes.edan.primary : const Color(0xFF94A3B8);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Row(
        children: [
          Icon(
            vozOn ? Icons.volume_up : Icons.volume_off,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 8),
          Text(
            vozOn ? 'Modo voz' : 'Modo texto',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const Spacer(),
          Switch(
            value: vozOn,
            onChanged: (_) => _provider.toggleVoz(),
            activeTrackColor: Palettes.edan.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildPresioneParaHablar() {
    return GestureDetector(
      onTap: () => _provider.toggleListening(),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: const Color(0xFFFFF8E1),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.mic_none, size: 16, color: Palettes.edan.primary),
            const SizedBox(width: 8),
            Text(
              'Presiona para volver a hablar',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Palettes.edan.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMensajes() {
    final mensajes = _provider.mensajes;

    if (mensajes.isEmpty) {
      return const Center(
        child: Text(
          'Iniciando conversacion...',
          style: TextStyle(color: Color(0xFF94A3B8)),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: mensajes.length + (_provider.isProcessing ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == mensajes.length) {
          return _buildTypingIndicator();
        }
        final msg = mensajes[index];
        final esIA = msg.role == 'assistant';
        final texto =
            esIA &&
                index == mensajes.length - 1 &&
                _provider.bufferIA.isNotEmpty
            ? _provider.bufferIA
            : msg.content;
        final esUltimoError =
            esIA && index == mensajes.length - 1 && _provider.huboError;
        final esStreaming =
            esIA &&
            _provider.isProcessing &&
            index == mensajes.length - 1 &&
            _provider.bufferIA.isNotEmpty;
        return _buildMensaje(
          esIA,
          texto,
          msg.content,
          esUltimoError,
          msg.fuentes,
          msg.citas,
          esStreaming,
          index,
        );
      },
    );
  }

  Widget _buildMensaje(
    bool esIA,
    String texto,
    String contenidoOriginal,
    bool mostrarRetry,
    List<AsistenteFuente>? fuentes,
    Map<String, AsistenteCita>? citas,
    bool esStreaming,
    int index,
  ) {
    return Align(
      alignment: esIA ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        child: Column(
          crossAxisAlignment: esIA
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.end,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: esIA ? const Color(0xFFF1F5F9) : Palettes.edan.primary,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  esIA
                      ? MarkdownBody(
                          data: _expandirCitas(texto, citas),
                          styleSheet: MarkdownStyleSheet(
                            p: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF1E293B),
                              height: 1.4,
                            ),
                            strong: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF1E293B),
                              fontWeight: FontWeight.w700,
                            ),
                            em: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF1E293B),
                              fontStyle: FontStyle.italic,
                            ),
                            listBullet: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                        )
                      : Text(
                          texto,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.white,
                            height: 1.4,
                          ),
                        ),
                  if (esIA)
                    _buildAccionesMensaje(contenidoOriginal, mostrarRetry),
                ],
              ),
            ),
            if (esIA && !esStreaming && fuentes != null && fuentes.isNotEmpty)
              _buildTarjetaFuentes(fuentes, citas, index),
          ],
        ),
      ),
    );
  }

  Widget _buildAccionesMensaje(String contenido, bool mostrarRetry) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (contenido.isNotEmpty) ...[
            GestureDetector(
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: contenido));
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Respuesta copiada'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              child: const Icon(
                Icons.copy,
                size: 15,
                color: Color(0xFF94A3B8),
              ),
            ),
            const SizedBox(width: 12),
          ],
          if (AsistenteVozService.instance.soportaVoz) ...[
            GestureDetector(
              onTap: () => _provider.reproducirMensaje(contenido),
              child: const Icon(
                Icons.volume_up,
                size: 15,
                color: Color(0xFF94A3B8),
              ),
            ),
            const SizedBox(width: 12),
          ],
          if (mostrarRetry)
            GestureDetector(
              onTap: () => _provider.reintentar(),
              child: const Icon(
                Icons.refresh,
                size: 16,
                color: Color(0xFFEF4444),
              ),
            ),
        ],
      ),
    );
  }

  String _expandirCitas(String texto, Map<String, AsistenteCita>? citas) {
  if (citas == null || citas.isEmpty) return texto;
  return texto.replaceAllMapped(
    RegExp(r'\[(\d+)\]'),
    (match) {
      final cita = citas[match.group(1)];
      if (cita == null) return match.group(0)!;
      final numeral = cita.numeral.isNotEmpty ? ' (${cita.numeral})' : '';
      return '[${cita.documentoId}] ${cita.titulo}$numeral';
    },
  );
}

AsistenteCita? _citaDeFuente(
    Map<String, AsistenteCita>? citas,
    AsistenteFuente fuente,
  ) {
  if (citas == null || citas.isEmpty) return null;
  for (final cita in citas.values) {
    if (cita.documentoId == fuente.documentoId) return cita;
  }
  return null;
}

Widget _buildTarjetaFuentes(
    List<AsistenteFuente> fuentes,
    Map<String, AsistenteCita>? citas,
    int index,
  ) {
    final expandida = _fuentesExpandidas.contains(index);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              setState(() {
                if (!_fuentesExpandidas.add(index)) {
                  _fuentesExpandidas.remove(index);
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.description_outlined,
                    size: 15,
                    color: Color(0xFF1D4ED8),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Referencias (${fuentes.length})',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  ),
                  Icon(
                    expandida ? Icons.expand_more : Icons.chevron_right,
                    size: 18,
                    color: const Color(0xFF94A3B8),
                  ),
                ],
              ),
            ),
          ),
          if (expandida)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < fuentes.length; i++) ...[
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 22,
                              height: 22,
                              alignment: Alignment.center,
                              decoration: const BoxDecoration(
                                color: Color(0xFFEDF2FF),
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '${i + 1}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1D4ED8),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    fuentes[i].titulo,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF334155),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Wrap(
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          spacing: 6,
                                          children: [
                                            if (fuentes[i].tipo.isNotEmpty)
                                              Text(
                                                fuentes[i].tipo,
                                                style: const TextStyle(
                                                  fontSize: 10.5,
                                                  color: Color(0xFF94A3B8),
                                                ),
                                              ),
                                            if (fuentes[i].tipo.isNotEmpty &&
                                                fuentes[i]
                                                    .numerals
                                                    .isNotEmpty)
                                              const Text(
                                                '·',
                                                style: TextStyle(
                                                  fontSize: 10.5,
                                                  color: Color(0xFF94A3B8),
                                                ),
                                              ),
                                            if (fuentes[i].numerals.isNotEmpty)
                                              Text(
                                                fuentes[i].numerals.join(', '),
                                                style: const TextStyle(
                                                  fontSize: 10.5,
                                                  color: Color(0xFF1D4ED8),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      if (fuentes[i].similitud > 0) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 1,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFDCfCE7),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            '${(fuentes[i].similitud * 100).round()}%',
                                            style: const TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF16A34A),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  if (_citaDeFuente(citas, fuentes[i]) != null) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      'Cita: ${_citaDeFuente(citas, fuentes[i])!.numeral}',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontStyle: FontStyle.italic,
                                        color: Color(0xFF7C3AED),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (i < fuentes.length - 1) const SizedBox(height: 6),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text(
              'Pensando...',
              style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextoEscuchado(String texto) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFFFFF8E1),
      child: Row(
        children: [
          const Icon(Icons.hearing, size: 16, color: Color(0xFFF59E0B)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(fontSize: 12, color: Color(0xFF92400E)),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            iconSize: 16,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: const Icon(Icons.close, color: Color(0xFF92400E)),
            tooltip: 'Cancelar y volver a hablar',
            onPressed: () => _provider.cancelarEscucha(),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              enabled: !_provider.isProcessing,
              decoration: InputDecoration(
                hintText: 'Escribe tu pregunta...',
                hintStyle: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF94A3B8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(color: Palettes.edan.primary),
                ),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
              ),
              style: const TextStyle(fontSize: 13),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _enviarTexto(),
            ),
          ),
          const SizedBox(width: 8),
          if (_provider.isProcessing)
            const SizedBox(
              width: 36,
              height: 36,
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.send, size: 20),
              color: Palettes.edan.primary,
              onPressed: _enviarTexto,
            ),
          if (_provider.vozHabilitada) ...[
            const SizedBox(width: 4),
            _buildMicButton(),
          ],
        ],
      ),
    );
  }

  Widget _buildMicButton() {
    final isActive = _provider.isListening;
    final isBusy = _provider.isProcessing || _provider.isSpeaking;
    final vozOn = _provider.vozHabilitada;

    return GestureDetector(
      onTap: (isBusy || !vozOn) ? null : () => _provider.toggleListening(),
      child: ListenableBuilder(
        listenable: _pulseAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: isActive ? _pulseAnimation.value : 1.0,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: !vozOn
                    ? const Color(0xFFCBD5E1)
                    : isActive
                    ? const Color(0xFFDC2626)
                    : isBusy
                    ? const Color(0xFF94A3B8)
                    : Palettes.edan.primary,
                boxShadow: [
                  if (isActive)
                    BoxShadow(
                      color: const Color(0xFFDC2626).withValues(alpha: 0.4),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                ],
              ),
              child: Icon(
                isActive ? Icons.mic : Icons.mic_none,
                color: Colors.white,
                size: 20,
              ),
            ),
          );
        },
      ),
    );
  }
}
