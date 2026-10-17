/// Human-facing sailing status for the shared Windows / Android connect card.
///
/// A node name is not a verified geolocation or a real seaport. "抵达港口" is
/// a visual voyage metaphor; the exact selected node remains visible below.
class VelaVoyageConnectionLabel {
  const VelaVoyageConnectionLabel._();

  static String headline({
    required bool connected,
    required bool busy,
    String? airportName,
  }) {
    if (busy) return '正在起航';
    if (!connected) return '未起航';
    final clean = airportName?.trim() ?? '';
    final airport = clean.isEmpty ? 'Vela' : clean;
    return '$airport · 抵达港口';
  }
}
