import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';

import 'vela_exit_ip_monitor.dart';

/// Render bundled vector flag artwork, because Windows displays Unicode
/// national-flag emoji as two letters (JP/US).
class VelaExitIpIndicator extends StatelessWidget {
  const VelaExitIpIndicator({
    super.key,
    required this.info,
    required this.statusText,
    required this.accentColor,
    required this.mutedColor,
  });

  final VelaExitIpInfo? info;
  final String statusText;
  final Color accentColor;
  final Color mutedColor;

  @override
  Widget build(BuildContext context) {
    const fontSize = 10.5;
    final details = info;
    if (details == null) {
      return Text(statusText,
        maxLines: 1, overflow: TextOverflow.ellipsis,
        style: TextStyle(color: mutedColor, fontSize: fontSize,
          fontWeight: FontWeight.w600));
    }
    return Semantics(
      label: '出口 ' + details.countryCode + ' ' + details.address,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CountryFlag.fromCountryCode(
            details.countryCode,
            key: const ValueKey('vela_exit_country_flag'),
            theme: const ImageTheme(
              width: 17, height: 12,
              shape: RoundedRectangle(2),
            ),
          ),
          const SizedBox(width: 5),
          Flexible(child: Text(
            details.address,
            key: const ValueKey('vela_exit_ip_address'),
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: accentColor, fontSize: fontSize,
              fontWeight: FontWeight.w600),
          )),
        ],
      ),
    );
  }
}
