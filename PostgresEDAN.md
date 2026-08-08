# Especificación de Campos EDAN para PostgreSQL

Este documento describe **todos los campos** del formulario EDAN (Evaluación de Daños y Análisis de Necesidades) para crear tablas PostgreSQL compatibles con la aplicación móvil/flutter actual.

---

## 📋 Índice

1. [Tabla Principal: `edans`](#tabla-principal-edans)
2. [Tabla: `edan_localidades`](#tabla-edan_localidades)
3. [Sección 01: Datos Generales](#sección-01-datos-generales)
4. [Sección 02: Población Afectada](#sección-02-población-afectada)
5. [Sección 03: Impacto en Población](#sección-03-impacto-en-población)
6. [Sección 04: Salud](#sección-04-salud)
7. [Sección 05: Infraestructura](#sección-05-infraestructura)
8. [Sección 06: Servicios Básicos](#sección-06-servicios-básicos)
9. [Sección 07: Educación](#sección-07-educación)
10. [Sección 08: Viviendas](#sección-08-viviendas)
11. [Sección 09: Agropecuario](#sección-09-agropecuario)
12. [Sección 10: Protección](#sección-10-protección)
13. [Sección 11: Necesidades Humanitarias](#sección-11-necesidades-humanitarias)
14. [Sección 13: Responsable](#sección-13-responsable)
15. [Campos de Control/Offline](#campos-de-controloffline)

---

## 🗄️ Tabla Principal: `edans`

Cabecera del formulario EDAN.

| Campo | Tipo | Nullable | Default | Descripción |
|-------|------|----------|---------|-------------|
| `id_local` | `SERIAL` | ❌ | `AUTO INCREMENT` | ID local (offline) |
| `id_server` | `INTEGER` | ✅ | `NULL` | ID en servidor (tras sync) |
| `id_edan` | `INTEGER` | ✅ | `NULL` | ID EDAN (legacy) |
| `codigo_edan` | `VARCHAR(50)` | ❌ | `''` | Código único EDAN (ej: `EDAN-2026-001`) |
| `id_usuario` | `INTEGER` | ✅ | `NULL` | FK usuario que crea |
| `id_departamento` | `INTEGER` | ✅ | `NULL` | FK departamento |
| `departamento_nombre` | `VARCHAR(200)` | ✅ | `NULL` | Nombre departamento |
| `id_provincia` | `INTEGER` | ✅ | `NULL` | FK provincia |
| `provincia_nombre` | `VARCHAR(200)` | ✅ | `NULL` | Nombre provincia |
| `id_municipio` | `INTEGER` | ✅ | `NULL` | FK municipio |
| `municipio_nombre` | `VARCHAR(200)` | ✅ | `NULL` | Nombre municipio |
| `nombre_alcalde` | `VARCHAR(200)` | ❌ | `''` | Nombre alcalde/responsable |
| `fono_alcalde` | `VARCHAR(20)` | ❌ | `''` | Teléfono alcalde |
| `fecha_llenado` | `DATE` | ❌ | - | Fecha de llenado |
| `fecha_evento` | `DATE` | ❌ | - | Fecha del evento |
| `hora_evento` | `TIME` | ❌ | - | Hora del evento |
| `total_poblacion_afectada` | `INTEGER` | ❌ | `0` | **Sumatoria** población afectada |
| `total_familias_afectadas` | `INTEGER` | ❌ | `0` | **Sumatoria** familias afectadas |
| `total_familias_damnificadas` | `INTEGER` | ❌ | `0` | **Sumatoria** familias damnificadas |
| `id_tipo_evento` | `INTEGER` | ✅ | `NULL` | FK tipo evento |
| `tipo_evento_nombre` | `VARCHAR(100)` | ✅ | `NULL` | Nombre tipo evento |
| `id_estado` | `INTEGER` | ❌ | `1` | FK estado (1=borrador, 2=enviado, etc.) |
| `estado` | `VARCHAR(50)` | ❌ | `'borrador'` | Estado texto |
| `sincronizado` | `BOOLEAN` | ❌ | `FALSE` | **Sync flag** |
| `pendiente_eliminacion` | `BOOLEAN` | ❌ | `FALSE` | **Sync flag** |
| `pendiente_actualizacion` | `BOOLEAN` | ❌ | `FALSE` | **Sync flag** |
| `es_borrador` | `BOOLEAN` | ❌ | `FALSE` | **Sync flag** |
| `fecha_creacion` | `TIMESTAMP` | ❌ | `NOW()` | Fecha creación |
| `fecha_modificacion` | `TIMESTAMP` | ✅ | `NULL` | Última modificación |
| `intentos_sync` | `INTEGER` | ❌ | `0` | Intentos de sync |
| `ultimo_error` | `TEXT` | ✅ | `NULL` | Último error de sync |

---

## 📍 Tabla: `edan_localidades`

**Relación:** `edans.id_local` → `edan_localidades.id_edan_local` (1:N)

Cada EDAN puede tener **múltiples localidades** (comunidades, barrios, etc.).

| Campo | Tipo | Nullable | Default | Descripción |
|-------|------|----------|---------|-------------|
| `id_edan_localidad` | `SERIAL` | ❌ | `AUTO INCREMENT` | PK |
| `id_edan_local` | `INTEGER` | ❌ | - | FK a `edans.id_local` |
| `tipo_localidad` | `VARCHAR(50)` | ❌ | `''` | Ej: `Comunidad`, `Barrio`, `Zona` |
| `nombre` | `VARCHAR(200)` | ❌ | `''` | Nombre de la localidad |
| `imp_poblacion` | `BOOLEAN` | ❌ | `FALSE` | **Flag**: tiene impacto en población |
| `imp_salud` | `BOOLEAN` | ❌ | `FALSE` | **Flag**: tiene impacto en salud |
| `imp_infraestructura` | `BOOLEAN` | ❌ | `FALSE` | **Flag**: tiene impacto en infraestructura |
| `imp_servicios` | `BOOLEAN` | ❌ | `FALSE` | **Flag**: tiene impacto en servicios |
| `imp_educacion` | `BOOLEAN` | ❌ | `FALSE` | **Flag**: tiene impacto en educación |
| `imp_vivienda` | `BOOLEAN` | ❌ | `FALSE` | **Flag**: tiene impacto en vivienda |
| `imp_agropecuario` | `BOOLEAN` | ❌ | `FALSE` | **Flag**: tiene impacto agropecuario |
| `imp_proteccion` | `BOOLEAN` | ❌ | `FALSE` | **Flag**: tiene impacto en protección |
| `imp_necesidades` | `BOOLEAN` | ❌ | `FALSE` | **Flag**: tiene necesidades humanitarias |

---

## 📊 Sección 01: Datos Generales

**Almacenado en:** `edans` (campos principales) + `edan_localidades`

### Campos en `edans`:
- `nombre_alcalde`, `fono_alcalde`
- `fecha_llenado`, `fecha_evento`, `hora_evento`
- `id_departamento`, `departamento_nombre`
- `id_provincia`, `provincia_nombre`
- `id_municipio`, `municipio_nombre`
- `id_tipo_evento`, `tipo_evento_nombre`

### Campos en `edan_localidades`:
- `tipo_localidad`, `nombre` (ej: `Comunidad El Centro`)

---

## 👥 Sección 02: Población Afectada y Damnificada

**Almacenado en:** `edans`

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `total_poblacion_afectada` | `INTEGER` | **Sumatoria global** de afectados |
| `total_familias_afectadas` | `INTEGER` | **Sumatoria global** familias afectadas |
| `total_familias_damnificadas` | `INTEGER` | **Sumatoria global** familias damnificadas |

> **Nota:** Estos valores se calculan sumando todas las localidades.

---

## ⚠️ Sección 03: Impacto en Población

**Tabla:** `edan_localidades_impacto_poblacion`

**Relación:** `edan_localidades.id_edan_localidad` → `edan_localidades_impacto_poblacion.id_edan_localidad` (1:1)

| Campo | Tipo | Nullable | Default | Descripción |
|-------|------|----------|---------|-------------|
| `id_edan_localidad` | `INTEGER` | ❌ | - | FK |
| `grupo_etario` | `VARCHAR(100)` | ❌ | `''` | Grupo etario principal |
| `fallecidos` | `INTEGER` | ❌ | `0` | Total fallecidos |
| `heridos` | `INTEGER` | ❌ | `0` | Total heridos |
| `desaparecidos` | `INTEGER` | ❌ | `0` | Total desaparecidos |
| `observaciones` | `TEXT` | ❌ | `''` | Observaciones generales |

### Sub-tabla: `edan_grupo_etario_detalle`

**Relación:** `edan_localidades_impacto_poblacion.id_edan_localidad` → `edan_grupo_etario_detalle.id_edan_localidad` (1:N)

| Campo | Tipo | Nullable | Default | Descripción |
|-------|------|----------|---------|-------------|
| `id_grupo_etario_detalle` | `SERIAL` | ❌ | - | PK |
| `id_edan_localidad` | `INTEGER` | ❌ | - | FK |
| `rango` | `VARCHAR(100)` | ❌ | `''` | Ej: `Niño(a) 0-5 años`, `Escolar 6-18 años`, `Adulto 19-60 años`, `Adulto mayor 60+` |
| `fallecidos` | `INTEGER` | ❌ | `0` | |
| `heridos` | `INTEGER` | ❌ | `0` | |
| `desaparecidos` | `INTEGER` | ❌ | `0` | |
| `observaciones` | `TEXT` | ❌ | `''` | |

### Primera Respuesta (sub-sección)

**Tabla:** `edan_localidades_primera_respuesta`

| Campo | Tipo | Nullable | Default | Descripción |
|-------|------|----------|---------|-------------|
| `id_edan_localidad` | `INTEGER` | ❌ | - | FK |
| `busqueda` | `BOOLEAN` | ❌ | `FALSE` | **Checkbox**: Búsqueda y rescate |
| `salvamento` | `BOOLEAN` | ❌ | `FALSE` | **Checkbox**: Salvamento |
| `evacuacion` | `BOOLEAN` | ❌ | `FALSE` | **Checkbox**: Evacuación |
| `observaciones` | `TEXT` | ❌ | `''` | |

> **Regla de negocio:** Los 3 checkboxes son **excluyentes** (solo uno puede estar marcado a la vez).

---

## 🏥 Sección 04: Salud

**Tabla:** `edan_localidades_salud_establecimientos`

**Relación:** `edan_localidades.id_edan_localidad` → `estan_localidades_salud_establecimientos.id_edan_localidad` (1:N)

| Campo | Tipo | Nullable | Default | Descripción |
|-------|------|----------|---------|-------------|
| `id_establecimiento_salud` | `SERIAL` | ❌ | - | PK |
| `id_edan_localidad` | `INTEGER` | ❌ | - | FK |
| `nombre_establecimiento` | `VARCHAR(200)` | ❌ | `''` | Nombre del centro de salud |
| `comunidad` | `VARCHAR(200)` | ❌ | `''` | Comunidad donde está ubicado |
| `nivel_atencion` | `VARCHAR(50)` | ❌ | `''` | `1er Nivel`, `2do Nivel`, `3er Nivel` |
| `dano_parcial` | `BOOLEAN` | ❌ | `FALSE` | **Checkbox exclusivo** |
| `dano_total` | `BOOLEAN` | ❌ | `FALSE` | **Checkbox exclusivo** |
| `medicos_afectados` | `INTEGER` | ❌ | `0` | Número de médicos afectados |
| `enfermeras_afectadas` | `INTEGER` | ❌ | `0` | Número de enfermeras afectadas |
| `otros_afectados` | `INTEGER` | ❌ | `0` | Otro personal afectado |

### Necesidades de Salud

**Tabla:** `edan_localidades_salud_necesidades`

| Campo | Tipo | Nullable | Default | Descripción |
|-------|------|----------|---------|-------------|
| `id_edan_localidad` | `INTEGER` | ❌ | - | FK |
| `botiquines` | `BOOLEAN` | ❌ | `FALSE` | **Checkbox**: Necesita botiquines |
| `numero_personas` | `INTEGER` | ❌ | `0` | Número de personas que necesitan atención |
| `otras_necesidades` | `TEXT` | ❌ | `''` | Otras necesidades |
| `observaciones` | `TEXT` | ❌ | `''` | |

---

## 🛣️ Sección 05: Infraestructura

### 5.1: Daños Viales

**Tabla:** `edan_localidades_danos_viales`

| Campo | Tipo | Nullable | Default | Descripción |
|-------|------|----------|---------|-------------|
| `id_dano_vial` | `SERIAL` | ❌ | - | PK |
| `id_edan_localidad` | `INTEGER` | ❌ | - | FK |
| `via_puente` | `VARCHAR(200)` | ❌ | `''` | Nombre de vía o puente |
| `tramo` | `VARCHAR(200)` | ❌ | `''` | Tramo específico |
| `dano_parcial` | `BOOLEAN` | ❌ | `FALSE` | **Checkbox exclusivo** |
| `dano_total` | `BOOLEAN` | ❌ | `FALSE` | **Checkbox exclusivo** |
| `km_danio` | `NUMERIC(10,2)` | ❌ | `0` | Kilómetros dañados |
| `necesidades_inmediatas` | `TEXT` | ❌ | `''` | |
| `observaciones` | `TEXT` | ❌ | `''` | |

### 5.2: Infraestructura Pública

**Tabla:** `edan_localidades_danos_infra_publica`

| Campo | Tipo | Nullable | Default | Descripción |
|-------|------|----------|---------|-------------|
| `id_dano_infra` | `SERIAL` | ❌ | - | PK |
| `id_edan_localidad` | `INTEGER` | ❌ | - | FK |
| `comunidad` | `VARCHAR(200)` | ❌ | `''` | |
| `tipo_estructura` | `VARCHAR(200)` | ❌ | `''` | Tipo de infraestructura |
| `dano_parcial` | `BOOLEAN` | ❌ | `FALSE` | **Checkbox exclusivo** |
| `dano_total` | `BOOLEAN` | ❌ | `FALSE` | **Checkbox exclusivo** |
| `observaciones` | `TEXT` | ❌ | `''` | |

---

## 💧 Sección 06: Servicios Básicos

**Tabla:** `edan_localidades_servicios_basicos`

**Relación:** 1 localidad → 5 servicios básicos (energía, agua, alcantarillado, gas, telecom)

| Campo | Tipo | Nullable | Default | Descripción |
|-------|------|----------|---------|-------------|
| `id_servicio_basico` | `SERIAL` | ❌ | - | PK |
| `id_edan_localidad` | `INTEGER` | ❌ | - | FK |
| `tipo` | `VARCHAR(50)` | ❌ | - | `energia_electrica`, `agua_potable`, `alcantarillado`, `gas_domiciliario`, `telecomunicaciones` |
| `afectado` | `BOOLEAN` | ❌ | `FALSE` | **Checkbox**: ¿Está afectado? |
| `dano_parcial` | `BOOLEAN` | ❌ | `FALSE` | **Checkbox exclusivo** |
| `dano_total` | `BOOLEAN` | ❌ | `FALSE` | **Checkbox exclusivo** |
| `necesidades_inmediatas` | `TEXT` | ❌ | `''` | |
| `observaciones` | `TEXT` | ❌ | `''` | |

> **Regla de negocio:** Si `afectado = TRUE`, entonces `dano_parcial` O `dano_total` debe ser `TRUE` (excluyentes).

---

## 🏫 Sección 07: Educación

**Tabla:** `edan_localidades_unidades_educativas`

**Relación:** 1 localidad → N unidades educativas

| Campo | Tipo | Nullable | Default | Descripción |
|-------|------|----------|---------|-------------|
| `id_unidad_educativa` | `SERIAL` | ❌ | - | PK |
| `id_edan_localidad` | `INTEGER` | ❌ | - | FK |
| `nombre_establecimiento` | `VARCHAR(200)` | ❌ | `''` | Nombre de la unidad educativa |
| `comunidad` | `VARCHAR(200)` | ❌ | `''` | |
| `dano_parcial` | `BOOLEAN` | ❌ | `FALSE` | **Checkbox exclusivo** |
| `dano_total` | `BOOLEAN` | ❌ | `FALSE` | **Checkbox exclusivo** |
| `suspension_clases` | `BOOLEAN` | ✅ | `NULL` | **Tri-state**: `NULL`=sin marcar, `TRUE`=Sí, `FALSE`=No |
| `perdida_material` | `BOOLEAN` | ✅ | `NULL` | **Tri-state** |
| `funciona_albergue` | `BOOLEAN` | ✅ | `NULL` | **Tri-state** |
| `estudiantes` | `INTEGER` | ❌ | `0` | Número de estudiantes afectados |
| `profesores` | `INTEGER` | ❌ | `0` | Número de profesores afectados |
| `administrativos` | `INTEGER` | ❌ | `0` | Número de administrativos afectados |
| `observaciones` | `TEXT` | ❌ | `''` | |

### Sumatorias calculadas (lado aplicación):
```sql
-- Total afectados por unidad educativa
estudiantes + profesores + administrativos
```

---

## 🏠 Sección 08: Viviendas

**Tabla:** `edan_localidades_danos_vivienda`

| Campo | Tipo | Nullable | Default | Descripción |
|-------|------|----------|---------|-------------|
| `id_dano_vivienda` | `SERIAL` | ❌ | - | PK |
| `id_edan_localidad` | `INTEGER` | ❌ | - | FK |
| `comunidad` | `VARCHAR(200)` | ❌ | `''` | |
| `dano_parcial` | `INTEGER` | ❌ | `0` | **Número** de viviendas con daño parcial |
| `dano_total` | `INTEGER` | ❌ | `0` | **Número** de viviendas con daño total |
| `necesidades_inmediatas` | `TEXT` | ❌ | `''` | |
| `observaciones` | `TEXT` | ❌ | `''` | |

> **Nota:** A diferencia de otras secciones, aquí `dano_parcial` y `dano_total` son **números** (cantidad de viviendas), no checkboxes.

---

## 🌾 Sección 09: Agropecuario

### 9.1: Agricultura

**Tabla:** `edan_localidades_danos_agricultura`

| Campo | Tipo | Nullable | Default | Descripción |
|-------|------|----------|---------|-------------|
| `id_dano_agricultura` | `SERIAL` | ❌ | - | PK |
| `id_edan_localidad` | `INTEGER` | ❌ | - | FK |
| `tipo_cultivo` | `VARCHAR(200)` | ❌ | `''` | Tipo de cultivo |
| `hectareas_afectadas` | `INTEGER` | ❌ | `0` | Hectáreas afectadas |
| `hectareas_perdidas` | `INTEGER` | ❌ | `0` | Hectáreas perdidas |
| `necesidades_inmediatas` | `TEXT` | ❌ | `''` | |
| `observaciones` | `TEXT` | ❌ | `''` | |

### 9.2: Pecuario

**Tabla:** `edan_localidades_danos_pecuario`

| Campo | Tipo | Nullable | Default | Descripción |
|-------|------|----------|---------|-------------|
| `id_dano_pecuario` | `SERIAL` | ❌ | - | PK |
| `id_edan_localidad` | `INTEGER` | ❌ | - | FK |
| `especie` | `VARCHAR(100)` | ❌ | `''` | Especie animal |
| `raza` | `VARCHAR(100)` | ❌ | `''` | Raza |
| `animales_afectados` | `INTEGER` | ❌ | `0` | |
| `animales_muertos` | `INTEGER` | ❌ | `0` | |
| `necesidades_inmediatas` | `TEXT` | ❌ | `''` | |

### 9.3: Infraestructura Productiva

**Tabla:** `edan_localidades_infra_productiva`

| Campo | Tipo | Nullable | Default | Descripción |
|-------|------|----------|---------|-------------|
| `id_infra_productiva` | `SERIAL` | ❌ | - | PK |
| `id_edan_localidad` | `INTEGER` | ❌ | - | FK |
| `tipo` | `VARCHAR(200)` | ❌ | `''` | Tipo de infraestructura |
| `dano_parcial` | `INTEGER` | ❌ | `0` | **Número** de infraestructuras |
| `dano_total` | `INTEGER` | ❌ | `0` | **Número** de infraestructuras |

---

## 🛡️ Sección 10: Protección

### Tabla Principal: `edan_localidades_proteccion`

| Campo | Tipo | Nullable | Default | Descripción |
|-------|------|----------|---------|-------------|
| `id_edan_localidad` | `INTEGER` | ❌ | - | FK (1:1) |

### Grupos Vulnerables: `edan_localidades_proteccion_grupos`

**Relación:** 1 localidad → 7 grupos vulnerables

| Campo | Tipo | Nullable | Default | Descripción |
|-------|------|----------|---------|-------------|
| `id_grupo_vulnerable` | `SERIAL` | ❌ | - | PK |
| `id_edan_localidad` | `INTEGER` | ❌ | - | FK |
| `grupo` | `VARCHAR(50)` | ❌ | - | `ninos`, `adolescentes`, `mujeres_lactantes`, `mujeres_embarazadas`, `adultos_mayores`, `personas_discapacidad`, `personas_enfermedad` |
| `mujeres` | `INTEGER` | ❌ | `0` | Número de mujeres |
| `hombres` | `INTEGER` | ❌ | `0` | Número de hombres |
| `apoyo_psicologico` | `BOOLEAN` | ✅ | `NULL` | **Tri-state**: ¿Requiere apoyo psicológico? |
| `reposicion_documentos` | `BOOLEAN` | ✅ | `NULL` | **Tri-state**: ¿Requiere reposición de documentos? |
| `observaciones` | `TEXT` | ❌ | `''` | |

### Sumatorias calculadas (lado aplicación):
```sql
-- Total por grupo
mujeres + hombres

-- Total mujeres (todos los grupos)
SUM(mujeres) OVER (PARTITION BY id_edan_localidad)

-- Total hombres (todos los grupos)
SUM(hombres) OVER (PARTITION BY id_edan_localidad)

-- Total general
SUM(mujeres + hombres) OVER (PARTITION BY id_edan_localidad)
```

---

## 📦 Sección 11: Necesidades Humanitarias

**Tabla:** `edan_localidades_necesidades_humanitarias`

| Campo | Tipo | Nullable | Default | Descripción |
|-------|------|----------|---------|-------------|
| `id_edan_localidad` | `INTEGER` | ❌ | - | FK (1:1) |
| `alimentos` | `BOOLEAN` | ❌ | `FALSE` | **Checkbox** |
| `refugio_vivienda` | `BOOLEAN` | ❌ | `FALSE` | **Checkbox** |
| `ropa_cama` | `BOOLEAN` | ❌ | `FALSE` | **Checkbox** |
| `articulos_higiene` | `BOOLEAN` | ❌ | `FALSE` | **Checkbox** |
| `articulos_cocina` | `BOOLEAN` | ❌ | `FALSE` | **Checkbox** |
| `prendas_vestir` | `BOOLEAN` | ❌ | `FALSE` | **Checkbox** |
| `herramientas` | `BOOLEAN` | ❌ | `FALSE` | **Checkbox** |
| `almacenamiento_agua` | `BOOLEAN` | ❌ | `FALSE` | **Checkbox** |
| `banos` | `BOOLEAN` | ❌ | `FALSE` | **Checkbox** |
| `obs_alimentos` | `TEXT` | ❌ | `''` | **Observaciones específicas** (solo si `alimentos = TRUE`) |
| `obs_refugio_vivienda` | `TEXT` | ❌ | `''` | |
| `obs_ropa_cama` | `TEXT` | ❌ | `''` | |
| `obs_articulos_higiene` | `TEXT` | ❌ | `''` | |
| `obs_articulos_cocina` | `TEXT` | ❌ | `''` | |
| `obs_prendas_vestir` | `TEXT` | ❌ | `''` | |
| `obs_herramientas` | `TEXT` | ❌ | `''` | |
| `obs_almacenamiento_agua` | `TEXT` | ❌ | `''` | |
| `obs_banos` | `TEXT` | ❌ | `''` | |

> **Regla de negocio:** Cada campo `obs_*` solo se muestra/llena si el checkbox correspondiente está marcado.

---

## 👤 Sección 13: Responsable del Formulario

**Almacenado en:** `edans.responsable_*` (JSON o columnas separadas)

**Opción A - Columnas separadas (recomendado):**

| Campo | Tipo | Nullable | Default |
|-------|------|----------|---------|
| `responsable_nombre` | `VARCHAR(200)` | ❌ | `''` |
| `responsable_cargo` | `VARCHAR(200)` | ❌ | `''` |
| `responsable_fono` | `VARCHAR(20)` | ❌ | `''` |
| `responsable_correo` | `VARCHAR(200)` | ❌ | `''` |

**Opción B - JSON:**

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `responsable` | `JSONB` | `{"nombre": "...", "cargo": "...", "fono": "...", "correo": "..."}` |

> **Nota:** Estos datos se **autocompletan** desde el usuario logueado (token de autenticación).

---

## 🔧 Campos de Control/Offline

Estos campos son **críticos** para la sincronización offline-first:

| Campo | Tipo | Descripción | Cuándo se modifica |
|-------|------|-------------|-------------------|
| `sincronizado` | `BOOLEAN` | ¿Ya se sincronizó con servidor? | `TRUE` tras sync exitoso |
| `pendiente_eliminacion` | `BOOLEAN` | ¿Marcado para eliminar en servidor? | `TRUE` cuando usuario elimina localmente |
| `pendiente_actualizacion` | `BOOLEAN` | ¿Tiene cambios pendientes? | `TRUE` tras editar borrador |
| `es_borrador` | `BOOLEAN` | ¿Es borrador no enviado? | `TRUE` si `estado = 'borrador'` |
| `fecha_creacion` | `TIMESTAMP` | Fecha creación local | Solo al crear |
| `fecha_modificacion` | `TIMESTAMP` | Última modificación | Cada `UPDATE` |
| `intentos_sync` | `INTEGER` | Intentos de sincronización | Incrementa tras fallo |
| `ultimo_error` | `TEXT` | Último error de sync | Tras fallo de sync |

### Estados posibles:

| Estado | `sincronizado` | `pendiente_eliminacion` | `pendiente_actualizacion` | `es_borrador` | ¿Editable? |
|--------|---------------|------------------------|--------------------------|---------------|------------|
| Borrador nuevo | `FALSE` | `FALSE` | `FALSE` | `TRUE` | ✅ Sí |
| Borrador editado | `FALSE` | `FALSE` | `TRUE` | `TRUE` | ✅ Sí |
| Enviado (sync OK) | `TRUE` | `FALSE` | `FALSE` | `FALSE` | ❌ No (solo lectura) |
| Pendiente eliminación | `FALSE` | `TRUE` | `FALSE` | `FALSE` | ❌ No |

---

## 📐 Relaciones ERD (Resumen)

```
edans (1) ──< (N) edan_localidades
                        │
                        ├──< (1) edan_localidades_impacto_poblacion
                        │         └──< (N) edan_grupo_etario_detalle
                        │
                        ├──< (1) edan_localidades_primera_respuesta
                        │
                        ├──< (N) edan_localidades_salud_establecimientos
                        ├──< (1) edan_localidades_salud_necesidades
                        │
                        ├──< (N) edan_localidades_danos_viales
                        ├──< (N) edan_localidades_danos_infra_publica
                        │
                        ├──< (N) edan_localidades_servicios_basicos
                        │
                        ├──< (N) edan_localidades_unidades_educativas
                        │
                        ├──< (N) edan_localidades_danos_vivienda
                        │
                        ├──< (N) edan_localidades_danos_agricultura
                        ├──< (N) edan_localidades_danos_pecuario
                        ├──< (N) edan_localidades_infra_productiva
                        │
                        ├──< (1) edan_localidades_proteccion
                        │         └──< (7) edan_localidades_proteccion_grupos
                        │
                        └──< (1) edan_localidades_necesidades_humanitarias
```

---

## 🔑 Índices Recomendados

```sql
-- Índices para consultas frecuentes
CREATE INDEX idx_edans_usuario ON edans(id_usuario);
CREATE INDEX idx_edans_estado ON edans(estado);
CREATE INDEX idx_edans_sincronizado ON edans(sincronizado) WHERE sincronizado = FALSE;
CREATE INDEX idx_edans_fecha_creacion ON edans(fecha_creacion DESC);

CREATE INDEX idx_edan_localidades_edan ON edan_localidades(id_edan_local);
CREATE INDEX idx_edan_localidades_imp ON edan_localidades(imp_poblacion, imp_salud, imp_infraestructura);

-- Índices para búsquedas
CREATE INDEX idx_edans_municipio ON edans(id_municipio);
CREATE INDEX idx_edans_tipo_evento ON edans(id_tipo_evento);
```

---

## 📝 Notas Importantes

### 1. **Campos Tri-state (`BOOLEAN` nullable)**
Los siguientes campos usan `NULL` para "sin marcar", `TRUE` para "Sí", `FALSE` para "No":
- `edan_localidades_unidades_educativas.suspension_clases`
- `edan_localidades_unidades_educativas.perdida_material`
- `edan_localidades_unidades_educativas.funciona_albergue`
- `edan_localidades_proteccion_grupos.apoyo_psicologico`
- `edan_localidades_proteccion_grupos.reposicion_documentos`

### 2. **Checksums exclusivos**
En las siguientes tablas, `dano_parcial` y `dano_total` son **excluyentes** (solo uno puede ser `TRUE`):
- `edan_localidades_salud_establecimientos`
- `edan_localidades_danos_viales`
- `edan_localidades_danos_infra_publica`
- `edan_localidades_servicios_basicos`
- `edan_localidades_unidades_educativas`

### 3. **Navegación en Educación**
La sección 07 permite **agregar N unidades educativas** por localidad. Cada unidad es independiente con su propio:
- Nombre del establecimiento
- Comunidad
- Daños (parcial/total)
- Flags tri-state (suspensión, pérdida, albergue)
- Número de afectados (estudiantes, profesores, administrativos)

### 4. **Sumatorias Automáticas**
Las siguientes sumatorias se calculan en la aplicación (no en DB):
- `total_poblacion_afectada` = Σ todas las localidades
- `total_familias_afectadas` = Σ todas las localidades
- `total_familias_damnificadas` = Σ todas las localidades
- `unidades_educativas.total_afectados` = estudiantes + profesores + administrativos
- `proteccion.total_mujeres` = Σ mujeres de los 7 grupos
- `proteccion.total_hombres` = Σ hombres de los 7 grupos
- `proteccion.total_general` = Σ total de los 7 grupos

### 5. **Flags `imp_*` en Localidades**
Los campos `imp_poblacion`, `imp_salud`, etc. indican **qué secciones completó el usuario** para esa localidad. Se usan para:
- Filtrar secciones visibles en borradores parciales
- Calcular progreso del formulario
- Validar completitud antes de enviar

---

## 📦 Ejemplo de Inserción (SQL)

```sql
-- 1. Insertar EDAN principal
INSERT INTO edans (
  codigo_edan, id_usuario, id_departamento, departamento_nombre,
  id_provincia, provincia_nombre, id_municipio, municipio_nombre,
  nombre_alcalde, fono_alcalde, fecha_llenado, fecha_evento, hora_evento,
  id_tipo_evento, tipo_evento_nombre, id_estado, estado,
  fecha_creacion, es_borrador
) VALUES (
  'EDAN-2026-001', 123, 1, 'La Paz',
  2, 'Pedro Domingo Murillo', 3, 'La Paz',
  'Juan Pérez', '77712345', '2026-08-08', '2026-08-07', '14:00',
  5, 'INUNDACIÓN', 1, 'borrador',
  NOW(), TRUE
) RETURNING id_local;

-- Supongamos que id_local = 1001

-- 2. Insertar localidad
INSERT INTO edan_localidades (
  id_edan_local, tipo_localidad, nombre,
  imp_poblacion, imp_salud, imp_educacion
) VALUES (
  1001, 'Comunidad', 'El Centro',
  TRUE, TRUE, TRUE
) RETURNING id_edan_localidad;

-- Supongamos que id_edan_localidad = 5001

-- 3. Insertar impacto en población
INSERT INTO edan_localidades_impacto_poblacion (
  id_edan_localidad, grupo_etario, fallecidos, heridos, desaparecidos
) VALUES (
  5001, 'Adulto 19-60 años', 0, 2, 0
);

-- 4. Insertar grupos etarios detalle
INSERT INTO edan_grupo_etario_detalle (
  id_edan_localidad, rango, fallecidos, heridos, desaparecidos
) VALUES
  (5001, 'Niño(a) 0-5 años', 0, 0, 0),
  (5001, 'Escolar 6-18 años', 0, 1, 0),
  (5001, 'Adulto 19-60 años', 0, 1, 0),
  (5001, 'Adulto mayor 60+ años', 0, 0, 0);

-- 5. Insertar establecimiento de salud
INSERT INTO edan_localidades_salud_establecimientos (
  id_edan_localidad, nombre_establecimiento, comunidad,
  nivel_atencion, dano_parcial, dano_total,
  medicos_afectados, enfermeras_afectadas
) VALUES (
  5001, 'Centro de Salud El Centro', 'El Centro',
  '1er Nivel', TRUE, FALSE,
  1, 2
);

-- 6. Insertar unidad educativa
INSERT INTO edan_localidades_unidades_educativas (
  id_edan_localidad, nombre_establecimiento, comunidad,
  dano_parcial, dano_total, suspension_clases,
  estudiantes, profesores, administrativos
) VALUES (
  5001, 'Unidad Educativa Bolivia', 'El Centro',
  FALSE, TRUE, TRUE,
  150, 12, 3
);
```

---

## ✅ Checklist para el Equipo de Backend

- [ ] Crear todas las tablas listadas
- [ ] Agregar índices recomendados
- [ ] Configurar FKs con `ON DELETE CASCADE`
- [ ] Agregar constraint de exclusividad para checkboxes (trigger o check constraint)
- [ ] Configurar usuarios/roles para sync
- [ ] Crear endpoints API para:
  - [ ] `POST /edans` (crear borrador)
  - [ ] `PUT /edans/:id` (actualizar borrador)
  - [ ] `GET /edans` (listar mis EDANs)
  - [ ] `GET /edans/:id` (obtener detalle)
  - [ ] `DELETE /edans/:id` (marcar pendiente eliminación)
  - [ ] `POST /edans/:id/sincronizar` (confirmar sync)

---

**Documento generado:** 2026-08-08  
**Versión:** 1.0  
**Basado en:** Flutter app `APP_REA` (carpeta `REA/lib/models/edan.dart`)
