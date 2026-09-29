# 🚀 Guía RESP — El EDAN en tu bolsillo

> **Rol 7 · Responsable Local**. Antes llevabas el formulario en papel. Ahora el EDAN vive en tu celular: fotos con GPS, secciones guiadas y envío a la UGR con un toque. Bienvenido a la versión digital. 😉

---

## 🎯 1. Qué cambió: del papel a la app

| En papel 📄 | En la app 📱 |
|---|---|
| Formulario con varias hojas sueltas | **1 formulario deslizable** (todo junto) |
| Escribías a mano y podías manchar/perder la data | **Guardado automático** en tu dispositivo |
| Las fotos iban aparte, sin ubicación | **Fotos georreferenciadas** (salen con su GPS) |
| Enviabas físico al municipio | **Envío digital a la UGR** en 1 toque |
| Nadie sabía el estado del trámite | **Estados visibles**: borrador → enviado → aprobado/rechazado |
| Todo quedaba en papel, difícil de buscar | **Trazable**: quién, qué, dónde y cuándo |

**Justificación**: la información llega más rápido, más completa y con evidencia (fotos + GPS). Ayuda a que la respuesta a la comunidad sea más ágil.

---

## 🌟 2. Quién eres tú (el RESP)

Eres la **autoridad máxima de tu comunidad** o alguien delegado por ella. Cuando ocurre un evento (granizada, inundación, sismo...), tú levantas el **EDAN local**: qué pasó, cuántos daños, qué se necesita.

{IMAGEN: bienvenida de la app con el nombre del usuario y "Responsable Local"}

---

## 🔁 3. El ciclo del EDAN (el viaje de tu reporte)

```
 RECOPILAS    →   LLENAS el       →   REVISAS y      →   APROBACIÓN      →   CONSOLIDACIÓN
 evidencia        EDAN local          ENVÍAS al           de la UGR           (EDAN municipal)
 (fotos+datos)    (13 secciones)      UGR                                    la arma la UGR
```

Tu trabajo termina cuando tu reporte está **completo y enviado**. De ahí en adelante, la UGR aprueba, verifica y consolida.

---

## 🏠 4. Tu pantalla principal (el "control center")

Así se ve tu app y qué hace cada pieza:

```
┌────────────────────────────────────────────────┐
│ 🏠 Inicio          [☁️ Sincronizar] [⬤ En línea]│   ← Barra superior
├────────────────────────────────────────────────┤
│                                                │
│   (contenido de la pestaña)                   │
│                                                │
├────────────────────────────────────────────────┤
│  ➕   Inicio · Reportes · Mapa · Guía · Perfil  │   ← 5 pestañas
└────────────────────────────────────────────────┘
          ⚡ = Asistente IA (siempre contigo)
```

- **Barra superior**: nombre de la pestaña, botón **☁️ sincronizar** (con número si hay pendientes) y tu estado **⬤ En línea** (verde) / **Sin conexión** (rojo).
- **Botón flotante ➕** *(FAB)*: **crea un reporte nuevo**. Está en Inicio y en Reportes.
- **Botón flotante ✨ Asistente IA** *(FAB)*: pregúntale dudas en cualquier pantalla.
- **5 pestañas**: tu hogar navegable. Cada una es un "modo" de trabajo.

{IMAGEN: pantalla principal de RESP con FAB "+", asistente IA, botón sincronizar y las 5 pestañas}

---

## 📝 5. Crear un reporte: el formulario que "pasa páginas" (PageView)

Este es el corazón de la app. Es un **libro digital**: no llenas una hoja gigante, sino **varias páginas** que pasas deslizando. Así se eliminó el formato papel.

### Las etapas del formulario (en orden)

**1. Arranque** → pulsa **➕** en Inicio o Reportes.
**2. Introducción** → lee el para qué del EDAN.
**3. Página 01 · Datos generales** 🗺️ → lugar, fecha, evento, y **marca los impactos**.
**4. Páginas 02–11** → daños y necesidades **según lo que marcaste** (la app solo te muestra lo que aplica).
**5. Página 13 · Responsable** 🪪 → con tus datos, ya pre-llenada.
**6. Resumen y envío** 📤 → revisa todo y **envía** con tu declaración.

```
┌─────────────── Indicador de pasos ───────────────┐
│  ● Intro  ● 01  ● 02  ● 04  ● 13  ● Resumen     │
│  (toca cualquier círculo para saltar)            │
├──────────────────────────────────────────────────┤
│  ✋ 04 · Impacto en la salud                     │
│  "Desliza o pulsa →"                            │
│  (local_hospital: establecimientos + fotos)      │
├──────────────────────────────────────────────────┤
│  ← Anterior        [Sección guardada ✓]   →     │
│                          [💚 ENVIAR] (en resumen) │
└──────────────────────────────────────────────────┘
```

### Trucos del sistema de páginas

- **Desliza** a la izquierda (o pulsa **Siguiente**) para avanzar; **Anterior** para volver.
- El **indicador de pasos** (círculos arriba) es tu mapa: **verde ✓** = completada, **ámbar** = la actual, toca cualquiera para **saltar directo**.
- El formulario es **inteligente**: si en 01 NO marcas "salud", la página 04 no aparece. Menos pasos, menos ruido.
- Cada página **se guarda sola** (en SQLite) al pasar. Tu data está segura aunque se cierre la app.
- **💾 Guardar borrador** (arriba) → "Borrador guardado". Sirve para llenar por partes.
- Al salir con cambios te pregunta: **"¿Salir del formulario?"** con la opción **Salir y guardar**.

### 📚 Las secciones del EDAN

| Página | Sección | Ícono |
|--------|---------|-------|
| Intro | Instrucciones y para qué | ℹ️ |
| 01 | Datos generales (lugar, fecha, evento, impactos) | 📍 |
| 02 | Población damnificada y afectada | 🧑‍🤝‍🧑 |
| 03 | Impacto en la población (grupos etarios + 1ª respuesta) | 👥 |
| 04 | Impacto en la salud (establecimientos + necesidades) | 🏥 |
| 05 | Impacto en infraestructuras (vías, puentes, pública) | 🏙️ |
| 06 | Impacto en servicios básicos (agua, luz, gas...) | 🏘️ |
| 07 | Impacto en educación | 🏫 |
| 08 | Impacto en viviendas | 🏠 |
| 09 | Impacto agropecuario (cultivos, pecuario, productiva) | 🚜 |
| 10 | Necesidades de protección | 🛡️ |
| 11 | Necesidades humanitarias | 🤝 |
| 13 | Responsable del formulario (pre-llenada) | 🪪 |
| — | Resumen y envío | 📊 |

### 📸 Etapa clave: las fotos

En las secciones de daños **toma fotos**. Cada una se guarda **con su GPS**: la prueba principal de tu reporte. Mapa y UGR las verán georreferenciadas.

### 🔐 El envío (tu firma digital)

1. Ve al **Resumen** y revisa secciones.
2. Pulsa **💚 Enviar**.
3. Confirmas la **declaración jurada**: la info será revisada para análisis y corresponde hacer el documento legal del EDAN municipal por parte del UGR.
4. Mensaje: **"Formulario enviado a UGR"** (sin red: "...se sincronizará después").

---

## 🔍 6. Etapas dentro de la pestaña Inicio

Un vistazo, dato y acción. Inicio tiene **4 zonas**:

1. **Bienvenida** 👋 — tu nombre y cargo.
2. **Indicadores** 🎚️ — Total · Sin consolidar · Enviadas UGR · Aprobadas · Rechazadas. **Toca uno** y saltas a Reportes con ese filtro ya aplicado.
3. **Actividad reciente** 🕘 — tus últimos 15 reportes, con estado, evento y fecha.
4. **Acciones de tarjeta** — toca para **ver vista previa**; **Editar / Eliminar** solo en borradores. Tira de la lista para **actualizar**.

{IMAGEN: pestaña Inicio con indicadores y actividad reciente}

---

## 📋 7. Etapas dentro de la pestaña Reportes

Reportes es tu **archivo y mesa de trabajo** del EDAN:

1. **Filtros (chips)** 🏷️ — Todas · Borrador · Enviadas UGR · Aprobadas · Rechazadas.
2. **Buscador** 🔎 — busca por nombre o tipo de localidad.
3. **Lista de tarjetas** 🗂️ — estado con colores, "Reportado por", datos clave.
4. **Vista previa** 👁️ — abre la tarjeta: ves el documento completo con sus secciones.
5. **Acciones** — **Enviar** (si falta completar te avisa), **Editar**, **Eliminar**.

> 💡 Eliminar un reporte **ya sincronizado** no lo borra al instante: se marca *"pendiente de eliminación"* y se elimina del servidor al sincronizar.

{IMAGEN: Reportes con chips de filtro, buscador y tarjetas}

---

## 🗺️ 8. Etapas dentro de la pestaña Mapa

Tu reporte con ojos de mapa 🛰️:

1. **Mapa** — sector callejero o **vista satelital**.
2. **Puntos por sección** — marcadores de salud, vías, viviendas... (8 íconos según impacto).
3. **Contador GPS** 🧭 — "N punto(s) / N foto(s) con GPS".
4. **Filtro de fecha** 📅 — chips tipo píldora: al tocarlos se filtran y centran los puntos del evento.
5. **Galería de fotos** 🖼️ — "toca para ver en el mapa". Foto a pantalla completa con coordenadas.
6. **Leyenda** 📖 — despliega los íconos/secciones.
7. **Ficha de punto** — toca un marcador: GPS, localidad, sección, daños, miniaturas.

{IMAGEN: mapa con marcadores por sección, galería de fotos y leyenda desplegada}

---

## 🧭 9. La pestaña Guía (tu brújula dentro de la app)

Ayuda integrada: el ciclo del EDAN, consejos de fotos georreferenciadas y atajo al **Asistente IA**. Resuelve dudas sin salir de la app.

---

## 🧑 10. Etapas dentro de la pestaña Perfil

1. **Tus datos** 🪪 — usuario, carnet, celular, correo, cargo, comunidad, ubicación, rol.
2. **Actualizar catálogos** 📦 — descarga estados, tipos y el mapa del municipio para **usar sin internet**.
3. **Editar perfil** ✏️ — datos personales y ubicación geográfica (identificación bloqueada).
4. **Cerrar sesión** 🚪 — aviso importante: borra datos locales; al volver a entrar **se recupera todo** desde el servidor.

---

## 🌐 11. Sincronización: tu reporte siempre viaja seguro

- **Sin conexión** → todo queda guardado en tu dispositivo (nada se pierde).
- **Al reconectar** → la app **sincroniza sola** (también puedes pulsar **☁️**).
- El botón nube muestra **cuántos cambios** están pendientes y gira mientras sincroniza.
- Resultado del sync → resumen verde ✓ (todo bien) o rojo (con fallos a reintentar).

---

## 💬 12. Mensajes clave (qué te va a decir la app)

| Mensaje | Cuándo | 🎨 |
|---------|--------|-----|
| "Borrador guardado" | Guardo con 💾 | 💾 |
| "Reporte guardado correctamente." | Creé un reporte | ✅ |
| "Formulario enviado a UGR" | Envié el reporte | 🚀 |
| "Formulario enviado a UGR (sin conexión; se sincronizará después)" | Envío sin red | 📡 |
| "Localidad enviada al UGR" | Envío desde vista previa | 📤 |
| "Localidad marcada para eliminación. Se borrará al sincronizar." | Eliminé algo ya sincronizado | ⏳ |
| "Localidad eliminada" | Borré un borrador | 🗑️ |
| "Sin conexión: los cambios están guardados localmente." | Sincronizo sin red | ⚠️ |

---

## 🏆 13. Impactos positivos y mejoras esperadas

**Impactos positivos** 😃
- **Menos errores**: el formulario solo pide lo que aplica; secciones incompletas se ven al instante.
- **Respaldo de evidencia**: cada foto trae su GPS.
- **Velocidad**: el reporte llega al municipio en minutos, no en días.
- **Transparencia**: el RESP y la UGR ven el mismo estado del trámite.

**Mejoras esperadas** 🚀
- Mayor **completitud** de los EDAN locales (menos idas y vueltas).
- **Seguimiento en vivo** desde la UGR mientras llenas el borrador.
- Menos **trabajo administrativo** y más tiempo en la comunidad.
- **Decisiones informadas**: datos y fotos reales para la respuesta.

---

## 🗺️ 14. Flujo completo de principio a fin

```
[Evento en tu comunidad]
   │
   ▼
[➕ Nuevo reporte] → [Introducción] → [01 Datos grales + impactos]
   │
   ▼
[Secciones 02-11 según impactos + 📸 fotos GPS]
   │
   ▼
[13 Responsable (pre-llenada)] → [Resumen]
   │
   ▼
[💚 Enviar + declaración jurada] → "Formulario enviado a UGR"
   │
   ▼
┌───────────── Estados posibles ──────────────┐
│ Borrador ──► Enviado UGR ──► Aprobado ✓     │
│                    └────────► Rechazado ✗    │
│                    (corriges y reenvías)     │
└─────────────────────────────────────────────┘
   │
   ▼
[Aprobado] ──► La UGR consolida el EDAN municipal y tú lo ves en Mapa
```

**Resumen en una línea**: *levantas el EDAN, lo dejas completo con fotos, lo envías y la UGR se encarga del resto — todo desde tu celular.*