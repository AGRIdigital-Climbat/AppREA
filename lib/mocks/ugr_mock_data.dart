import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/ugr_models.dart';

List<String> mockTiposEvento() => const [
      'Granizada',
      'Inundación',
      'Deslizamiento',
      'Helada',
      'Incendio',
      'Vendaval',
      'Sequía',
    ];

List<UgrReporte> mockReportes() => [
      UgrReporte(
        id: 'mock-rep-1',
        tipoEvento: 'Granizada',
        comunidad: 'San Miguel',
        municipio: 'Sacaba',
        responsable: 'Juan Pérez',
        fechaEvento: DateTime.now().subtract(const Duration(minutes: 25)),
        descripcion:
            'Granizada de fuerte intensidad durante 20 minutos. Viviendas con daños en techo y pérdida parcial de cultivos de papa.',
        lat: -17.85,
        lon: -65.2,
        fotos: 3,
        videos: 1,
        documentos: 0,
        estado: UgrReporteEstado.pendiente,
      ),
      UgrReporte(
        id: 'mock-rep-2',
        tipoEvento: 'Inundación',
        comunidad: 'Charape',
        municipio: 'Tiquipaya',
        responsable: 'María Condori',
        fechaEvento: DateTime.now().subtract(const Duration(hours: 1)),
        descripcion:
            'Desborde de río afecta viviendas cercanas al cauce. Familias evacuadas preventivamente.',
        lat: -17.32,
        lon: -66.22,
        fotos: 4,
        videos: 2,
        documentos: 1,
        estado: UgrReporteEstado.pendiente,
      ),
      UgrReporte(
        id: 'mock-rep-3',
        tipoEvento: 'Deslizamiento',
        comunidad: 'Villa 14 de Septiembre',
        municipio: 'Cochabamba',
        responsable: 'Rolando Mamani',
        fechaEvento: DateTime.now().subtract(const Duration(hours: 4)),
        descripcion:
            'Deslizamiento de talud bloquea vía secundaria. Sin viviendas afectadas.',
        lat: -17.4,
        lon: -66.15,
        fotos: 2,
        videos: 0,
        documentos: 0,
        estado: UgrReporteEstado.confirmado,
      ),
      UgrReporte(
        id: 'mock-rep-4',
        tipoEvento: 'Helada',
        comunidad: 'Alto Valle',
        municipio: 'Arbieto',
        responsable: 'Lucía Rojas',
        fechaEvento: DateTime.now().subtract(const Duration(days: 1)),
        descripcion:
            'Helada afecta cultivos de maíz y hortalizas en áreas altas.',
        lat: -17.58,
        lon: -66.05,
        fotos: 1,
        videos: 0,
        documentos: 0,
        estado: UgrReporteEstado.confirmado,
      ),
      UgrReporte(
        id: 'mock-rep-5',
        tipoEvento: 'Incendio',
        comunidad: 'Loma Pampa',
        municipio: 'Colomi',
        responsable: 'Pedro Quispe',
        fechaEvento: DateTime.now().subtract(const Duration(days: 2)),
        descripcion:
            'Incendio de pastizales controlado por comunarios y bomberos. Sin víctimas.',
        lat: -17.1,
        lon: -65.7,
        fotos: 3,
        videos: 1,
        documentos: 1,
        estado: UgrReporteEstado.rechazado,
      ),
      UgrReporte(
        id: 'mock-rep-6',
        tipoEvento: 'Vendaval',
        comunidad: 'Tiquirpaya',
        municipio: 'Vinto',
        responsable: 'Ana Gutiérrez',
        fechaEvento: DateTime.now().subtract(const Duration(days: 3)),
        descripcion:
            'Vendaval derribó árboles y dañó techos de 5 viviendas.',
        lat: -17.37,
        lon: -66.33,
        fotos: 2,
        videos: 0,
        documentos: 0,
        estado: UgrReporteEstado.confirmado,
      ),
    ];

List<UgrEdan> mockEdanes() {
  return [
    UgrEdan(
      codigo: 'EDAN-2026-018',
      tipoEvento: 'Incendio',
      comunidad: 'Loma Pampa',
      municipio: 'Colomi',
      fechaCreacion: DateTime.now().subtract(const Duration(hours: 2)),
      estado: UgrEdanEstado.borrador,
      secciones: mockSeccionesEdan(),
      historial: mockHistorialEdan(UgrEdanEstado.borrador),
    ),
    UgrEdan(
      codigo: 'EDAN-2026-015',
      tipoEvento: 'Granizada',
      comunidad: 'San Miguel',
      municipio: 'Sacaba',
      fechaCreacion: DateTime.now().subtract(const Duration(hours: 5)),
      estado: UgrEdanEstado.enEdicion,
      secciones: mockSeccionesEdan(),
      historial: mockHistorialEdan(UgrEdanEstado.enEdicion),
    ),
    UgrEdan(
      codigo: 'EDAN-2026-014',
      tipoEvento: 'Inundación',
      comunidad: 'Charape',
      municipio: 'Tiquipaya',
      fechaCreacion: DateTime.now().subtract(const Duration(days: 1)),
      estado: UgrEdanEstado.firmado,
      secciones: mockSeccionesEdan(),
      historial: mockHistorialEdan(UgrEdanEstado.firmado),
    ),
    UgrEdan(
      codigo: 'EDAN-2026-012',
      tipoEvento: 'Deslizamiento',
      comunidad: 'Villa 14 de Septiembre',
      municipio: 'Cochabamba',
      fechaCreacion: DateTime.now().subtract(const Duration(days: 2)),
      estado: UgrEdanEstado.enviado,
      secciones: mockSeccionesEdan(),
      historial: mockHistorialEdan(UgrEdanEstado.enviado),
    ),
    UgrEdan(
      codigo: 'EDAN-2026-011',
      tipoEvento: 'Helada',
      comunidad: 'Alto Valle',
      municipio: 'Arbieto',
      fechaCreacion: DateTime.now().subtract(const Duration(days: 3)),
      estado: UgrEdanEstado.observado,
      secciones: mockSeccionesEdan(),
      historial: mockHistorialEdan(UgrEdanEstado.observado),
    ),
    UgrEdan(
      codigo: 'EDAN-2026-009',
      tipoEvento: 'Vendaval',
      comunidad: 'Tiquirpaya',
      municipio: 'Vinto',
      fechaCreacion: DateTime.now().subtract(const Duration(days: 5)),
      estado: UgrEdanEstado.aprobado,
      secciones: mockSeccionesEdan(),
      historial: mockHistorialEdan(UgrEdanEstado.aprobado),
    ),
  ];
}

UgrIndicadores mockIndicadores() => const UgrIndicadores(
      reportesNuevos: 2,
      reportesConfirmados: 3,
      edanEnEdicion: 1,
      edanObservados: 1,
      edanEnviados: 1,
    );

List<UgrActividad> mockActividad() => const [
      UgrActividad(
        texto: 'Juan reportó granizada',
        tiempo: 'Hace 10 minutos',
        icon: Icons.warning_amber_rounded,
        color: AppColors.pending,
      ),
      UgrActividad(
        texto: 'Se confirmó inundación en Charape',
        tiempo: 'Hace 1 hora',
        icon: Icons.check_circle,
        color: AppColors.aprobado,
      ),
      UgrActividad(
        texto: 'EDAN 2026-015 observado por la autoridad',
        tiempo: 'Hace 3 horas',
        icon: Icons.feedback,
        color: AppColors.rechazado,
      ),
      UgrActividad(
        texto: 'EDAN 2026-012 enviado a nivel departamental',
        tiempo: 'Ayer',
        icon: Icons.send,
        color: AppColors.enviado,
      ),
    ];

List<UgrSeccion> mockSeccionesEdan() => const [
      UgrSeccion(
        nombre: 'Datos generales',
        descripcion: 'Alcalde, responsable, población afectada',
        icon: Icons.badge_outlined,
        completada: true,
      ),
      UgrSeccion(
        nombre: 'Población y grupo etario',
        descripcion: 'Fallecidos, heridos, desaparecidos por edad',
        icon: Icons.groups_outlined,
        completada: true,
      ),
      UgrSeccion(
        nombre: 'Tipos de evento',
        descripcion: 'Eventos que impactaron la comunidad',
        icon: Icons.warning_amber_rounded,
        completada: true,
      ),
      UgrSeccion(
        nombre: 'Primera respuesta',
        descripcion: 'Búsqueda, salvamento y evacuación',
        icon: Icons.local_fire_department_outlined,
        completada: true,
      ),
      UgrSeccion(
        nombre: 'Salud',
        descripcion: 'Establecimientos de salud y necesidades',
        icon: Icons.local_hospital_outlined,
        completada: false,
      ),
      UgrSeccion(
        nombre: 'Infraestructura vial',
        descripcion: 'Puentes, tramos y vías de acceso',
        icon: Icons.route_outlined,
        completada: true,
      ),
      UgrSeccion(
        nombre: 'Infraestructura pública',
        descripcion: 'Daños en estructuras públicas',
        icon: Icons.apartment_outlined,
        completada: false,
      ),
      UgrSeccion(
        nombre: 'Servicios básicos',
        descripcion: 'Agua, energía, comunicación',
        icon: Icons.water_drop_outlined,
        completada: false,
      ),
      UgrSeccion(
        nombre: 'Educación',
        descripcion: 'Daño en unidades educativas',
        icon: Icons.school_outlined,
        completada: true,
      ),
      UgrSeccion(
        nombre: 'Vivienda',
        descripcion: 'Daños parciales y totales',
        icon: Icons.home_outlined,
        completada: true,
      ),
      UgrSeccion(
        nombre: 'Agricultura',
        descripcion: 'Hectáreas afectadas y perdidas',
        icon: Icons.grain,
        completada: false,
      ),
      UgrSeccion(
        nombre: 'Pecuaria',
        descripcion: 'Animales afectados y muertos',
        icon: Icons.pets_outlined,
        completada: true,
      ),
      UgrSeccion(
        nombre: 'Protección y ayuda humanitaria',
        descripcion: 'Personas protegidas y requerimientos',
        icon: Icons.volunteer_activism_outlined,
        completada: false,
      ),
    ];

List<UgrHistorialEvento> mockHistorialEdan(UgrEdanEstado estado) {
  final eventos = <UgrHistorialEvento>[
    const UgrHistorialEvento(
      titulo: 'Creado',
      fecha: '12/08/2026 08:15',
      usuario: 'Juan Pérez',
      icon: Icons.add_circle,
      color: AppColors.aprobado,
    ),
    const UgrHistorialEvento(
      titulo: 'Editado',
      fecha: '12/08/2026 09:40',
      usuario: 'Juan Pérez',
      icon: Icons.edit,
      color: AppColors.inProgress,
    ),
    const UgrHistorialEvento(
      titulo: 'Firmado',
      fecha: '12/08/2026 11:05',
      usuario: 'Juan Pérez',
      icon: Icons.draw,
      color: AppColors.enRevision,
    ),
    const UgrHistorialEvento(
      titulo: 'Enviado',
      fecha: '12/08/2026 11:30',
      usuario: 'Juan Pérez',
      icon: Icons.send,
      color: AppColors.enviado,
    ),
    const UgrHistorialEvento(
      titulo: 'En revisión',
      fecha: '12/08/2026 15:00',
      usuario: 'Autoridad municipal',
      icon: Icons.visibility,
      color: AppColors.pending,
    ),
    const UgrHistorialEvento(
      titulo: 'Observado',
      fecha: '13/08/2026 08:00',
      usuario: 'Autoridad municipal',
      icon: Icons.feedback,
      color: AppColors.rechazado,
    ),
    const UgrHistorialEvento(
      titulo: 'Aprobado',
      fecha: '14/08/2026 10:20',
      usuario: 'Departamento',
      icon: Icons.verified,
      color: AppColors.aprobado,
    ),
  ];

  final index = switch (estado) {
    UgrEdanEstado.borrador => 0,
    UgrEdanEstado.enEdicion => 1,
    UgrEdanEstado.firmado => 2,
    UgrEdanEstado.enviado => 3,
    UgrEdanEstado.enRevision => 4,
    UgrEdanEstado.observado => 5,
    UgrEdanEstado.aprobado => 6,
  };

  return eventos.sublist(0, index + 1);
}
