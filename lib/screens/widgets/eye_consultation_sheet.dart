import 'package:flutter/material.dart';
import '../../core/recommendation/eye_shape_analyzer.dart';
import '../../core/recommendation/lash_consultation.dart';
import '../../core/theme/app_colors.dart';

class EyeConsultationSheet extends StatefulWidget {
  final EyeAnalysis? analysis;
  final bool needsAdjustment;
  final LashConsultation initial;
  final ValueChanged<LashConsultation> onApply;
  final VoidCallback onReanalyze;

  const EyeConsultationSheet({
    super.key,
    required this.analysis,
    required this.needsAdjustment,
    required this.initial,
    required this.onApply,
    required this.onReanalyze,
  });

  @override
  State<EyeConsultationSheet> createState() => _EyeConsultationSheetState();
}

class _EyeConsultationSheetState extends State<EyeConsultationSheet> {
  late EyeShape? _shape;
  late EyelidType? _eyelid;
  late EyeDepth? _depth;
  late LashGoal _goal;

  @override
  void initState() {
    super.initState();
    _shape = widget.initial.shapeOverride;
    _eyelid = widget.initial.eyelid;
    _depth = widget.initial.depth;
    _goal = widget.initial.goal;
  }

  LashConsultation get _selection => LashConsultation(
    shapeOverride: _shape,
    eyelid: _eyelid,
    depth: _depth,
    goal: _goal,
  );

  @override
  Widget build(BuildContext context) {
    final analysis = widget.analysis;
    final theme = Theme.of(context);
    return FractionallySizedBox(
      heightFactor: .88,
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 16, 12),
              child: Row(
                children: [
                  const Icon(
                    Icons.remove_red_eye_outlined,
                    color: AppColors.actionGreen,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Tu mirada', style: theme.textTheme.titleLarge),
                        Text(
                          _selection.title(analysis),
                          maxLines: 2,
                          style: const TextStyle(
                            color: AppColors.actionGreen,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Cerrar',
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (analysis == null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF2EC),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          widget.needsAdjustment
                              ? 'Ajusta la posición para analizar tu mirada'
                              : 'Mira de frente con los ojos abiertos durante unos 3 segundos.',
                        ),
                      ),
                    if (analysis != null) ...[
                      Text(
                        'Análisis de la mirada',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      LayoutBuilder(
                        builder: (context, constraints) => Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _measurement(
                              'Separación',
                              analysis.separationLabel,
                              constraints.maxWidth,
                            ),
                            _measurement(
                              'Inclinación',
                              analysis.inclinationLabel,
                              constraints.maxWidth,
                            ),
                            _measurement(
                              'Apertura',
                              analysis.symmetryLabel,
                              constraints.maxWidth,
                            ),
                            _measurement(
                              'Forma',
                              (_shape ?? analysis.shape).catalogName,
                              constraints.maxWidth,
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Text(
                      'Resultado deseado',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: LashGoal.values
                          .map(
                            (goal) => ChoiceChip(
                              label: Text(goal.label),
                              selected: _goal == goal,
                              onSelected: (_) => setState(() => _goal = goal),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Ficha de la profesional',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Confirma el párpado y la profundidad para personalizar las sugerencias.',
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<EyelidType>(
                      initialValue: _eyelid,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Párpado',
                        border: OutlineInputBorder(),
                      ),
                      hint: const Text('Seleccionar'),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('Seleccionar'),
                        ),
                        ...EyelidType.values.map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value.label),
                          ),
                        ),
                      ],
                      onChanged: (value) => setState(() => _eyelid = value),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<EyeDepth>(
                      initialValue: _depth,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Profundidad',
                        border: OutlineInputBorder(),
                      ),
                      hint: const Text('Seleccionar'),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('Seleccionar'),
                        ),
                        ...EyeDepth.values.map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value.label),
                          ),
                        ),
                      ],
                      onChanged: (value) => setState(() => _depth = value),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<EyeShape>(
                      initialValue: _shape,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Forma confirmada',
                        border: OutlineInputBorder(),
                      ),
                      hint: const Text('Detección automática'),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('Detección automática'),
                        ),
                        ...const [
                          EyeShape.redondo,
                          EyeShape.almendrado,
                          EyeShape.rasgado,
                        ].map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value.catalogName),
                          ),
                        ),
                      ],
                      onChanged: (value) => setState(() => _shape = value),
                    ),
                    if (analysis != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: const Text('Medidas del análisis'),
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Ancho/alto ${analysis.aspectRatio.toStringAsFixed(2)}\n'
                                'Separación relativa ${analysis.separationRatio.toStringAsFixed(2)}\n'
                                'Inclinación ${analysis.canthalTiltDeg.toStringAsFixed(1)}°\n'
                                'Diferencia de apertura ${(analysis.asymmetry * 100).toStringAsFixed(0)} %',
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFE0E6E1))),
              ),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 12,
                runSpacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: widget.onReanalyze,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Volver a analizar'),
                  ),
                  FilledButton(
                    onPressed: analysis == null && _shape == null
                        ? null
                        : () => widget.onApply(_selection),
                    child: const Text('Aplicar a sugerencias'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _measurement(String label, String value, double availableWidth) =>
      Container(
        width: availableWidth < 300
            ? availableWidth
            : (availableWidth - 10) / 2,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F5F0),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Color(0xFF617467)),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.actionGreen,
              ),
            ),
          ],
        ),
      );
}
