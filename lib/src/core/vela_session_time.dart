/// Format a confirmed VPN/proxy session uptime without showing fake timers.
class VelaSessionTime {
  const VelaSessionTime._();

  static String format(Duration? elapsed) {
    if (elapsed == null) return '连接时长 —';
    final seconds = elapsed.inSeconds;
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final remain = seconds % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return '连接时长 ${two(hours)}:${two(minutes)}:${two(remain)}';
  }
}
