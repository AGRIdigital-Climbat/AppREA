/// La conversación de llenado del formulario EDAN.
///
/// Es la pantalla donde la persona hace la evaluación hablando. Todo lo que
/// muestra sale del [EdanIaBorradorProvider]: los mensajes, el avance, los
/// avisos de población y la decisión de pasar al paso de fotos. Acá no hay
/// lógica de formulario, solo presentación.
///
/// Dos decisiones que no son obvias:
///
/// 1. **El micrófono manda.** El campo de texto está, porque en una zona sin
///    señal o con la mano llena escribir es más realistic que hablar, pero el
///    botón grande es el queStarts la captura.
/// 2. **Los avisos de población se muestran aunque el modelo no los haya
///    dicho.** Una suma que no cierra es un dato que va a llegar al reporte
///    igual, y esconderlo detrás de lo que Contestó el chatbot sería deixar que
///    la persona firmara una incoherencia sin saberlo.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../config/theme.dart';
import '../../../../models/edan.dart';
import '../../../../models/edan_borrador_ia.dart';
import '../../../../providers/edan_ia_borrador_provider.dart';
import '../../../../services/edan_ia/edan_traduccion.dart';
import 'edan_ia_paso_fotos.dart';

/// Pantalla de conversación. Recibe el provider ya construido para que la
/// pantalla no dependa de cómo se arma la dependencia.
class EdanIaAsistenteScreen extends StatefulWidget {
  final EdanIaBorradorProvider provider;

  /// Id del usuario que guarda. Lo necesita la persistencia.
  final int usuarioId;

  /// Se llama al terminar con la ficha guardada.
  final void Function(EdanLocalidad localidad)? onGuardado;

  const EdanIaAsistenteScreen({
    super.key,
    required this.provider,
    required this.usuarioId,
    this.onGuardado,
  });

  @override
  State<EdanIaAsistenteScreen> createState() => _EdanIaAsistenteScreenState();
}

class _EdanIaAsistenteScreenState extends State<EdanIaAsistenteScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  bool _guardando = false;

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _bajar() {
    // El salto se hace después del frame porque el mensaje todavía no está
    // medido: si se hace de una, el scroll queda a medias.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _enviar([String? texto]) async {
    final t = (texto ?? _controller.text).trim();
    if (t.isEmpty) return;
    _controller.clear();
    _bajar();
    await widget.provider.enviar(t);
    _bajar();
  }

  Future<void> _guardar([EdanTraduccionResultado? preparado]) async {
    setState(() => _guardando = true);
    try {
      final r = preparado ?? widget.provider.prepararGuardado();
      final id = await widget.provider.guardar(
        usuarioId: widget.usuarioId,
        preparado: r,
      );
      if (!mounted) return;
      widget.onGuardado?.call(r.localidad);
      _avisar('Ficha guardada ($id)', AppColors.aprobado);
      // Se avisa a quien abrió la pantalla (el FAB +) para que refresque la
      // lista. Solo al guardar: volver atrás sin guardar no es una ficha nueva.
      Navigator.of(context).pop(true);
    } on EdanPoblacionIncoherente catch (e) {
      // No es un error de la app: son números que no cierran. Se muestra el
      // texto del aviso, que es el mismo que ve en el wizard.
      _avisar(e.toString(), const Color(0xFFF59E0B));
    } catch (e) {
      _avisar('No se pudo guardar: $e', AppColors.error);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  void _avisar(String texto, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(texto),
      backgroundColor: color,
      duration: const Duration(seconds: 4),
    ));
  }

  void _irAFotos() {
    final r = widget.provider.prepararGuardado();
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => EdanIaPasoFotosScreen(
        localidad: r.localidad,
        onListo: (l) {
          // Se guarda ESTA localidad, la que volvió del paso final con
          // `fotografia` y las coordenadas. Antes se llamaba a guardar sin
          // argumento, el provider re-traducía el borrador y armaba otra
          // localidad: las fotos se perdían justo al cerrar la ficha.
          _guardar(EdanTraduccionResultado(
            localidad: l,
            seccionesActivas: r.seccionesActivas,
            avisos: r.avisos,
          ));
          Navigator.of(context).pop();
        },
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<EdanIaBorradorProvider>.value(
      value: widget.provider,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Llenar por voz'),
          actions: [
            Consumer<EdanIaBorradorProvider>(
                builder: (_, p, _) => IconButton(
                tooltip: 'Empezar de nuevo',
                onPressed: p.mensajes.isEmpty ? null : p.reiniciar,
                icon: const Icon(Icons.restart_alt),
              ),
            ),
            // Guardar vive en el AppBar: la barra de ingreso es para hablar.
            // El aviso de bloqueo se muestra acá para no competir con el
            // campo de texto por el ancho en pantallas angostas.
            Consumer<EdanIaBorradorProvider>(
              builder: (_, p, _) => IconButton(
                tooltip: p.bloqueaGuardar
                    ? 'Revisá los avisos de la conversación'
                    : 'Guardar en el dispositivo',
                onPressed: _guardando || p.bloqueaGuardar ? null : _guardar,
                icon: _guardando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        Icons.save_outlined,
                        color: p.bloqueaGuardar ? AppColors.textSecondary : null,
                      ),
              ),
            ),
          ],
        ),
        body: Consumer<EdanIaBorradorProvider>(
            builder: (_, p, _) => Column(
            children: [
              _Progreso(avance: p.avance),
              const _Avisos(),
              Expanded(
                child: p.mensajes.isEmpty
                    ? _Bienvenida(pendientes: p.pendientes)
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                        itemCount: p.mensajes.length +
                            (p.respuestaEnCurso.isEmpty ? 0 : 1),
                        itemBuilder: (_, i) {
                          if (i == p.mensajes.length) {
                            return _Burbuja(
                              texto: p.respuestaEnCurso,
                              esUsuario: false,
                              escribiendo: true,
                            );
                          }
                          final m = p.mensajes[i];
                          return _Burbuja(
                            texto: m.texto,
                            esUsuario: m.esUsuario,
                            fallo: m.fallo,
                          );
                        },
                      ),
              ),
              _BarraIngreso(
                controller: _controller,
                onEnviar: _enviar,
                onEscuchar: () async {
                  _bajar();
                  await widget.provider.escucharYResponder();
                  _bajar();
                },
                onDetener: widget.provider.detener,
                onFotos: p.hayDatosParaFotos ? _irAFotos : null,
                ocupado: p.ocupado,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bienvenida extends StatelessWidget {
  final List<EdanProgresoSeccion> pendientes;
  const _Bienvenida({required this.pendientes});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.hearing, size: 60, color: AppColors.primary),
              const SizedBox(height: 14),
              Text(
                'Contame qué pasó',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Hablá como le contarías a alguien: "se cayó el puente de la '
                'ruta 1 y hay 40 personas afectadas". Yo voy anotando y te '
                'pregunto lo que falte. No hace falta que repitas nada.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade700, height: 1.35),
              ),
              if (pendientes.isNotEmpty) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final s in pendientes)
                      Chip(
                        label: Text(s.titulo, style: const TextStyle(fontSize: 11)),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      );
}

class _Progreso extends StatelessWidget {
  final double avance;
  const _Progreso({required this.avance});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: avance,
                minHeight: 6,
                backgroundColor: AppColors.divider,
                color: AppColors.aprobado,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${(avance * 100).round()}% de la ficha',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      );
}

/// Los avisos de población, como el banner del wizard.
///
/// Se leen del provider y no se guardan en estado propio: si se copian al
/// pintarse, el banner puede quedar mostrando un desajuste que ya se corrigió.
class _Avisos extends StatelessWidget {
  const _Avisos();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EdanIaBorradorProvider>();
    final avisos = provider.avisosPoblacion;
    if (avisos.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0x1AF59E0B),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFF59E0B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final a in avisos)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber, size: 16, color: Color(0xFFB45309)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(a.mensaje, style: const TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Burbuja extends StatelessWidget {
  final String texto;
  final bool esUsuario;
  final bool fallo;
  final bool escribiendo;

  const _Burbuja({
    required this.texto,
    required this.esUsuario,
    this.fallo = false,
    this.escribiendo = false,
  });

  @override
  Widget build(BuildContext context) {
    final fondo = esUsuario
        ? AppColors.primary
        : (fallo ? const Color(0xFFFDECEC) : Colors.white);
    final colorTexto = esUsuario ? Colors.white : Colors.black87;
    return Align(
      alignment: esUsuario ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: fondo,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(esUsuario ? 16 : 4),
            bottomRight: Radius.circular(esUsuario ? 4 : 16),
          ),
          border: esUsuario ? null : Border.all(color: AppColors.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: Text(
                texto,
                style: TextStyle(color: colorTexto, height: 1.3),
              ),
            ),
            if (escribiendo) ...[
              const SizedBox(width: 8),
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BarraIngreso extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onEnviar;
  final VoidCallback onEscuchar;
  final VoidCallback onDetener;
  final VoidCallback? onFotos;
  final bool ocupado;

  const _BarraIngreso({
    required this.controller,
    required this.onEnviar,
    required this.onEscuchar,
    required this.onDetener,
    this.onFotos,
    required this.ocupado,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.divider)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onFotos != null) ...[
              FilledButton.icon(
                onPressed: onFotos,
                icon: const Icon(Icons.photo_camera),
                label: const Text('Completar fotos y coordenadas'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.aprobado,
                  minimumSize: const Size.fromHeight(44),
                ),
              ),
              const SizedBox(height: 8),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => onEnviar(),
                    decoration: InputDecoration(
                      hintText: 'O escribí lo que pasó…',
                      isDense: true,
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: onEnviar,
                  icon: const Icon(Icons.send),
                  color: AppColors.primary,
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: ocupado ? onDetener : onEscuchar,
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ocupado ? AppColors.error : AppColors.primary,
                    ),
                    child: Icon(
                      ocupado ? Icons.stop : Icons.mic,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
