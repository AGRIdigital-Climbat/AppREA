import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import '../widgets/custom_button.dart';
import '../widgets/custom_text_field.dart';
import '../widgets/status_badge.dart';
import '../widgets/reporte_card.dart';
import '../config/theme.dart';
import 'mock_data.dart';
import 'screen_wrapper.dart';

@Preview(name: 'Button Normal', group: 'CustomButton', wrapper: reaSimpleWrapper)
Widget customButtonNormal() {
  return Padding(
    padding: const EdgeInsets.all(16),
    child: CustomButton(
      text: 'Enviar Reporte',
      onPressed: () {},
      icon: Icons.send,
    ),
  );
}

@Preview(name: 'Button Loading', group: 'CustomButton', wrapper: reaSimpleWrapper)
Widget customButtonLoading() {
  return Padding(
    padding: const EdgeInsets.all(16),
    child: CustomButton(
      text: 'Enviar Reporte',
      onPressed: () {},
      isLoading: true,
      icon: Icons.send,
    ),
  );
}

@Preview(name: 'Button Outlined', group: 'CustomButton', wrapper: reaSimpleWrapper)
Widget customButtonOutlined() {
  return Padding(
    padding: const EdgeInsets.all(16),
    child: CustomButton(
      text: 'Cancelar',
      onPressed: () {},
      isOutlined: true,
    ),
  );
}

@Preview(name: 'TextField Vacio', group: 'CustomTextField', wrapper: reaSimpleWrapper)
Widget customTextFieldEmpty() {
  return const Padding(
    padding: EdgeInsets.all(16),
    child: CustomTextField(
      label: 'Nombre completo',
      hint: 'Ingrese su nombre',
    ),
  );
}

@Preview(name: 'TextField Con Texto', group: 'CustomTextField', wrapper: reaSimpleWrapper)
Widget customTextFieldWithText() {
  return Padding(
    padding: const EdgeInsets.all(16),
    child: CustomTextField(
      label: 'Nombre completo',
      hint: 'Ingrese su nombre',
      controller: TextEditingController(text: 'Carlos Rios'),
    ),
  );
}

@Preview(name: 'StatusBadge Pendiente', group: 'StatusBadge', wrapper: reaSimpleWrapper)
Widget statusBadgePending() {
  return const Padding(
    padding: EdgeInsets.all(16),
    child: StatusBadge(text: 'Pendiente', color: AppColors.pending),
  );
}

@Preview(name: 'StatusBadge Sincronizado', group: 'StatusBadge', wrapper: reaSimpleWrapper)
Widget statusBadgeSynced() {
  return const Padding(
    padding: EdgeInsets.all(16),
    child: StatusBadge(text: 'Sincronizado', color: AppColors.completed),
  );
}

@Preview(name: 'StatusBadge Error', group: 'StatusBadge', wrapper: reaSimpleWrapper)
Widget statusBadgeError() {
  return const Padding(
    padding: EdgeInsets.all(16),
    child: StatusBadge(text: 'Error de sync', color: AppColors.error),
  );
}

@Preview(name: 'ReporteCard Sincronizado', group: 'ReporteCard', wrapper: reaSimpleWrapper)
Widget reporteCardSynced() {
  return ReporteCard(reporte: mockReporteOfflineStats, onTap: () {});
}

@Preview(name: 'ReporteCard Pendiente', group: 'ReporteCard', wrapper: reaSimpleWrapper)
Widget reporteCardPending() {
  return ReporteCard(reporte: mockReporteOfflinePendiente, onTap: () {});
}

@Preview(name: 'ReporteCard Error', group: 'ReporteCard', wrapper: reaSimpleWrapper)
Widget reporteCardError() {
  return ReporteCard(reporte: mockReporteOfflineError, onTap: () {});
}
