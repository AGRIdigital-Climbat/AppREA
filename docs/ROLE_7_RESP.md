# Rol 7 — Responsable Local (RESP)

> **Nota de vigencia (2026-10-19).** El envío ya no usa
> `/edan/localidades/{id}/documento` ni `/edan/localidades/sync/pull` (rutas
> eliminadas). Usa `POST/PUT /edan/formularios/completo`, `POST /edan/fotografias`
> y `GET /edan/sync/pull`. El mapa actualizado pantalla → API está en
> [`MAPA_APIS_WEB_EDAN.md`](./MAPA_APIS_WEB_EDAN.md).

## 1. Resumen del Rol

El **Responsable Local (RESP)** es el rol base de la aplicación SINAGER-SAT. Sus responsabilidades principales son:

- **Crear** reportes de localidad (formularios EDAN) con evidencia fotográfica georreferenciada.
- **Guardar** borradores localmente (funciona sin conexión a internet).
- **Enviar** localidades al UGR para revisión y consolidación.
- **Visualizar** sus reportes en lista, dashboard y mapa interactivo.
- **Gestionar** su perfil y credenciales.

El RESP opera desde `RespScreen` y es el único rol que puede **crear** localidades. El UGR (Rol 6) solo las revisa y consolida.

---

## 2. Arquitectura de Pantallas

### 2.1 `RespScreen` — Scaffold Principal

**Archivo:** `REA/lib/screens/role_screens/resp_screen.dart`

```
RespScreen (StatefulWidget)
├── AppBar
│   ├── Título dinámico (según pestaña)
│   ├── Botón sync con badge de pendientes
│   └── Badge de conectividad ("En línea" / "Sin conexión")
├── IndexedStack (5 tabs)
│   ├── [0] RespDashboardTab     — "Inicio"
│   ├── [1] RespEdanLocalidadTab — "Reportes"
│   ├── [2] RespMapaTab          — "Mapa"
│   ├── [3] RespGuiaTab          — "Guía"
│   └── [4] PerfilTab            — "Perfil"
├── FABs
│   ├── AsistenteIaFab           — siempre visible
│   ├── Nuevo reporte FAB (+)    — tabs 0 y 1
│   └── (sin FAB en tabs 2-4)
└── BottomNavigationBar (5 ítems)
```

#### Estado Principal

| Variable | Tipo | Propósito |
|----------|------|-----------|
| `_selectedIndex` | `int` | Pestaña actual |
| `_isProfileEditing` | `bool` | Estado de edición de perfil |
| `_wasOnline` | `bool` | Transiciones de conectividad |
| `_connectivity` | `ConnectivityProvider?` | Listener de red |

#### Inicialización

```dart
Future<void> _initialize() async {
  // 1. Registrar observer de ciclo de vida
  WidgetsBinding.instance.addObserver(this);
  
  // 2. Inicializar proveedor de conectividad
  _connectivity = Provider.of<ConnectivityProvider>(context, listen: false);
  _connectivity!.addListener(_onConnectivityChanged);
  
  // 3. Recargar pendientes de sync
  await LocalidadSyncService.instance.recargarPendientes();
  
  // 4. Inicializar catálogos y reportes
  await ReporteProvider.initializeResp();
  
  // 5. Configurar sync automático al restaurar conexión
  _wasOnline = _connectivity!.isConnected;
}
```

#### Sincronización

```dart
Future<void> _sincronizar() async {
  if (_sincronizando) return;
  if (!_connectivity!.isConnected) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Sin conexión a internet')),
    );
    return;
  }
  
  _sincronizando = true;
  try {
    final resultado = await LocalidadSyncService.instance.sincronizar();
    
    // Refrescar pestañas
    _dashboardTabKey.currentState?.refresh();
    _edanTabKey.currentState?.refresh();
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(resultado.resumen)),
    );
  } finally {
    _sincronizando = false;
  }
}
```

### 2.2 Navegación entre Pestañas

Las pestañas usan `IndexedStack` para preservar el estado:

```dart
IndexedStack(
  index: _selectedIndex,
  children: [
    RespDashboardTab(key: _dashboardTabKey, ...),
    RespEdanLocalidadTab(key: _edanTabKey, ...),
    RespMapaTab(key: _mapaTabKey, ...),
    RespGuiaTab(),
    PerfilTab(),
  ],
)
```

**Comunicación padre-hijo:**
- `KeyGlobalKey` permite al padre llamar `.refresh()` en hijos específicos
- Los indicadores del dashboard filtran la pestaña de reportes al tocarlos

---

## 3. Dashboard (Tab 0)

### 3.1 `RespDashboardTab`

**Archivo:** `REA/lib/screens/role_screens/resp/resp_dashboard_tab.dart`

#### Variables de Estado

```dart
List<EdanLocalidad> _localidades = [];  // Cargadas de SQLite, limit 15
```

#### Indicadores Calculados

```dart
final total = _localidades.length;
final huerfanas = _localidades.where((l) => l.esHuerfana).length;
final enviadas = _localidades.where((l) => l.estadoLocalidad == UgrLocalidadEstado.enviadoUgr).length;
final aprobadas = _localidades.where((l) => l.estadoLocalidad == UgrLocalidadEstado.aprobadoUgr).length;
final rechazadas = _localidades.where((l) => l.estadoLocalidad == UgrLocalidadEstado.rechazadoUgr).length;
```

#### Interacciones

| Acción | Condición | Resultado |
|--------|-----------|-----------|
| **Tocar indicador** | Siempre | Cambia a Tab 1 con filtro aplicado |
| **Tocar tarjeta** | Siempre | Navega a `UgrEdanPreviewScreen` (solo lectura) |
| **Editar** | `borrador` | Navega a `RespEdanFormScreen` con datos existentes |
| **Eliminar** | `borrador` | Diálogo de confirmación → elimina de SQLite |
| **Enviar** | `borrador` | Valida completitud → confirma → `enviadoUgr` → sync |

#### Flujo de Envío

```dart
void _enviarLocalidad(EdanLocalidad localidad) async {
  // 1. Validar completitud
  final incompletos = localidad.incompletosPorSeccion(exigirAlcalde: true);
  if (incompletos.isNotEmpty) {
    // Mostrar advertencia con secciones faltantes
    return;
  }
  
  // 2. Confirmar
  final confirmado = await showDialog<bool>(...);
  if (confirmado != true) return;
  
  // 3. Cambiar estado
  localidad.estadoLocalidad = UgrLocalidadEstado.enviadoUgr;
  localidad.sincronizado = false;
  
  // 4. Guardar en SQLite
  await DatabaseHelper.instance.updateLocalidad(localidad);
  
  // 5. Sync inmediato
  await LocalidadSyncService.instance.sincronizar();
  
  // 6. Refrescar
  refresh();
}
```

---

## 4. Pestaña Reportes (Tab 1)

### 4.1 `RespEdanLocalidadTab`

**Archivo:** `REA/lib/screens/role_screens/resp/resp_edan_localidad_tab.dart`

#### Variables de Estado

| Variable | Tipo | Propósito |
|----------|------|-----------|
| `_localidades` | `List<EdanLocalidad>` | Todas las localidades del usuario |
| `_cargando` | `bool` | Estado de carga |
| `_filtro` | `UgrLocalidadEstado?` | Filtro activo (null = Todas) |
| `_query` | `String` | Texto de búsqueda |

#### Barra de Filtros

```dart
Row(
  children: [
    FilterChip(
      label: Text('Todas'),
      selected: _filtro == null,
      onSelected: (_) => setState(() => _filtro = null),
    ),
    FilterChip(
      label: Text('Borrador'),
      selected: _filtro == UgrLocalidadEstado.borrador,
      onSelected: (_) => setState(() => _filtro = UgrLocalidadEstado.borrador),
    ),
    FilterChip(
      label: Text('Enviadas'),
      selected: _filtro == UgrLocalidadEstado.enviadoUgr,
      onSelected: (_) => setState(() => _filtro = UgrLocalidadEstado.enviadoUgr),
    ),
    FilterChip(
      label: Text('Aprobadas'),
      selected: _filtro == UgrLocalidadEstado.aprobadoUgr,
      onSelected: (_) => setState(() => _filtro = UgrLocalidadEstado.aprobadoUgr),
    ),
    FilterChip(
      label: Text('Rechazadas'),
      selected: _filtro == UgrLocalidadEstado.rechazadoUgr,
      onSelected: (_) => setState(() => _filtro = UgrLocalidadEstado.rechazadoUgr),
    ),
  ],
)
```

#### Búsqueda

Filtra por `nombre` o `tipoLocalidad` que contengan el texto de búsqueda.

#### Acciones por Tarjeta

| Estado | Acciones |
|--------|----------|
| `borrador` + `esMia` | Ver, Editar, Eliminar, Enviar |
| `enviadoUgr` | Ver (solo lectura) |
| `aprobadoUgr` | Ver (solo lectura) |
| `rechazadoUgr` | Ver (solo lectura) |

---

## 5. Formulario EDAN

### 5.1 `RespEdanFormScreen`

**Archivo:** `REA/lib/screens/role_screens/resp/resp_edan_form_screen.dart` (~2932 líneas)

Este es el formulario principal de creación/edición de localidades EDAN.

#### Variables de Estado Principales

| Variable | Tipo | Propósito |
|----------|------|-----------|
| `_edan` | `Edan` | Modelo siendo construido |
| `_expandidas` | `Set<String>` | Secciones expandidas (default: `{'01'}`) |
| `_lugarExpandido` | `int` | Índice de tarjeta de localidad expandida |
| `_seccionActual` | `String?` | Sección visible actual (por scroll) |
| `_idDepartamento/Provincia/Municipio` | `int?` | Ubicación seleccionada |
| `_idTipoEvento` | `int?` | Tipo de evento seleccionado |
| `_codigoIne` | `String?` | Código INE del municipio |
| `_siguienteNumero` | `int` | Siguiente número secuencial |

### 5.2 Secciones del Formulario

| Número | Título | Descripción | Visible cuando |
|--------|--------|-------------|----------------|
| 01 | Datos generales | Ubicación, nombres, tipo evento, fechas | Siempre |
| 02 | Población | Población total, familias afectadas | `impPoblacion` |
| 03 | Impacto en la población | Muertos/heridos por grupo etario | `impPoblacion` |
| 04 | Impacto en salud | Establecimientos dañados | `impSalud` |
| 05 | Impacto en infraestructuras | Vías, puentes, infra pública | `impInfraestructura` |
| 06 | Impacto en servicios básicos | Agua, luz, alcantarillado | `impServicios` |
| 07 | Impacto en educación | Unidades educativas | `impEducacion` |
| 08 | Impacto en viviendas | Viviendas parcial/totalmente dañadas | `impVivienda` |
| 09 | Impacto agropecuario | Agricultura, pecuario | `impAgropecuario` |
| 10 | Impacto en protección | Población vulnerable por sexo | `impProteccion` |
| 11 | Necesidades humanitarias | Alimentos, refugio, higiene | `impNecesidades` |
| 13 | Responsable | Datos del usuario que llena | Siempre |

### 5.3 Generación de Código EDAN

```dart
String _generarCodigoEdan() {
  // Formato: {codigoIne}/{año}/{NNN}
  final anio = DateTime.now().year;
  final codigoIne = _codigoIne ?? '00000';
  final numero = _siguienteNumero.toString().padLeft(3, '0');
  
  return '$codigoIne/$anio/$numero';
}
```

El código se auto-genera basándose en:
1. El código INE del municipio
2. El año actual
3. El siguiente número secuencial (se incrementa con cada EDAN del municipio/año)

### 5.4 Flujo de Captura de Fotos

Cada sub-item (establecimiento salud, vía, vivienda, etc.) tiene un botón de foto:

```
_BotonSacarFoto
│
├─ 1. "Coordenadas" → LocationService().getCurrentLocation()
│   └─ Polling hasta accuracy < 30m (timeout 45s)
│
└─ 2. "Sacar foto" → ImageService().takePhoto()
    └─ Guarda localmente + almacena GPS coords
```

**Modelo de foto:**
```dart
class EdanFoto {
  String ruta;          // Ruta local del archivo
  double latitud;       // GPS latitude
  double longitud;      // GPS longitude
  double precision;     // GPS accuracy in meters
  String? fecha;        // Timestamp
}
```

### 5.5 Barra de Acciones (Bottom)

```
┌─────────────────────────────────────┐
│ ████████░░░░ 8/10 secciones listas  │  ← Indicador de progreso
├─────────────────────────────────────┤
│ [Borrador]           [V. previa]    │
└─────────────────────────────────────┘
```

- **"Borrador"**: Guarda como borrador en SQLite, retorna a la pantalla anterior
- **"V. previa"**: Navega a `UgrEdanPreviewScreen` para revisión final

### 5.6 Validación de Completitud

```dart
// En el modelo EdanLocalidad
List<String> incompletosPorSeccion({bool exigirAlcalde = false}) {
  final incompletos = <String>[];
  
  if (nombre.isEmpty) incompletos.add('Nombre de localidad');
  if (idTipoEvento == null) incompletos.add('Tipo de evento');
  if (exigirAlcalde && nombreAlcalde.isEmpty) incompletos.add('Alcalde');
  
  // Secciones condicionales
  if (impPoblacion && impactoPoblacion.isEmpty) incompletos.add('Impacto en población');
  if (impSalud && establecimientosSalud.isEmpty) incompletos.add('Impacto en salud');
  // ... etc
  
  return incompletos;
}
```

---

## 6. Flujo de Previsualización y Envío

### 6.1 Navegación desde el Formulario

```dart
void _revisar() {
  final edan = _construirEdan();  // Serializa todos los datos del form
  
  Navigator.push(context, ugrRoute(
    UgrEdanPreviewScreen(
      edan: edan,
      soloLectura: false,      // permite "Confirmar y Enviar"
      sinAlcalde: true,        // el Responsable no asigna alcalde
      cargarResponsableDeCache: true,
    ),
  )).then((confirmado) {
    if (confirmado != null) {
      _marcarEnviada();  // Cambia estado a enviadoUgr
    }
  });
}
```

### 6.2 Confirmación en Preview

En `UgrEdanPreviewScreen`, la rama default (Form Flow) muestra:

```
┌─────────────────────────────────────┐
│ ⚠ Secciones incompletas:           │
│   • Población                       │
│   • Salud                           │
├─────────────────────────────────────┤
│ [Volver y Editar]  [Confirmar y Enviar] │
└─────────────────────────────────────┘
```

El botón "Confirmar y Enviar" está **deshabilitado** cuando hay secciones incompletas.

Al confirmar:
```dart
void _confirmar() {
  edan.estado = 'enviado';
  edan.idEstado = 1;
  Navigator.pop(edan);  // Retorna el EDAN modificado al formulario
}
```

### 6.3 Guardado Final en el Formulario

```dart
void _marcarEnviada() {
  // 1. Cambiar estado
  _edan.estadoLocalidad = UgrLocalidadEstado.enviadoUgr;
  
  // 2. Generar ID local único
  _edan.idLocal = _generarIdLocal();  // Hex timestamp
  
  // 3. Guardar en SQLite
  DatabaseHelper.instance.insertLocalidad(_edan);
  
  // 4. Sync inmediato
  LocalidadSyncService.instance.sincronizar();
  
  // 5. Retornar a la pantalla anterior
  Navigator.pop(context, true);
}
```

---

## 7. Pestaña Mapa (Tab 2)

### 7.1 `RespMapaTab`

**Archivo:** `REA/lib/screens/role_screens/resp/resp_mapa_tab.dart` (~1520 líneas)

#### Arquitectura General

```
RespMapaTab
├── FlutterMap
│   ├── TileLayer (Calle / Satélite)
│   ├── PolygonLayer (GeoJSON municipio)
│   └── MarkerClusterLayerWidget
├── Filtros
│   ├── Date Chips (fechas horizontales)
│   └── Photo Strip (thumbnails)
├── Panel de Info
│   ├── Counter Badge (puntos + fotos)
│   └── Legend (colapsable)
└── Bottom Sheet (detalles al tocar marcador)
```

### 7.2 Extracción de Puntos del Mapa

```dart
void _cargarLocalidades() {
  final localidades = DatabaseHelper.instance.getLocalidades(userId);
  final puntos = <_PuntoMapa>[];
  final vistos = <String>{};  // Para deduplicar
  
  for (final loc in localidades) {
    _extraerPuntosSecciones(loc, puntos, vistos);
  }
  
  setState(() => _puntos = puntos);
}

void _extraerPuntosSecciones(
  EdanLocalidad loc, 
  List<_PuntoMapa> puntos, 
  Set<String> vistos,
) {
  // Salud
  for (final s in loc.establecimientosSalud) {
    if (s.coordenadas?.lat != null) {
      final key = 'salud|${s.nombreEstablecimiento}|${s.comunidad}';
      if (vistos.add(key)) {
        puntos.add(_PuntoMapa(
          lat: s.coordenadas!.lat,
          lon: s.coordenadas!.lon,
          seccion: 'Salud',
          color: AppColors.enviado,
          icon: Icons.local_hospital,
          localidad: loc.nombre,
          fotos: s.fotos,
          datos: {
            'Establecimiento': s.nombreEstablecimiento ?? '',
            'Comunidad': s.comunidad ?? '',
            'Nivel': s.nivelAtencion ?? '',
          },
        ));
      }
    }
  }
  
  // Vías
  for (final v in loc.danosViales) {
    if (v.coordenadas?.lat != null) {
      final key = 'vias|${v.viaPuente}|${v.tramo}';
      if (vistos.add(key)) {
        puntos.add(_PuntoMapa(
          lat: v.coordenadas!.lat,
          lon: v.coordenadas!.lon,
          seccion: 'Vías/Puentes',
          color: AppColors.primary,
          icon: Icons.route,
          localidad: loc.nombre,
          fotos: v.fotos,
        ));
      }
    }
  }
  
  // ... repetir para las 8 secciones
}
```

### 7.3 Interacciones del Mapa

| Interacción | Resultado |
|-------------|-----------|
| **Tocar marcador** | Abre `_PuntoSheet` (bottom sheet con detalles) |
| **Tocar foto en sheet** | Visor fullscreen con `InteractiveViewer` (zoom 0.5x-4x) |
| **Tocar chip de fecha** | Filtra puntos por fecha del evento |
| **Tocar thumbnail en photo strip** | Centra mapa en ese punto y abre sheet |
| **Toggle calle/satélite** | Cambia capa de tiles |
| **Tocar leyenda** | Colapsa/expande |

### 7.4 Modelo de Punto

```dart
class _PuntoMapa {
  double lat, lon;
  String localidad, seccion, fechaKey;
  IconData icon;
  Color color;
  List<EdanFoto> fotos;
  String? servidor, usuarioNombre, tipoEvento;
  Map<String, String> datos;  // Campos específicos de la sección
}
```

---

## 8. Arquitectura de Sincronización

### 8.1 `LocalidadSyncService`

**Archivo:** `REA/lib/services/localidad_sync_service.dart` (~775 líneas)

#### Estado Reactivo

```dart
final pendientes = ValueNotifier<int>(0);
final sincronizando = ValueNotifier<bool>(false);
final sincronizandoMunicipio = ValueNotifier<bool>(false);
```

#### Flujo Principal `sincronizar()`

```
sincronizar()
│
├─ 1. _pullLocalidades(userId, result)
│   ├─ GET /edan/sync/pull?desde={watermark}
│   ├─ Para cada localidad remota:
│   │   ├─ Existe localmente y está sincronizado → merge
│   │   └─ Es nueva → insertar y marcar sincronizado
│   └─ Actualizar lastSyncDate
│
├─ 2. _pushDeletions(result)
│   ├─ Obtener localidades con pendienteEliminacion=true
│   ├─ DELETE /edan/localidades/{id} para cada una
│   └─ Eliminar de SQLite
│
├─ 3. _pushLocalidades(userId, result)
│   ├─ Obtener localidades con sincronizado=0
│   ├─ Serializar a JSON
│   ├─ POST /edan/localidades/sync (batch)
│   └─ Para cada respuesta:
│       ├─ aplicado=true → marcar sincronizado
│       ├─ conflicto=true (LWW) → adoptar versión del servidor
│       ├─ tombstone=true → eliminar de SQLite
│       └─ Error de código → regenerar idLocal y reintentar
│
└─ 4. _pushFotos(userId, result)
    └─ Para cada sección 1:N:
        ├─ salud/establecimientos
        ├─ danos-viales
        ├─ danos-infra-publica
        ├─ unidades-educativas
        ├─ danos-vivienda
        ├─ danos-agricultura
        ├─ danos-pecuarios
        └─ infra-productiva
            └─ Para cada item con foto:
                POST /edan/localidades/{id}/{seccion}/con-foto (multipart)
```

### 8.2 Algoritmo de Merge de Secciones

```dart
List<T> _fusionarSeccion<T>(
  List<T> locales,
  List<T> remotos,
  String Function(T) keyExtractor,
  T Function(T, T) mergeItem,
) {
  final resultado = <T>[];
  final remotosMap = {for (final r in remotos) keyExtractor(r): r};
  
  // Items locales son autoritativos
  for (final local in locales) {
    final key = keyExtractor(local);
    if (remotosMap.containsKey(key)) {
      // Merge: copiar datos del servidor que faltan en local
      resultado.add(mergeItem(local, remotosMap[key]!));
      remotosMap.remove(key);
    } else {
      resultado.add(local);
    }
  }
  
  // Items remanentes del servidor (nuevos)
  resultado.addAll(remotosMap.values);
  
  return resultado;
}
```

**Lógica clave:**
- Los items **locales** son autoritativos para estructura y fotos locales
- Los items del **servidor** se emparejan por clave compuesta (tipo + identificadores)
- Las **fotos del servidor** se copian de vuelta al local solo cuando el local no las tiene
- Los items **"echo"** (creados por el servidor al subir fotos) se descartan

### 8.3 Estrategia de Resolución de Conflictos

| Escenario | Comportamiento |
|-----------|----------------|
| Local modificado, servidor sin cambios | Push local al servidor |
| Servidor modificado, local sin cambios | Pull del servidor |
| Ambos modificados (LWW) | **Servidor gana** (Last-Writer-Wins) |
| Colisión de código | Regenerar `idLocal` (nuevo UUID) y reintentar |
| Servidor eliminó | Tombstone → eliminar de SQLite local |
| Error de red | Incrementar `intentos_sync`, almacenar `ultimo_error` |

---

## 9. Esquema de Base de Datos

### 9.1 `localidades_offline`

| Columna | Tipo | Descripción |
|---------|------|-------------|
| `id_local` | TEXT PK | UUID generado localmente |
| `id_server` | INTEGER | ID asignado por el servidor |
| `id_edan` | INTEGER | FK al EDAN padre (NULL = huérfana) |
| `es_huerfana` | INTEGER | 1=huérfana, 0=consolidada |
| `usuario_id` | INTEGER | FK al usuario propietario |
| `id_tipo_localidad` | INTEGER | FK a catálogo |
| `id_tipo_evento` | INTEGER | FK a catálogo |
| `id_departamento` | INTEGER | FK geográfico |
| `id_provincia` | INTEGER | FK geográfico |
| `id_municipio` | INTEGER | FK geográfico |
| `departamento_nombre` | TEXT | Nombre cacheado (v15+) |
| `provincia_nombre` | TEXT | Nombre cacheado (v15+) |
| `municipio_nombre` | TEXT | Nombre cacheado (v15+) |
| `localidad` | TEXT | Nombre de la localidad |
| `fecha_llenado` | TEXT | ISO8601 |
| `fecha_evento` | TEXT | ISO8601 |
| `hora_evento` | TEXT | |
| `total_poblacion_afectada` | INTEGER | |
| `total_familias_afectadas` | INTEGER | |
| `total_familias_damnificadas` | INTEGER | |
| `imp_poblacion` - `imp_necesidades` | INTEGER | 9 flags de impacto |
| `id_edan_localidad_estado` | INTEGER | FK a estado |
| `estado_localidad` | TEXT | Label de `UgrLocalidadEstado` |
| `datos_json` | TEXT | **Blob JSON completo del modelo EdanLocalidad** |
| `sincronizado` | INTEGER | 0=pendiente, 1=sincronizado |
| `pendiente_eliminacion` | INTEGER | Soft-delete flag |
| `pendiente_actualizacion` | INTEGER | Necesita update flag |
| `fecha_creacion` | TEXT | Timestamp local |
| `fecha_modificacion` | TEXT | Última modificación |
| `intentos_sync` | INTEGER | Contador de reintentos |
| `ultimo_error` | TEXT | Último error de sync |

### 9.2 Tablas de Catálogo Relevantes

| Tabla | PK | Columnas Principales |
|-------|----|--------------------|
| `catalogo_tipo_localidad` | `id_tipo_localidad` | nombre, descripcion, orden |
| `catalogo_tipos_evento` | `id_tipo_evento` | nombre |
| `catalogo_estados` | `id_estado` | nombre, descripcion, orden |
| `catalogo_estados_edan` | `id_estado` | nombre, descripcion, orden |
| `catalogo_grupo_vulnerable` | `id_grupo_vulnerable` | codigo, nombre, descripcion, orden, activo |
| `catalogo_cultivos` | `id_cultivo` | nombre, grupo |
| `catalogo_pecuario_grupos` | `id_pecuario_grupo` | nombre, grupo |
| `catalogo_departamentos` | `id` | codigo_ine, nombre |
| `catalogo_provincias` | `id` | codigo_ine, id_departamento, nombre |
| `catalogo_municipios` | `id` | codigo_ine, id_departamento, id_provincia, nombre |

---

## 10. Endpoints API Relevantes

### 10.1 Autenticación

| Método | Ruta | Propósito |
|--------|------|-----------|
| POST | `/auth/login` | Login |
| POST | `/auth/register` | Registro (id_rol=7) |
| POST | `/auth/cambiar-contrasena` | Cambiar contraseña |

### 10.2 Localidades

| Método | Ruta | Propósito |
|--------|------|-----------|
| GET | `/edan/localidades/mis-resumen?id_usuario=` | Resumen del usuario |
| GET | `/edan/localidades/mis-reportes?id_usuario=&solo_huerfanas=` | Mis reportes |
| GET | `/edan/sync/pull?desde=&limit=` | Pull de sync (V2) |
| POST | `/edan/sync/ack` | Confirmar watermark |
| POST/PUT | `/edan/formularios/completo` | Push del documento completo |
| GET | `/edan/localidades/{id}` | Detalle de localidad |
| DELETE | `/edan/localidades/{id}` | Eliminar localidad |
| PUT | `/edan/localidades/{id}/estado` | Cambiar estado |
| POST | `/edan/localidades/{id}/{seccion}/con-foto` | Subir sección con foto |
| GET | `/edan/localidades/{id}/{seccion}` | Obtener items de sección |

### 10.3 EDANs

| Método | Ruta | Propósito |
|--------|------|-----------|
| GET | `/edan/?id_usuario=&id_municipio=` | Listar EDANs |
| GET | `/edan/{id}` | Detalle de EDAN |
| POST | `/edan/` | Crear EDAN |
| PUT | `/edan/{id}` | Actualizar EDAN |
| DELETE | `/edan/{id}` | Eliminar EDAN |
| POST | `/edan/sync` | Batch sync |
| PUT | `/edan/{id}/estado` | Cambiar estado |

### 10.4 Repositorio de Documentos

| Método | Ruta | Propósito |
|--------|------|-----------|
| GET | `/repositorio/tipos` | Catálogo de tipos |
| GET | `/repositorio/edan/{id}/documentos` | Listar documentos |
| POST | `/repositorio/edan/{id}/documentos` | Subir documento (multipart) |
| GET | `/repositorio/documentos/{id}/descargar` | Descargar documento |
| DELETE | `/repositorio/documentos/{id}` | Eliminar documento |
| GET | `/repositorio/documentos/filtrar?...` | Filtrar documentos |
| GET | `/repositorio/documentos/buscar?q=` | Buscar documentos |

### 10.5 Catálogos Compartidos

| Método | Ruta | Propósito |
|--------|------|-----------|
| GET | `/shared/departamentos` | Departamentos |
| GET | `/shared/provincias?id_departamento=` | Provincias |
| GET | `/shared/municipios?id_provincia=` | Municipios |
| GET | `/shared/municipios/{codigoIne}/geojson` | GeoJSON del municipio |
| GET | `/shared/cultivos` | Catálogo de cultivos |
| GET | `/shared/pecuario` | Catálogo pecuario |
| GET | `/edan/tipo-evento` | Tipos de evento |
| GET | `/edan/grupo-vulnerable` | Grupos vulnerables |
| GET | `/edan/tipo-localidad` | Tipos de localidad |

### 10.6 Usuarios

| Método | Ruta | Propósito |
|--------|------|-----------|
| GET | `/usuarios/?id_municipio=&id_rol=` | Listar usuarios |
| GET | `/usuarios/{id}` | Detalle de usuario |
| POST | `/usuarios/` | Crear usuario |
| PUT | `/usuarios/{id}` | Actualizar usuario |

---

## 11. Manejo Offline

### 11.1 Detección de Conectividad

```dart
class ConnectivityService {
  // Singleton
  static final instance = ConnectivityService._();
  
  bool _isConnected = false;
  bool get isConnected => _isConnected;
  
  Stream<bool> get isConnectedStream => _controller.stream;
  final _controller = StreamController<bool>.broadcast();
  
  Timer? _timer;
  
  Future<void> initialize() async {
    // Verificación inicial
    await _checkConnection();
    
    // Polling cada 30 segundos
    _timer = Timer.periodic(Duration(seconds: 30), (_) => _checkConnection());
  }
  
  Future<void> _checkConnection() async {
    try {
      final result = await Connectivity().checkConnectivity();
      if (result == ConnectivityResult.none) {
        _updateConnection(false);
        return;
      }
      
      // Verificación HTTP HEAD real
      final response = await http.head(
        Uri.parse(ApiConfig.baseUrl),
      ).timeout(Duration(seconds: 5));
      
      _updateConnection(response.statusCode < 400);
    } catch (e) {
      _updateConnection(false);
    }
  }
  
  void _updateConnection(bool connected) {
    if (_isConnected != connected) {
      _isConnected = connected;
      _controller.add(connected);
    }
  }
}
```

### 11.2 Patrón Offline-First

```
┌─────────────────────────────────────────────────────┐
│                   FLUJO OFFLINE-FIRST               │
│                                                     │
│  Usuario crea/edita localidad                       │
│     → SQLite (localidades_offline)                  │
│     → sincronizado=0, pendiente_* flags activos     │
│                                                     │
│  Cuando se detecta conectividad:                    │
│     → LocalidadSyncService.sincronizar()            │
│         → _pullLocalidades (descarga cambios)       │
│         → _pushDeletions (sube eliminaciones)       │
│         → _pushLocalidades (sube cambios)           │
│         → _pushFotos (sube fotos por sección)       │
│                                                     │
│  Resolución de conflictos:                          │
│     - LWW con preservación de headers               │
│     - Merge de secciones 1:N por clave compuesta    │
│     - Server gana en caso de empate                 │
│                                                     │
│  Reintentos:                                        │
│     - intentos_sync incrementado en fallo           │
│     - ultimo_error almacenado para diagnóstico      │
│     - API con retry (hasta 2 reintentos, backoff)   │
└─────────────────────────────────────────────────────┘
```

### 11.3 Persistencia de Borradores

Los borradores se guardan en la tabla `borradores`:

| Columna | Tipo | Descripción |
|---------|------|-------------|
| `id_borrador` | INTEGER PK | ID autoincremental |
| `usuario_id` | INTEGER | FK al usuario |
| `datos_formulario` | TEXT | JSON completo del formulario |
| `imagenes_paths` | TEXT | JSON array de rutas locales |
| `fecha_creacion` | TEXT | Timestamp |
| `fecha_modificacion` | TEXT | Última modificación |

### 11.4 Tracking de Reintentos

```dart
// En cada intento fallido de sync
localidad.intentosSync = (localidad.intentosSync ?? 0) + 1;
localidad.ultimoError = errorMessage;
await DatabaseHelper.instance.updateLocalidad(localidad);

// Si excede 10 reintentos, marcar para revisión
if (localidad.intentosSync! > 10) {
  // Mostrar en UI como error persistente
}
```

---

## 12. Adaptación a Web

### 12.1 Cambios Necesarios

| Componente | Móvil | Web | Acción |
|------------|-------|-----|--------|
| `OpenFilex.open()` | Visor PDF del sistema | No disponible | Usar `url_launcher` o visor embebido |
| `Image.file()` | Archivos locales | No funciona | Usar `Image.network()` siempre |
| `ConnectivityService` | HTTP HEAD a API | CORS puede bloquear | Solo `connectivity_plus` en web |
| `flutter_map` | Touch gestures | Mouse scroll conflict | Configurar `InteractiveFlag` |
| `LocationService` | GPS del dispositivo | No disponible | Deshabilitar o usar geolocation API |
| `ImageService.takePhoto()` | Cámara del dispositivo | No disponible | Usar `file_picker` con `FilePickerPlatform` |
| `getApplicationDocumentsDirectory()` | Directorio local | No existe | Usar `kIsWeb` para branching |

### 12.2 Código: Apertura de PDF en Web

```dart
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';

Future<void> _abrirDocumento(Map<String, dynamic> doc) async {
  final idDoc = doc['id_documento'];
  
  if (kIsWeb) {
    // Web: abrir URL directa del servidor
    final url = Uri.parse(
      '${ApiConfig.baseUrl}/repositorio/documentos/$idDoc/descargar',
    );
    
    // Opción 1: Abrir en nueva pestaña
    await launchUrl(url, mode: LaunchMode.externalApplication);
    
    // Opción 2: Usar visor PDF embebido (requiere implementación custom)
    // Navigator.push(context, MaterialPageRoute(
    //   builder: (_) => PdfViewerScreen(url: url.toString()),
    // ));
  } else {
    // Móvil: cache read-through
    final appDir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${appDir.path}/documentos_edan');
    if (!await cacheDir.exists()) await cacheDir.create(recursive: true);
    
    final file = File('${cacheDir.path}/$idDoc.pdf');
    if (!await file.exists()) {
      final bytes = await ApiService.instance.descargarDocRepositorio(idDoc);
      await file.writeAsBytes(bytes);
    }
    await OpenFilex.open(file.path);
  }
}
```

### 12.3 Código: Imágenes en Web

```dart
Widget _buildFotoWidget(String? ruta, {double width = 80, double height = 80}) {
  if (ruta == null) return SizedBox(width: width, height: height);
  
  if (kIsWeb) {
    // Web: siempre usar Image.network con auth header
    final url = ruta.startsWith('http')
        ? ruta
        : '${ApiConfig.baseUrl}/upload/descargar/$ruta';
    
    return Image.network(
      url,
      width: width,
      height: height,
      fit: BoxFit.cover,
      headers: {
        'Authorization': 'Bearer ${AuthService.instance.currentToken}',
      },
      errorBuilder: (_, __, ___) => Container(
        width: width,
        height: height,
        color: Colors.grey[300],
        child: Icon(Icons.broken_image),
      ),
    );
  } else {
    // Móvil: intentar archivo local primero
    final file = File(ruta);
    if (file.existsSync()) {
      return Image.file(file, width: width, height: height, fit: BoxFit.cover);
    }
    // Fallback a red
    return Image.network(
      '${ApiConfig.baseUrl}/upload/descargar/$ruta',
      width: width,
      height: height,
      fit: BoxFit.cover,
      headers: {'Authorization': 'Bearer ${AuthService.instance.currentToken}'},
    );
  }
}
```

### 12.4 Código: `flutter_map` Configurado para Web

```dart
import 'package:flutter/foundation.dart' show kIsWeb;

FlutterMap(
  mapController: _mapController,
  options: MapOptions(
    center: LatLng(-17.7833, -63.1821),  // Santa Cruz, Bolivia
    zoom: 12,
    interactionOptions: InteractionOptions(
      flags: kIsWeb
          // En web: solo drag + pinchZoom + doubleTapZoom
          // Evitar scroll zoom para no interferir con scroll del navegador
          ? InteractiveFlag.drag | InteractiveFlag.pinchZoom | InteractiveFlag.doubleTapZoom
          // En móvil: todas las interacciones
          : InteractiveFlag.all,
    ),
  ),
  children: [
    TileLayer(
      urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
      subdomains: ['a', 'b', 'c'],
    ),
    MarkerClusterLayerWidget(
      options: MarkerClusterLayerOptions(
        maxClusterRadius: 80,
        maxZoom: 15,
        markers: _buildMarkers(),
        builder: (context, markers) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.purple.withOpacity(0.7),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '${markers.length}',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          );
        },
      ),
    ),
  ],
)
```

### 12.5 Código: Conectividad en Web

```dart
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class ConnectivityService {
  Stream<bool> get isConnectedStream {
    return Connectivity().onConnectivityChanged.map((result) {
      if (kIsWeb) {
        // En web, connectivity_plus solo detecta si hay red
        // No puede verificar el backend por CORS
        // Se asume que si hay red, hay connectivity
        return result != ConnectivityResult.none;
      }
      // En móvil: verificación HTTP HEAD completa
      return _checkHttpConnection();
    });
  }
  
  Future<bool> _checkHttpConnection() async {
    try {
      final response = await http.head(
        Uri.parse(ApiConfig.baseUrl),
      ).timeout(Duration(seconds: 5));
      return response.statusCode < 400;
    } catch (e) {
      return false;
    }
  }
}
```

### 12.6 Código: Geolocalización en Web

```dart
import 'package:flutter/foundation.dart' show kIsWeb;

class LocationService {
  Future<Position?> getCurrentLocation() async {
    if (kIsWeb) {
      // Web: usar Geolocation API del navegador
      // Requiere permiso del usuario
      try {
        // Implementación con dart:html
        // final permission = await window.navigator.geolocation.requestPermission();
        // if (permission == 'granted') {
        //   final position = await window.navigator.geolocation.getCurrentPosition();
        //   return Position(
        //     latitude: position.coords!.latitude!,
        //     longitude: position.coords!.longitude!,
        //     accuracy: position.coords!.accuracy!,
        //   );
        // }
        
        // Por ahora, retornar null en web
        print('Geolocalización no disponible en web');
        return null;
      } catch (e) {
        print('Error de geolocalización web: $e');
        return null;
      }
    }
    
    // Móvil: usar Geolocator
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;
    
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return null;
    }
    
    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: Duration(seconds: 45),
    );
  }
}
```

### 12.7 Código: Cámara en Web

```dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';

class ImageService {
  Future<PlatformFile?> takePhoto() async {
    if (kIsWeb) {
      // Web: usar file_picker para seleccionar imagen
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,  // Necesario para web
      );
      
      if (result != null && result.files.isNotEmpty) {
        return result.files.first;
      }
      return null;
    }
    
    // Móvil: usar ImagePicker
    final picker = ImagePicker();
    final photo = await picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1920,
      maxHeight: 1080,
      imageQuality: 85,
    );
    
    if (photo != null) {
      return PlatformFile(
        name: photo.name,
        path: photo.path,
        size: await photo.length(),
      );
    }
    return null;
  }
}
```

### 12.8 Estrategia de URLs para Web

```dart
// lib/config/url_strategy.dart
import 'package:flutter_web_plugins/url_strategy.dart';

void configureAppUrlStrategy() {
  // Elimina el # de las URLs (PathUrlStrategy)
  setUrlStrategy(PathUrlStrategy());
}
```

En `main.dart`:
```dart
import 'package:flutter/foundation.dart' show kIsWeb;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  if (kIsWeb) {
    configureAppUrlStrategy();
  }
  
  runApp(MyApp());
}
```

---

## 13. Referencia de Archivos Clave

| Archivo | Líneas | Propósito |
|---------|--------|-----------|
| `resp_screen.dart` | ~414 | Scaffold principal con 5 tabs |
| `resp_dashboard_tab.dart` | ~826 | Dashboard con indicadores y actividad |
| `resp_edan_localidad_tab.dart` | ~666 | Lista de reportes con filtros |
| `resp_edan_form_screen.dart` | ~2932 | Formulario EDAN completo (12 secciones) |
| `resp_mapa_tab.dart` | ~1520 | Mapa interactivo con clustering |
| `resp_guia_tab.dart` | ~400 | Guía de ayuda estática |
| `ugr_edan_preview_screen.dart` | ~1200 | Previsualización compartida UGR/RESP |
| `ugr_edan_localidad_preview_screen.dart` | ~800 | Previsualización con Aprobar/Rechazar |
| `localidad_sync_service.dart` | ~775 | Sincronización de localidades |
| `api_service.dart` | ~1281 | Todos los endpoints API |
| `database_helper.dart` | ~1621 | SQLite v17, todas las tablas |
| `edan.dart` | ~2539 | Modelos Edan y EdanLocalidad |
| `connectivity_service.dart` | ~82 | Detección de conectividad |
| `connectivity_provider.dart` | ~28 | ChangeNotifier para widget tree |
