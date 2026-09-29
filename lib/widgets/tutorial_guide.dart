import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../config/theme.dart';

/// Posición del asistente en pantalla (equivalente a `ScreenPosition` en
/// `TutorialGuide.java`).
enum TutorialPosition {
  topLeft,
  topCenter,
  topRight,
  centerLeft,
  center,
  centerRight,
  bottomLeft,
  bottomCenter,
  bottomRight,
}

/// Lado hacia el que apunta la flecha del tooltip. La burbuja siempre queda
/// del lado opuesto, señalando al asistente (igual que `TooltipDirection`).
enum TutorialDirection { left, right, top, bottom }

/// Guía asistente en capa superior (port de `TutorialGuide.java` a Flutter).
///
/// Muestra un personaje + burbuja de ayuda con flecha, animados, por encima de
/// todas las vistas (rutas, bottom sheets y diálogos), con cierre por "tap
/// fuera", botón X y auto-ocultado configurable. Contenido totalmente libre.
///
/// Uso:
/// ```dart
/// TutorialGuide.of(context)
///   ..setTitulo('¿Cómo llenar esta sección?')
///   ..setConsejos(['● ...', '● ...'])
///   ..setPosicion(TutorialPosition.bottomRight)
///   ..setDireccion(TutorialDirection.left)
///   ..setColor(PaletteScope.of(context).primary)
///   ..setVisibilidad(const Duration(seconds: 8))
///   ..show();
/// ```
class TutorialGuide {
  TutorialGuide._(this._context)
      : _color = PaletteScope.of(_context).primary;

  final BuildContext _context;

  String _titulo = '';
  List<String> _consejos = const [];
  Widget? _contenido;
  Widget _personaje = const Icon(
    Icons.support_agent_outlined,
    color: Colors.white,
  );
  String? _imagenAsset;
  BoxFit _fitImagen = BoxFit.contain;
  bool _conFondo = true;
  double _margenImgIzquierda = 0;
  double _margenImgDerecha = 0;
  double _margenImgArriba = 0;
  double _margenImgAbajo = 0;
  double _tamanoPersonaje = 56;
  double? _tamanoPersonajeFactor;
  TutorialPosition _posicion = TutorialPosition.bottomRight;
  TutorialDirection _direccion = TutorialDirection.left;
  Color _color;
  Duration _visibilidad = const Duration(seconds: 5);
  VoidCallback? _onHideEnd;
  double _maxAnchoTooltip = 0.78;

  /// Guía activa a nivel de app (para no apilar varias).
  static VoidCallback? _dismissActiva;

  /// Pop de la ruta del diálogo actual de ESTA instancia. Nunca se dispara
  /// sobre una ruta ajena ni con un contexto ya desmontado.
  VoidCallback? _popRuta;

  /// Crea una instancia encadenable para el [context] dado.
  static TutorialGuide of(BuildContext context) => TutorialGuide._(context);

  // ---------------------------------------------------------------- setters

  TutorialGuide setTitulo(String value) {
    _titulo = value;
    return this;
  }

  /// Lista de consejos (búlets) mostrados bajo el título.
  TutorialGuide setConsejos(List<String> value) {
    _consejos = value;
    return this;
  }

  /// Contenido 100% libre dentro de la burbuja (reemplaza título y búlets).
  TutorialGuide setContenido(Widget value) {
    _contenido = value;
    return this;
  }

  /// Representación del asistente (por defecto un icono `support_agent`).
  TutorialGuide setPersonaje(Widget value) {
    _personaje = value;
    return this;
  }

  /// Usa una imagen PNG (transparente, estilo Java) como personaje, a la
  /// medida de [setTamanoPersonaje]. Desactiva el círculo de fondo; para
  /// reactivarlo usar [setConFondo].
  TutorialGuide setPersonajeImagen(
    String asset, {
    BoxFit fit = BoxFit.contain,
  }) {
    _imagenAsset = asset;
    _fitImagen = fit;
    _conFondo = false;
    return this;
  }

  /// Muestra el personaje sobre el círculo de color primario (por defecto
  /// `true` para iconos, `false` al usar una imagen).
  TutorialGuide setConFondo(bool value) {
    _conFondo = value;
    return this;
  }

  /// Desplaza la figura dentro de su caja SIN cambiarle el tamaño, para
  /// compensar el espacio en blanco propio del PNG.
  /// - `derecha` acerca la figura a la burbuja (si la burbuja está a la
  ///   derecha), `izquierda` la aleja hacia el borde.
  /// - `arriba`/`abajo` ajustan la alineación vertical.
  TutorialGuide setMargenesImagen({
    double izquierda = 0,
    double derecha = 0,
    double arriba = 0,
    double abajo = 0,
  }) {
    _margenImgIzquierda = izquierda;
    _margenImgDerecha = derecha;
    _margenImgArriba = arriba;
    _margenImgAbajo = abajo;
    return this;
  }

  /// Lado del cuadrado que contiene al personaje (por defecto 56).
  TutorialGuide setTamanoPersonaje(double value) {
    _tamanoPersonaje = value;
    return this;
  }

  /// Tamaño del personaje como FRACCIÓN del ancho de pantalla (0.05–0.5).
  /// Si se usa, tiene prioridad sobre [setTamanoPersonaje] y el personaje
  /// escala igual en cualquier resolución (clamp 24–160 dp).
  TutorialGuide setTamanoPersonajeFactor(double value) {
    _tamanoPersonajeFactor = value.clamp(0.05, 0.5).toDouble();
    return this;
  }

  /// Posición del asistente en pantalla.
  TutorialGuide setPosicion(TutorialPosition value) {
    _posicion = value;
    return this;
  }

  /// Hacia dónde apunta la flecha de la burbuja.
  TutorialGuide setDireccion(TutorialDirection value) {
    _direccion = value;
    return this;
  }

  /// Color de la burbuja, flecha y personaje.
  TutorialGuide setColor(Color value) {
    _color = value;
    return this;
  }

  /// Tiempo que la guía permanece antes de ocultarse sola
  /// (`Duration.zero` la deja abierta hasta cerrarla manualmente).
  TutorialGuide setVisibilidad(Duration value) {
    _visibilidad = value;
    return this;
  }

  /// Ancho máximo de la burbuja como fracción de la pantalla (0..1).
  TutorialGuide setMaxAnchoTooltip(double value) {
    _maxAnchoTooltip = value.clamp(0.3, 1.0).toDouble();
    return this;
  }

  /// Callback ejecutado cuando la guía se cierra (por cualquier vía).
  TutorialGuide setOnHideEnd(VoidCallback value) {
    _onHideEnd = value;
    return this;
  }

  // --------------------------------------------------------------- acciones

  /// Muestra la guía por encima de todas las vistas (modal; tocar fuera o X
  /// la cierra). Cierra cualquier guía activa previa.
  Future<void> show() async {
    _cerrarActiva();
    var activa = true;
    void ocultar() {
      if (!activa) return;
      final pop = _popRuta;
      if (pop != null) pop();
    }

    _dismissActiva = ocultar;
    try {
      await showGeneralDialog<void>(
        context: _context,
        useRootNavigator: true,
        barrierDismissible: true,
        barrierLabel: 'Cerrar guía de ayuda',
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (ctx, _, _) {
          // El pop siempre apunta a la ruta del propio diálogo; si la ruta ya
          // se desmontó, no hace nada. Nunca toca rutas ajenas.
          _popRuta = () {
            if (ctx.mounted) Navigator.of(ctx, rootNavigator: true).pop();
          };
          return _GuiaOverlay(guia: this);
        },
        transitionBuilder: (ctx, anim, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: child,
        ),
      );
    } finally {
      activa = false;
      _popRuta = null;
      // Solo se limpia si el handle sigue siendo el de ESTA guía; si vino una
      // guía nueva (que ya se cerró esta), se respeta su handle.
      if (identical(_dismissActiva, ocultar)) _dismissActiva = null;
    }
    _onHideEnd?.call();
  }

  /// Cierra la guía si está visible.
  void hide() {
    _cerrarActiva();
  }

  void _cerrarActiva() {
    final d = _dismissActiva;
    if (d != null) {
      _dismissActiva = null;
      d();
    }
  }
}

// ---------------------------------------------------------------------------

/// Constantes geométricas de la capa de la guía.
const double _margen = 16;
const double _espaciadoFlecha = 0;
const double _tamFlecha = 10;
const double _radioBurbuja = 14;

class _GuiaOverlay extends StatefulWidget {
  final TutorialGuide guia;

  const _GuiaOverlay({required this.guia});

  @override
  State<_GuiaOverlay> createState() => _GuiaOverlayState();
}

class _GuiaOverlayState extends State<_GuiaOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  )..forward();

  Timer? _timer;
  Size? _tooltipSize;
  final GlobalKey _tooltipKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    final visible = widget.guia._visibilidad;
    if (visible > Duration.zero) {
      _timer = Timer(visible + const Duration(milliseconds: 700), _cerrar);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _medirTooltip());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _cerrar() {
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
  }

  void _medirTooltip() {
    if (!mounted) return;
    final rb = _tooltipKey.currentContext?.findRenderObject();
    if (rb is RenderBox) {
      final s = rb.size;
      if (s != _tooltipSize) setState(() => _tooltipSize = s);
    }
  }

  // ------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final g = widget.guia;
    return Material(
      type: MaterialType.transparency,
      child: LayoutBuilder(
        builder: (ctx, c) {
          final w = c.maxWidth;
          final h = c.maxHeight;
          final cs = g._tamanoPersonajeFactor != null
            ? (w * g._tamanoPersonajeFactor!).clamp(24.0, 160.0)
            : g._tamanoPersonaje;
          final fx = _fracX(g._posicion);
          final fy = _fracY(g._posicion);
          final charLeft =
              (fx * w - cs / 2).clamp(_margen, (w - cs - _margen).toDouble());
          final charTop =
              (fy * h - cs / 2).clamp(_margen, (h - cs - _margen).toDouble());
          final charCx = charLeft + cs / 2;
          final charCy = charTop + cs / 2;

          final medido = _tooltipSize;
          final maxAncho = (w * g._maxAnchoTooltip).toDouble();
          final capAlto =
              (h * 0.55).clamp(0.0, 520.0).toDouble();
          final ww = medido != null
              ? medido.width.clamp(_margen, maxAncho)
              : maxAncho;
          final hh = medido?.height ?? (capAlto * 0.55);

          // Rectángulo de la burbuja según dirección de la flecha.
          final rect = _rectBurbuja(
            g._direccion,
            w: w,
            h: h,
            cs: cs,
            charLeft: charLeft,
            charTop: charTop,
            charCx: charCx,
            charCy: charCy,
            ww: ww,
            hh: hh,
          );

          final arrowPos = _posFlecha(g._direccion, rect, charCx, charCy);

          return Stack(
            children: [
              // Capa opaca invisible: tocar en cualquier zona vacía cierra.
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _cerrar,
                ),
              ),
              Positioned(
                left: rect.left,
                top: rect.top,
                width: rect.width,
                child: _burbujaAnimada(g, arrowPos, capAlto),
              ),
              Positioned(
                left: charLeft,
                top: charTop,
                child: GestureDetector(
                  onTap: _cerrar,
                  child: _personajeAnimado(g, w, h, cs),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Posición/ancho/alto de la burbuja para la dirección dada.
  ({double left, double top, double width, double height}) _rectBurbuja(
    TutorialDirection dir, {
    required double w,
    required double h,
    required double cs,
    required double charLeft,
    required double charTop,
    required double charCx,
    required double charCy,
    required double ww,
    required double hh,
  }) {
    switch (dir) {
      case TutorialDirection.left:
        final ancho =
            ww.clamp(_margen, (charLeft - _espaciadoFlecha - _margen).toDouble());
        final alto = hh.clamp(_margen, h - 2 * _margen);
        final top = (charCy - alto / 2).clamp(_margen, h - _margen - alto);
        return (left: charLeft - _espaciadoFlecha - ancho, top: top,
            width: ancho, height: alto);
      case TutorialDirection.right:
        final ancho = ww
            .clamp(_margen, (w - charLeft - cs - _espaciadoFlecha - _margen).toDouble());
        final alto = hh.clamp(_margen, h - 2 * _margen);
        final top = (charCy - alto / 2).clamp(_margen, h - _margen - alto);
        return (left: charLeft + cs + _espaciadoFlecha,
            top: top, width: ancho, height: alto);
      case TutorialDirection.top:
        final ancho = ww.clamp(_margen, w - 2 * _margen);
        final alto = hh
            .clamp(_margen, (charTop - _espaciadoFlecha - _margen).toDouble());
        final leftC = (charCx - ancho / 2).clamp(_margen, w - _margen - ancho);
        return (left: leftC, top: charTop - _espaciadoFlecha - alto,
            width: ancho, height: alto);
      case TutorialDirection.bottom:
        final ancho = ww.clamp(_margen, w - 2 * _margen);
        final alto = hh.clamp(
          _margen,
          (h - charTop - cs - _espaciadoFlecha - _margen).toDouble(),
        );
        final leftC = (charCx - ancho / 2).clamp(_margen, w - _margen - ancho);
        return (
          left: leftC,
          top: charTop + cs + _espaciadoFlecha,
          width: ancho,
          height: alto,
        );
    }
  }

  /// Punto (en coordenadas de la burbuja) donde dibujar la flecha.
  double _posFlecha(
    TutorialDirection dir,
    ({double left, double top, double width, double height}) rect,
    double charCx,
    double charCy,
  ) {
    switch (dir) {
      case TutorialDirection.left:
      case TutorialDirection.right:
        return (charCy - rect.top)
            .clamp(_tamFlecha, rect.height - _tamFlecha)
            .toDouble();
      case TutorialDirection.top:
      case TutorialDirection.bottom:
        return (charCx - rect.left)
            .clamp(_tamFlecha, rect.width - _tamFlecha)
            .toDouble();
    }
  }

  // ------------------------------------------------------------ widgets aux

  /// Entrada secuencial: el personaje aparece primero y la burbuja entra
  /// después (escala + fade), igual que el port de Java.
  Widget _burbujaAnimada(TutorialGuide g, double arrowPos, double capAlto) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        // Comienza al 45% del controller (el personaje ya llegó).
        final local = ((_ctrl.value - 0.45) / 0.55).clamp(0.0, 1.0);
        final escala = Curves.easeOutBack.transform(local);
        final opacidad = Curves.easeOut.transform(local);
        return Opacity(
          opacity: opacidad,
          child: Transform.scale(
            scale: escala < 0.01 ? 0.01 : escala,
            child: _burbuja(g, arrowPos, capAlto),
          ),
        );
      },
    );
  }

  Widget _burbuja(TutorialGuide g, double arrowPos, double capAlto) {
    return RepaintBoundary(
      key: _tooltipKey,
      child: CustomPaint(
        painter: _BubblePainter(
          color: g._color,
          direction: g._direccion,
          arrowPos: arrowPos,
        ),
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxWidth: double.infinity, maxHeight: capAlto),
          child: SingleChildScrollView(
            padding: g._contenido != null || g._titulo.isNotEmpty
                ? const EdgeInsets.fromLTRB(16, 12, 8, 16)
                : const EdgeInsets.fromLTRB(16, 12, 40, 16),
            child: _cuerpo(g),
          ),
        ),
      ),
    );
  }

  Widget _cuerpo(TutorialGuide g) {
    if (g._contenido != null) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: g._contenido!),
          _cerrarBoton(g),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (g._titulo.isNotEmpty) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  g._titulo,
                  style: TextStyle(
                    color: g._color,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                ),
              ),
              _cerrarBoton(g),
            ],
          ),
          if (g._consejos.isNotEmpty) const SizedBox(height: 10),
        ],
        for (final c in g._consejos)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: g._color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    c,
                    style: const TextStyle(
                      color: Colors.black87,
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _cerrarBoton(TutorialGuide g) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: IconButton(
        tooltip: 'Cerrar guía',
        visualDensity: VisualDensity.compact,
        onPressed: _cerrar,
        iconSize: 20,
        color: g._color,
        icon: const Icon(Icons.close),
      ),
    );
  }

  Widget _personajeAnimado(TutorialGuide g, double w, double h, double cs) {
    final (ex, ey) = _origen(g._posicion);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = Curves.decelerate.transform(_ctrl.value);
        final fade = Curves.easeOut.transform((_ctrl.value / 0.35).clamp(0.0, 1.0));
        final centro = g._posicion == TutorialPosition.center;
        final deslizaX = centro ? 0.0 : ex * (1 - t) * w * 0.85;
        final deslizaY = centro ? 0.0 : ey * (1 - t) * h * 0.85;
        final escala = centro
            ? 0.6 + 0.4 * Curves.easeOutBack.transform(_ctrl.value)
            : 1.0;

        final contenido = g._imagenAsset != null
            ? Image.asset(
                g._imagenAsset!,
                fit: g._fitImagen,
                width: cs,
                height: cs,
              )
            : g._personaje;

        Widget hijo;
        if (g._conFondo) {
          hijo = SizedBox(
            width: cs,
            height: cs,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: g._color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Center(child: contenido),
            ),
          );
        } else {
          // Modo imagen: transparente, sin círculo. Sombra suave dinámica que
          // sigue el contorno del PNG (silueta negra del alpha difuminada).
          // Desplazamiento configurable para compensar el blanco del PNG.
          final dx = g._margenImgDerecha - g._margenImgIzquierda;
          final dy = g._margenImgAbajo - g._margenImgArriba;
          hijo = SizedBox(
            width: cs,
            height: cs,
            child: Transform.translate(
              offset: Offset(dx, dy),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Transform.translate(
                    offset: const Offset(0, 3),
                    child: Opacity(
                      opacity: 0.4,
                      child: ImageFiltered(
                        imageFilter:
                            ImageFilter.blur(sigmaX: 4.5, sigmaY: 4.5),
                        child: ColorFiltered(
                          colorFilter: const ColorFilter.mode(
                              Colors.black, BlendMode.srcIn),
                          child: contenido,
                        ),
                      ),
                    ),
                  ),
                  contenido,
                ],
              ),
            ),
          );
        }

        if (centro) {
          hijo = Transform.scale(scale: escala, child: hijo);
        } else {
          hijo = Transform.translate(
            offset: Offset(deslizaX, deslizaY),
            child: hijo,
          );
        }
        return Opacity(opacity: fade, child: hijo);
      },
    );
  }
}

// ---------------------------------------------------------------------------

(double, double) _origen(TutorialPosition p) {
  switch (p) {
    case TutorialPosition.topLeft:
      return (-1, -1);
    case TutorialPosition.topCenter:
      return (0, -1);
    case TutorialPosition.topRight:
      return (1, -1);
    case TutorialPosition.centerLeft:
      return (-1, 0);
    case TutorialPosition.center:
      return (0, 0);
    case TutorialPosition.centerRight:
      return (1, 0);
    case TutorialPosition.bottomLeft:
      return (-1, 1);
    case TutorialPosition.bottomCenter:
      return (0, 1);
    case TutorialPosition.bottomRight:
      return (1, 1);
  }
}

double _fracX(TutorialPosition p) {
  switch (p) {
    case TutorialPosition.topLeft:
    case TutorialPosition.centerLeft:
    case TutorialPosition.bottomLeft:
      return 0.14;
    case TutorialPosition.topCenter:
    case TutorialPosition.center:
    case TutorialPosition.bottomCenter:
      return 0.5;
    default:
      return 0.86;
  }
}

double _fracY(TutorialPosition p) {
  switch (p) {
    case TutorialPosition.topLeft:
    case TutorialPosition.topCenter:
    case TutorialPosition.topRight:
      return 0.16;
    case TutorialPosition.centerLeft:
    case TutorialPosition.center:
    case TutorialPosition.centerRight:
      return 0.5;
    default:
      return 0.84;
  }
}

/// Pintor de la burbuja con flecha (equivalente a `CustomTooltipView.java`).
class _BubblePainter extends CustomPainter {
  final Color color;
  final TutorialDirection direction;
  final double arrowPos;

  const _BubblePainter({
    required this.color,
    required this.direction,
    required this.arrowPos,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final body = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(_radioBurbuja),
        ),
      );
    final tri = Path();
    switch (direction) {
      case TutorialDirection.left: // flecha a la derecha (hacia el personaje)
        tri
          ..moveTo(size.width + _tamFlecha, arrowPos)
          ..lineTo(size.width, arrowPos - _tamFlecha)
          ..lineTo(size.width, arrowPos + _tamFlecha)
          ..close();
      case TutorialDirection.right: // flecha a la izquierda
        tri
          ..moveTo(-_tamFlecha, arrowPos)
          ..lineTo(0, arrowPos - _tamFlecha)
          ..lineTo(0, arrowPos + _tamFlecha)
          ..close();
      case TutorialDirection.top: // flecha abajo
        tri
          ..moveTo(arrowPos, size.height + _tamFlecha)
          ..lineTo(arrowPos - _tamFlecha, size.height)
          ..lineTo(arrowPos + _tamFlecha, size.height)
          ..close();
      case TutorialDirection.bottom: // flecha arriba
        tri
          ..moveTo(arrowPos, -_tamFlecha)
          ..lineTo(arrowPos - _tamFlecha, 0)
          ..lineTo(arrowPos + _tamFlecha, 0)
          ..close();
    }
    final path = Path.combine(PathOperation.union, body, tri);
    canvas.drawShadow(path, Colors.black, 7, true);
    // Fondo blanco con acento rojo: cuerpo blanco, contorno rojo y flecha
    // roja sólida apuntando al personaje.
    canvas.drawPath(path, Paint()..color = Colors.white);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color,
    );
    canvas.drawPath(tri, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_BubblePainter old) =>
      old.color != color ||
      old.direction != direction ||
      old.arrowPos != arrowPos;
}