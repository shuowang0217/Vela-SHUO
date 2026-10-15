/// Adaptive real measured byte/second rates for the sailing dashboard.
class VelaVoyageSpeed {
  const VelaVoyageSpeed._();

  static (String, String) format(double? bytesPerSecond) {
    if (bytesPerSecond == null || !bytesPerSecond.isFinite ||
        bytesPerSecond < 0) return ('—', '');
    const units = ['B/s', 'KB/s', 'MB/s', 'GB/s', 'TB/s'];
    var value = bytesPerSecond;
    var step = 0;
    while (value >= 1024 && step < units.length - 1) {
      value /= 1024;
      step++;
    }
    if (step == 0) return (value.round().toString(), units[step]);
    final digits = value < 10 ? 2 : value < 100 ? 1 : 0;
    final raw = value.toStringAsFixed(digits);
    final display = digits > 0
        ? raw.replaceFirst(RegExp(r'\.?0+$'), '') : raw;
    return (display, units[step]);
  }
}
