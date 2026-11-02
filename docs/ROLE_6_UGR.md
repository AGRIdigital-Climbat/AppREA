# Rol 6 — Unidad de Gestión de Recurso (UGR)

> **Nota de vigencia (2026-10-19).** El envío de localidades ya no usa
> `/edan/localidades/{id}/documento` (ruta eliminada). Usa
> `POST/PUT /edan/formularios/completo`. El mapa actualizado pantalla → API
> está en [`MAPA_APIS_WEB_EDAN.md`](./MAPA_APIS_WEB_EDAN.md).

## 1. Resumen del Rol

La **Unidad de Gestión de Recurso (UGR)** es el rol intermedio en la cadena EDAN. Sus responsabilidades principales son:

- **Recibir** reportes de localidades enviados por el Responsable Local (Rol 7).
- **Revisar y contrastar** la información de cada localidad.
- **Aprobar o rechazar** localidades individualmente.
- **Consolidar** localidades aprobadas del mismo tipo de evento en un EDAN consolidado.
- **Asignar alcalde** al EDAN consolidado.
- **Adjuntar documentos** de soporte (PDFs).
- **Enviar** el EDAN consolidado al servidor.

El UGR opera sobre la pestaña **"Localidades"** y **"EDAN"** de `UgrScreen`, y comparte la pestaña de **"Mapa"** con el rol RESP.

---

## 2. Arquitectura de Pantallas

### 2.1 `UgrScreen` — Scaffold Principal

**Archivo:** `REA/lib/screens/role_screens/ugr_screen.dart`

```
UgrScreen (StatefulWidget)
├── AppBar (título + botón sync con badge)
├── IndexedStack (5 tabs)
│   ├── [0] UgrLocalidadesTab    — "Localidades"
│   ├── [1] UgrEdanTab           — "EDAN" (2 sub-pestañas)
│   ├── [2] RespMapaTab           — "Mapa"
│   ├── [3] UgrGuiaTab           — "Guía"
│   └── [4] PerfilTab            — "Perfil"
├── FABs (solo en tab 0)
│   ├── AsistenteIaFab           — siempre visible
│   ├── Consolidar FAB (layers)  — condicional
│   └── Crear EDAN FAB (add)     — siempre visible
└── BottomNavigationBar (5 ítems)
```

**Estado:**
- `_selectedIndex` — pestaña actual (`IndexedStack`)
- `_isProfileEditing` — resetea al cambiar de pestaña
- `_wasOnline` — detecta transiciones online→offline para auto-sync
- `_connectivity` — listener de `ConnectivityProvider`

**Sincronización automática:**
- Al iniciar la app → `EdanSyncService.instance.recargarPendientes()`
- Al reanudar la app (app resume) → recarga pendientes
- Al cambiar de pestaña → recarga pendientes
- Al restaurar conectividad → `_sincronizar(auto: true)`
- Botón sync en AppBar → `_sincronizar(auto: false)`

### 2.2 Navegación `onNavigateToEdan`

El callback `onNavigateToEdan` se pasa a `UgrLocalidadesTab` y ejecuta:
```dart
onNavigateToEdan: () => setState(() => _selectedIndex = 1)
```
Esto fuerza el cambio a la pestaña EDAN después de una consolidación exitosa.

---

## 3. Pestaña Localidades (Tab 0)

### 3.1 `UgrLocalidadesTab`

**Archivo:** `REA/lib/screens/role_screens/ugr/ugr_localidades_tab.dart`

#### Variables de Estado Principales

| Variable | Tipo | Propósito |
|----------|------|-----------|
| `_localidades` | `List<EdanLocalidad>` | Todas las localidades del municipio |
| `_resumen` | `Map<String, dynamic>?` | Conteos resumen (total, huérfanas, consolidadas) |
| `_cargando` | `bool` | Estado de carga |
| `_error` | `String?` | Mensaje de error |
| `_query` | `String` | Texto de búsqueda |
| `_modoConsolidacion` | `bool` | Modo consolidación activo |
| `_seleccionadas` | `Set<int>` | IDs seleccionados (`idServer`) |
| `_vistaActual` | `_VistaLocalidades` | Enum: `sinConsolidar` o `consolidadas` |

#### Vista Toggle

```dart
enum _VistaLocalidades { sinConsolidar, consolidadas }
```

- **`sinConsolidar`**: localidades donde `idEdan == null || idEdan == 0` (huérfanas)
- **`consolidadas`**: localidades donde `idEdan != null && idEdan > 0` (asignadas a un EDAN)

El toggle se cambia tocando los chips de resumen en la parte superior.

#### Filtrado (`_filtradas`)

1. Filtra por `_vistaActual` (huérfanas vs consolidadas)
2. Aplica búsqueda por texto en `nombre`, `tipoEventoNombre`, `usuario.nombre`
3. Ordena por `fechaModificacion` descendente (más recientes primero)

#### `mostrarFabConsolidar`

Retorna `true` cuando:
- NO está en modo consolidación
- La vista es `sinConsolidar`
- Existen localidades con `idEdan == null || idEdan == 0`

### 3.2 Tarjetas de Localidad (`_LocalidadCard`)

Cada tarjeta muestra diferentes acciones según el estado:

| Estado | Acciones Visibles |
|--------|-------------------|
| `enRevisionUgr` | **Aprobar** (verde) / **Rechazar** (rojo) |
| `borrador` + `esMia` | **Editar** / **Eliminar** |
| Modo consolidación (aprobada + huérfana) | **Checkbox** de selección |

---

## 4. Flujo Aprobar / Rechazar

### 4.1 Transición Automática

Cuando el UGR toca una localidad con estado `enviadoUgr`:

```dart
// En _verDetalle(localidad)
if (localidad.estadoLocalidad == UgrLocalidadEstado.enviadoUgr) {
  await ApiService.instance.cambiarEstadoLocalidad(
    localidad.idServer!, 
    UgrLocalidadEstado.enRevisionUgr.id,
  );
  localidad.estadoLocalidad = UgrLocalidadEstado.enRevisionUgr;
}
```

Esto cambia automáticamente el estado a `enRevisionUgr` la primera vez que el UGR abre la localidad.

### 4.2 Pantalla de Previsualización

**Archivo:** `REA/lib/screens/role_screens/ugr/ugr_edan_localidad_preview_screen.dart`

```dart
UgrEdanLocalidadPreviewScreen(
  localidad: localidad,
  soloLectura: false,  // permite actuar
)
```

**Propiedad clave: `_puedeActuar`**
```dart
bool get _puedeActuar =>
    localidad.estadoLocalidad == UgrLocalidadEstado.enRevisionUgr &&
    localidad.idServer != null;
```

Los botones solo se muestran cuando `_puedeActuar` es `true`.

### 4.3 Diálogo de Confirmación

```dart
void _mostrarConfirmacion(String accion, Color color, VoidCallback onPressed) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(
        accion == 'Aprobar' ? Icons.check_circle : Icons.cancel,
        color: color,
        size: 48,
      ),
      title: Text('$accion localidad'),
      content: Text('¿Estás seguro de que deseas $accion esta localidad?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancelar')),
        TextButton(
          onPressed: () { Navigator.pop(ctx); onPressed(); },
          child: Text(accion),
          style: TextButton.styleFrom(foregroundColor: color),
        ),
      ],
    ),
  );
}
```

### 4.4 Flujo de Aprobación

```
_tap localidad → _verDetalle()
  │
  ├─ estado == enviadoUgr → auto-cambia a enRevisionUgr (API)
  │
  └─ navega a UgrEdanLocalidadPreviewScreen
       │
       ├─ "Aprobar" → _mostrarConfirmacion('Aprobar', ...)
       │   └─ _aprobar()
       │       ├─ connectivity check
       │       ├─ ApiService.cambiarEstadoLocalidad(idServer, aprobadoUgr.id)
       │       ├─ localidad.estadoLocalidad = aprobadoUgr (in-memory)
       │       ├─ snackbar "Localidad aprobada"
       │       └─ Navigator.pop(true) → recarga datos
       │
       └─ "Rechazar" → _mostrarConfirmacion('Rechazar', ...)
           └─ _rechazar()
               ├─ connectivity check
               ├─ ApiService.cambiarEstadoLocalidad(idServer, rechazadoUgr.id)
               ├─ localidad.estadoLocalidad = rechazadoUgr (in-memory)
               ├─ snackbar "Localidad rechazada"
               └─ Navigator.pop(true) → recarga datos
```

### 4.5 Máquina de Estados (`UgrLocalidadEstado`)

| ID | Estado | Label | Color | Descripción |
|----|--------|-------|-------|-------------|
| 1 | `borrador` | Borrador | `pending` (naranja) | Siendo creado localmente |
| 2 | `enviadoUgr` | Enviado UGR | `primary` (azul) | Enviado por el Responsable |
| 6 | `enRevisionUgr` | En revisión UGR | `pending` (naranja) | UGR lo tiene abierto |
| 3 | `aprobadoUgr` | Aprobado UGR | `aprobado` (verde) | Validado y aprobado |
| 4 | `rechazadoUgr` | Rechazado UGR | `rechazado` (rojo) | Rechazado con observaciones |
| 5 | `aprobadoAjuste` | Aprobado con ajuste | `completed` (teal) | Aprobado con correcciones |

---

## 5. Flujo de Consolidación

### 5.1 Activación del Modo

```
_usuario toca FAB "layers" → _activarModoConsolidacion()
  │
  ├─ filtra localidades aprobadas + huérfanas
  ├─ si no hay → snackbar "No hay localidades aprobadas sin consolidar"
  └─ si hay → _modoConsolidacion = true, _seleccionadas.clear()
```

### 5.2 Selección de Localidades

```dart
void _toggleSeleccion(int idServer) {
  // Solo localidades aprobadas y huérfanas son seleccionables
  if (!esAprobada || !esHuerfana) return;
  
  if (_seleccionadas.isEmpty) {
    _seleccionadas.add(idServer);
  } else {
    // Restricción: mismo tipo de evento
    final primerTipo = _localidades.firstWhere((l) => l.idServer == _seleccionadas.first).idTipoEvento;
    final actualTipo = localidad.idTipoEvento;
    
    if (primerTipo != actualTipo) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Solo puede consolidar localidades del mismo tipo de evento')),
      );
      return;
    }
    _seleccionadas.add(idServer);
  }
}
```

**Restricción clave:** Solo se pueden consolidar localidades del **mismo tipo de evento**.

### 5.3 Vista Previa del EDAN

```dart
void _vistaPreviaConsolidacion() {
  final seleccionadasList = _localidades
      .where((l) => _seleccionadas.contains(l.idServer))
      .toList();
  
  // Calcular totales agregados
  final totalPoblacion = seleccionadasList.fold(0, (s, l) => s + l.totalPoblacionAfectada);
  final totalFamilias = seleccionadasList.fold(0, (s, l) => s + l.totalFamiliasAfectadas);
  final totalDamnificadas = seleccionadasList.fold(0, (s, l) => s + l.totalFamiliasDamnificadas);
  
  // Construir EDAN sintético
  final edanSintetico = Edan(
    idDepartamento: primeraLocalidad.idDepartamento,
    idProvincia: primeraLocalidad.idProvincia,
    idMunicipio: primeraLocalidad.idMunicipio,
    idTipoEvento: primeraLocalidad.idTipoEvento,
    estado: 'aprobado ugr',
    idEstado: 3,
    esBorrador: false,
    localidades: seleccionadasList,
    totalPoblacionAfectada: totalPoblacion,
    totalFamiliasAfectadas: totalFamilias,
    totalFamiliasDamnificadas: totalDamnificadas,
  );
  
  Navigator.push(context, ugrRoute(
    UgrEdanPreviewScreen(
      edan: edanSintetico,
      soloLectura: true,
      esConsolidado: true,
    ),
  )).then((confirmado) {
    if (confirmado == true) _consolidar(seleccionadasList);
  });
}
```

### 5.4 Confirmación y API

```dart
Future<void> _consolidar(List<EdanLocalidad> localidades) async {
  if (!await ConnectivityService.instance.isConnected) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Se requiere conexión a internet para consolidar')),
    );
    return;
  }
  
  final idTipoEvento = localidades.first.idTipoEvento!;
  final localidadIds = localidades.map((l) => l.idServer!).toList();
  
  final resultado = await ApiService.instance.consolidar(
    idMunicipio, idTipoEvento, localidadIds,
  );
  
  if (resultado != null) {
    // Parsear EDAN del servidor
    final edan = Edan.fromJson(resultado);
    
    // Guardar en SQLite
    await DatabaseHelper.instance.insertEdan(edan);
    await DatabaseHelper.instance.markEdanAsSynced(edan.idLocal!);
    
    // Actualizar sync state
    await EdanSyncService.instance.recargarEdansMunicipio();
    
    // Feedback
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('EDAN consolidado correctamente')),
    );
    
    // Navegar a pestaña EDAN
    _modoConsolidacion = false;
    await _cargarDatos();
    widget.onConsolidado?.call();
    widget.onNavigateToEdan?.call();  // ← Cambia a tab 1
  }
}
```

### 5.5 Barra de Consolidación

La barra se posiciona **debajo del AppBar** (no en el bottom) para evitar overlap con FABs:

```
┌─────────────────────────────┐
│ AppBar                      │
├─────────────────────────────┤
│ ▌ Barra de consolidación    │  ← _buildConsolidacionBar()
│  "3 seleccionados" [Vista]  │
├─────────────────────────────┤
│                             │
│   Lista de localidades      │  ← Expanded (se adapta)
│                             │
└─────────────────────────────┘
```

---

## 6. Pestaña EDAN (Tab 1)

### 6.1 `UgrEdanTab`

**Archivo:** `REA/lib/screens/role_screens/ugr/ugr_edan_tab.dart`

#### Sub-pestañas

```dart
TabBar(
  controller: _tabController,
  tabs: [
    Tab(text: 'EDANs'),
    Tab(text: 'Recursos'),
  ],
)
```

| Sub-pestaña | Widget | Contenido |
|-------------|--------|-----------|
| EDANs | `_buildEdanTabContent()` | Lista de EDANs consolidados del municipio |
| Recursos | `UgrRecursoTab` | Repositorio de documentos PDF |

#### Helper `_esBorrador()`

```dart
static bool _esBorrador(Edan e) {
  final estLower = e.estado.trim().toLowerCase();
  return estLower == 'borrador' || (estLower.isEmpty && e.idEstado == 1);
}
```

Este helper determina si un EDAN es editable (solo los borradores).

### 6.2 Carga de EDANs

- **Online:** `ApiService.instance.listarEdansPorMunicipio(municipioId)`
- **Offline:** `DatabaseHelper.instance.getEdansByMunicipio(municipioId)`

También se recarga cuando `sincronizandoMunicipio` pasa de `true` a `false`.

### 6.3 Navegación a Detalle

```dart
void _verDetalleEdan(Map<String, dynamic> edan) async {
  final idEdan = edan['id_edan'];
  
  // Offline: cargar de SQLite
  // Online: ApiService.instance.getEdanById(idEdan)
  
  Navigator.push(context, ugrRoute(
    UgrEdanPreviewScreen(
      edan: edanModel,
      soloLectura: !_esBorrador(edanModel),  // solo borradores son editables
      esConsolidado: true,
    ),
  ));
}
```

---

## 7. Pantalla Previsualización EDAN

### 7.1 `UgrEdanPreviewScreen`

**Archivo:** `REA/lib/screens/role_screens/ugr/ugr_edan_preview_screen.dart`

#### Parámetros del Constructor

| Parámetro | Default | Propósito |
|-----------|---------|-----------|
| `edan` | requerido | Modelo EDAN a mostrar |
| `soloLectura` | `false` | Sin edición/confirmación |
| `sinAlcalde` | `false` | Oculta campo de alcalde |
| `cargarResponsableDeCache` | `false` | Cargar responsable de caché |
| `esConsolidado` | `false` | Es un EDAN consolidado |

### 7.2 Lógica del Bottom Bar (3 Ramas)

```
                    soloLectura?
                   /            \
                 SÍ              NO
                /                  \
    esConsolidado && idEdan==null?   esConsolidado?
       /            \                  /          \
     SÍ              NO              SÍ            NO
      |               |               |             |
  "Consolidar"    "Cerrar"      "Deshacer EDAN"   Form Flow
   (verde)        (primario)    (rojo outline)    (Volver + Confirmar)
```

#### Rama A: Consolidar

```dart
// soloLectura && esConsolidado && edan.idEdan == null
ElevatedButton(
  style: ElevatedButton.styleFrom(backgroundColor: AppColors.aprobado),
  onPressed: _confirmarConsolidacion,
  child: Text('Consolidar'),
)
```

`_confirmarConsolidacion()` muestra un `AlertDialog`:
```
"¿Confirmar la consolidación de las localidades seleccionadas en un EDAN?"
[Cancelar] [Consolidar]
```

Al confirmar: `Navigator.of(context).pop(true)` → el padre (`UgrLocalidadesTab`) ejecuta `_consolidar()`.

#### Rama B: Cerrar

```dart
// soloLectura (pero NO el caso de consolidación)
ElevatedButton(
  onPressed: () => Navigator.of(context).pop(),
  child: Text('Cerrar'),
)
```

#### Rama C: Deshacer EDAN

```dart
// !soloLectura && esConsolidado
// Solo si el EDAN tiene idEdan y está en estado borrador/enviado
OutlineButton(
  style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
  onPressed: _deshacerEdan,
  child: Text('Deshacer EDAN'),
)
```

`_deshacerEdan()`:
1. Diálogo de confirmación advirtiendo que las localidades serán liberadas
2. `ApiService.instance.deshacerEdan(edanId)` o marcado para eliminación offline
3. Las localidades vuelven a estado huérfano

#### Rama D: Formulario (Default)

Muestra dos botones:
- **"Volver y Editar"** — `pop()` sin retorno
- **"Confirmar y Enviar"** — deshabilitado si hay secciones incompletas; al habilitarse:
  ```dart
  edan.estado = 'enviado';
  edan.idEstado = 1;
  Navigator.pop(edan);
  ```

### 7.3 Secciones Visibles

Se calculan dinámicamente según los flags de impacto:

```dart
seccionesVisibles = ['01', '13'];  // siempre visibles
if (impPoblacion) seccionesVisibles.add('02');
if (impSalud) seccionesVisibles.add('03');
if (impInfraestructura) seccionesVisibles.add('04');
if (impServicios) seccionesVisibles.add('05');
if (impEducacion) seccionesVisibles.add('06');
if (impVivienda) seccionesVisibles.add('07');
if (impAgropecuario) seccionesVisibles.add('08');
if (impProteccion) seccionesVisibles.add('09');
if (impNecesidades) seccionesVisibles.add('10');
```

### 7.4 Documentos Vinculados

**Sección:** `_buildDocumentosVinculados()`

- Carga documentos al iniciar: `ApiService.instance.listarDocumentosEdan(idEdan)`
- Cada documento muestra: ícono PDF, nombre, tipo, fecha
- Acciones por documento:
  - **Ver** — descarga PDF a caché y abre con visor del sistema
  - **Descargar** — guarda en directorio de documentos
  - **Eliminar** — solo cuando `!soloLectura` (AlertDialog de confirmación)
- Botón **"Subir PDF"** → navega a `UgrRecursoUploadScreen`

### 7.5 Asignación de Alcalde

**Sección:** `_campoAlcaldeInline()`

Flujo de un toque:
```
_tap en alcalde card
  │
  └─ _asignarAlcalde(Usuario u)
      ├─ edan.idUsuarioAlcalde = u.idUsuario
      ├─ edan.nombreAlcalde = u.nombre
      ├─ edan.fonoAlcalde = u.celular
      └─ _guardarAlcalde()
          ├─ ApiService.instance.updateEdan(edanId, {alcalde data})
          └─ snackbar "Alcalde asignado"
```

**Edición:** botón lápiz → `CrearUsuarioScreen(usuario: existingUsuario)` → `updateUsuario` API → retorna `Usuario` actualizado.

---

## 8. Subida de Documentos

### 8.1 `UgrRecursoUploadScreen`

**Archivo:** `REA/lib/screens/role_screens/ugr/ugr_recurso_upload_screen.dart`

#### Campos del Formulario

| Campo | Tipo | Validación |
|-------|------|------------|
| EDAN (banner) | Display only | `edan.codigoEdan` |
| Archivo PDF | `File?` | Requerido; solo PDF (`FileType.custom`) |
| Nombre del documento | `TextEditingController` | Requerido (no vacío) |
| Tipo de documento | `DropdownButtonFormField<int>` | Requerido |
| Observaciones | `TextEditingController` | Opcional, 3 líneas |

#### Carga de Tipos de Documento

```dart
Future<void> _cargarTiposDocumento() async {
  try {
    // Intento online
    final tipos = await ApiService.instance.listarTiposRepositorio();
    _tiposDocumento = tipos;
  } catch (e) {
    // Fallback offline
    _tiposDocumento = await DatabaseHelper.instance.getTiposRepositorioLocal();
  }
}
```

### 8.2 Flujo de Subida

```dart
Future<void> _subirDocumento() async {
  if (!_formKey.currentState!.validate()) return;
  if (_selectedFile == null) { /* error */ return; }
  if (_selectedTipoId == null) { /* error */ return; }
  
  if (!await ConnectivityService.instance.isConnected) {
    /* "Sin conexión" snackbar */ return;
  }
  
  final resultado = await ApiService.instance.subirDocumentoEdan(
    idEdan: widget.edan.idEdan!,
    filePath: _selectedFile!.path,
    idTipoDocumento: _selectedTipoId!,
    nombreDocumento: _nombreController.text,
    fechaDocumento: DateFormat('yyyy-MM-dd').format(DateTime.now()),  // fecha del sistema
    idDepartamento: widget.edan.idDepartamento!,
    idProvincia: widget.edan.idProvincia!,
    idMunicipio: widget.edan.idMunicipio!,
    observaciones: _observacionesController.text.isEmpty 
        ? null 
        : _observacionesController.text,
  );
  
  if (resultado != null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Documento subido correctamente')),
    );
    Navigator.pop(context, true);  // refresca lista en padre
  }
}
```

---

## 9. Cache de PDF (Read-Through)

### 9.1 Flujo en `UgrRecursoTab`

```dart
Future<void> _abrirDocumento(Map<String, dynamic> doc) async {
  final idDoc = doc['id_documento'];
  
  // Directorio de caché persistente
  final appDir = await getApplicationDocumentsDirectory();
  final cacheDir = Directory('${appDir.path}/documentos_edan');
  if (!await cacheDir.exists()) await cacheDir.create(recursive: true);
  
  final file = File('${cacheDir.path}/$idDoc.pdf');
  
  if (!await file.exists()) {
    // Primera vez: descargar
    final bytes = await ApiService.instance.descargarDocRepositorio(idDoc);
    await file.writeAsBytes(bytes);
  }
  
  // Abrir con visor del sistema
  await OpenFilex.open(file.path);
}
```

**Comportamiento:**
- Primera apertura: descarga de la API, guarda en `getApplicationDocumentsDirectory()/documentos_edan/{id}.pdf`
- Aperturas siguientes: lee del caché local (sin descarga)
- El caché es **persistente** (sobrevive reinicios de app)

---

## 10. Pestaña Mapa

### 10.1 `RespMapaTab` (Compartido con RESP)

**Archivo:** `REA/lib/screens/role_screens/resp/resp_mapa_tab.dart`

#### Arquitectura del Mapa

```
RespMapaTab
├── FlutterMap (MapController)
│   ├── TileLayer (Street: CartoDB Voyager / Satellite: ArcGIS)
│   ├── PolygonLayer (límites del municipio GeoJSON)
│   └── MarkerClusterLayerWidget (maxClusterRadius: 80, maxZoom: 15)
├── Bottom Date Filter (chips horizontales)
├── Photo Strip (thumbnails de puntos con fotos)
├── Legend (colapsable, 8 tipos de sección)
└── Counter Badge (puntos + fotos GPS)
```

#### Capas de Tiles

| Modo | Proveedor | URL |
|------|-----------|-----|
| Calle | CartoDB Voyager | `https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png` |
| Satélite | ArcGIS World Imagery | `https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}` |

#### Codificación por Sección

| Sección | Color | Ícono |
|---------|-------|-------|
| Salud | `AppColors.enviado` | `Icons.local_hospital` |
| Vías/puentes | `AppColors.primary` | `Icons.route` |
| Infraestructura pública | `AppColors.pending` | `Icons.account_balance` |
| Educación | `AppColors.inProgress` | `Icons.school` |
| Viviendas | `AppColors.rechazado` | `Icons.home` |
| Agricultura | `AppColors.aprobado` | `Icons.agriculture` |
| Pecuario | `AppColors.secondary` | `Icons.pets` |
| Infra productiva | `AppColors.cerrado` | `Icons.factory` |

#### Extracción de Puntos

```dart
void _cargarLocalidades() {
  // Para cada localidad
  for (final localidad in localidades) {
    // Iterar todas las secciones 1:N
    for (final salud in localidad.establecimientosSalud) {
      if (salud.coordenadas?.lat != null) {
        _puntos.add(_PuntoMapa(
          lat: salud.coordenadas!.lat,
          lon: salud.coordenadas!.lon,
          seccion: 'Salud',
          color: AppColors.enviado,
          icon: Icons.local_hospital,
          fotos: salud.fotos,
        ));
      }
    }
    // ... repetir para danosViales, danosInfraPublica, etc.
  }
}
```

---

## 11. Arquitectura de Sincronización

### 11.1 `EdanSyncService`

**Archivo:** `REA/lib/services/edan_sync_service.dart`

#### Flujo `sincronizar()`

```
1. _pullEdans(userId, result)
   ├─ GET /edan/sync/pull?fecha_desde={lastSync}
   ├─ Para cada EDAN remoto:
   │   ├─ Existe localmente y está sincronizado → actualizar
   │   └─ Es nuevo → insertar y marcar sincronizado
   └─ Actualizar timestamp de última sync
   
2. _pushDeletions(result)
   ├─ Obtener EDANs con pendienteEliminacion=true
   ├─ DELETE /edan/{id} para cada uno
   └─ Eliminar de SQLite
   
3. _pushEdans(userId, result)
   ├─ Obtener EDANs con sincronizado=0
   ├─ Serializar a JSON
   ├─ POST /edan/sync (batch)
   └─ Para cada respuesta:
       ├─ aplicado=true → marcar sincronizado con id_devuelto
       ├─ Error de código → regenerar codigoEdan y reintentar
       └─ Otro error → incrementar intentos_sync
```

#### Notificadores Reactivos

```dart
final pendientes = ValueNotifier<int>(0);
final sincronizando = ValueNotifier<bool>(false);
final sincronizandoMunicipio = ValueNotifier<bool>(false);
```

### 11.2 Resolución de Conflictos

| Entidad | Estrategia |
|---------|-----------|
| Reportes (legacy) | Last-Write-Wins por respuesta del servidor |
| EDANs | Batch sync con regeneración de código en colisión |
| Localidades | LWW con preservación de header + merge de secciones 1:N |
| Fotos | Subida diferida después del sync del registro padre |

---

## 12. Esquema de Base de Datos

### 12.1 Tablas Relevantes

#### `edans_offline` (SQLite v8+)

| Columna | Tipo | Descripción |
|---------|------|-------------|
| `id_local` | INTEGER PK | ID local autoincremental |
| `id_server` | INTEGER | ID del servidor |
| `id_edan` | INTEGER | ID del EDAN en servidor |
| `codigo_edan` | TEXT | Código generado `INE/AÑO/NNN` |
| `municipio_id` | INTEGER | FK al municipio |
| `estado_edan` | TEXT | Estado textual |
| `id_estado` | INTEGER | FK a catálogo |
| `datos_json` | TEXT | **Blob JSON completo del modelo Edan** |
| `sincronizado` | INTEGER | 0=no, 1=sí |
| `pendiente_eliminacion` | INTEGER | Soft-delete flag |
| `es_borrador` | INTEGER | Flag de borrador |
| `intentos_sync` | INTEGER | Contador de reintentos |

#### `localidades_offline` (SQLite v11+)

| Columna | Tipo | Descripción |
|---------|------|-------------|
| `id_local` | TEXT PK | UUID local |
| `id_server` | INTEGER | ID del servidor |
| `id_edan` | INTEGER | FK al EDAN padre (null = huérfana) |
| `es_huerfana` | INTEGER | 1=huérfana, 0=consolidada |
| `id_tipo_evento` | INTEGER | FK tipo de evento |
| `estado_localidad` | TEXT | Label de `UgrLocalidadEstado` |
| `datos_json` | TEXT | **Blob JSON completo del modelo EdanLocalidad** |
| `sincronizado` | INTEGER | 0=no, 1=sí |

#### `catalogo_tipos_repositorio` (SQLite v17)

| Columna | Tipo | Descripción |
|---------|------|-------------|
| `id_tipo_documento` | INTEGER PK | ID del tipo |
| `codigo` | TEXT | Código abreviado |
| `nombre` | TEXT | Nombre del tipo |
| `descripcion` | TEXT | Descripción |
| `orden` | INTEGER | Orden de visualización |
| `activo` | INTEGER | 1=activo |
| `extensiones_permitidas` | TEXT | PDF, DOC, etc. |
| `tamano_maximo_bytes` | INTEGER | Default 50MB |

---

## 13. Adaptación a Web

### 13.1 Problemas Conocidos

| Problema | Causa | Solución |
|----------|-------|----------|
| `OpenFilex.open()` no funciona | No hay visor PDF del sistema en web | Usar `dart:html` o `url_launcher` con URL del PDF |
| `flutter_map` gestos | Conflicto con scroll del navegador | Configurar `InteractiveFlag` apropiado |
| `getApplicationDocumentsDirectory()` | No existe en web | Usar `kIsWeb` para_branching |
| `ConnectivityService` HTTP HEAD | CORS puede bloquear | Usar solo `connectivity_plus` en web |
| `Image.file()` | No funciona en web | Usar `Image.network()` con URL del servidor |

### 13.2 Código de Ejemplo: Apertura de PDF en Web

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
    final token = await AuthService.instance.currentToken;
    
    // Usar un enlace temporal con headers de auth
    // (o implementar proxy en el backend para evitar CORS)
    await launchUrl(url, mode: LaunchMode.externalApplication);
  } else {
    // Móvil: cache read-through existente
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

### 13.3 Código de Ejemplo: `flutter_map` Configurado para Web

```dart
FlutterMap(
  mapController: _mapController,
  options: MapOptions(
    center: LatLng(lat, lon),
    zoom: 12,
    // En web, deshabilitar zoom por scroll para no interferir
    interactionOptions: InteractionOptions(
      flags: kIsWeb
          ? InteractiveFlag.drag | InteractiveFlag.pinchZoom | InteractiveFlag.doubleTapZoom
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
        // ... resto de configuración
      ),
    ),
  ],
)
```

### 13.4 Código de Ejemplo: Conectividad en Web

```dart
import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  Stream<bool> get isConnectedStream {
    return Connectivity().onConnectivityChanged.map((result) {
      if (kIsWeb) {
        // En web, connectivity_plus solo detecta si hay red
        // No puede verificar el backend por CORS
        return result != ConnectivityResult.none;
      }
      // En móvil: verificación HTTP HEAD completa
      return _checkHttpConnection();
    });
  }
}
```

### 13.5 Código de Ejemplo: Imágenes en Web

```dart
Widget _buildFotoWidget(String? ruta, {double width = 80, double height = 80}) {
  if (ruta == null) return SizedBox(width: width, height: height);
  
  if (kIsWeb) {
    // Web: siempre usar Image.network
    return Image.network(
      ruta.startsWith('http') 
          ? ruta 
          : '${ApiConfig.baseUrl}/upload/descargar/$ruta',
      width: width,
      height: height,
      fit: BoxFit.cover,
      headers: {
        'Authorization': 'Bearer ${AuthService.instance.currentToken}',
      },
      errorBuilder: (_, __, ___) => Icon(Icons.broken_image),
    );
  } else {
    // Móvil: intentar archivo local primero
    final file = File(ruta);
    if (file.existsSync()) {
      return Image.file(file, width: width, height: height, fit: BoxFit.cover);
    }
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

### 13.6 Estrategia de URLs para Web

```dart
// lib/config/url_strategy.dart
import 'package:flutter_web_plugins/url_strategy.dart';

void configureAppUrlStrategy() {
  setUrlStrategy(PathUrlStrategy());  // elimina # de las URLs
}
```

Llamar en `main.dart`:
```dart
void main() {
  if (kIsWeb) configureAppUrlStrategy();
  runApp(MyApp());
}
```

---

## 14. Referencia de Archivos Clave

| Archivo | Líneas | Propósito |
|---------|--------|-----------|
| `ugr_screen.dart` | ~400 | Scaffold principal con 5 tabs y FABs |
| `ugr_localidades_tab.dart` | ~900 | Lista de localidades, consolidación, agrupación |
| `ugr_edan_preview_screen.dart` | ~1200 | Previsualización EDAN, 3-branch bottom bar |
| `ugr_edan_localidad_preview_screen.dart` | ~800 | Previsualización de localidad, Aprobar/Rechazar |
| `ugr_edan_tab.dart` | ~600 | Sub-pestañas EDANs + Recursos |
| `ugr_recurso_tab.dart` | ~500 | Lista de documentos, PDF cache |
| `ugr_recurso_upload_screen.dart` | ~350 | Formulario de subida de documentos |
| `crear_usuario_screen.dart` | ~400 | Crear/editar alcalde (dual-mode) |
| `edan_sync_service.dart` | ~347 | Sincronización de EDANs |
| `api_service.dart` | ~1281 | Todos los endpoints API |
| `database_helper.dart` | ~1621 | SQLite v17, todas las tablas |
| `edan.dart` | ~2539 | Modelos Edan y EdanLocalidad |
