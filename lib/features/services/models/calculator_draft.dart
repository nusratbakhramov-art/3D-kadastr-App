enum CalculatorTab {
  arxitektura('Arxitektura'),
  dizayn('Dizayn'),
  qurilish('Qurilish');

  const CalculatorTab(this.label);
  final String label;
}

enum CalculatorStyle {
  minimalizm('Minimalizm'),
  klassika('Klassika'),
  modern('Modern');

  const CalculatorStyle(this.label);
  final String label;
}

class CalculatorDraft {
  const CalculatorDraft({
    required this.tab,
    required this.landSotix,
    required this.buildingM2,
    required this.floors,
    required this.residents,
    required this.style,
  });

  final CalculatorTab tab;
  final double landSotix;
  final double buildingM2;
  final int floors;
  final int residents;
  final CalculatorStyle style;
}
