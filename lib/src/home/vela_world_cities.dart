import 'package:flutter/material.dart';

import 'demo_connection.dart';

/// Recognizable English map labels; positions are approximate city centers,
/// NOT verified node-server coordinates.
@immutable
class VelaWorldCity {
  const VelaWorldCity(this.label, this.coordinate, this.keywords);
  final String label;
  final Offset coordinate;
  final List<String> keywords;
}

class VelaWorldCityCatalog {
  const VelaWorldCityCatalog._();

  static const cityList = <VelaWorldCity>[
    VelaWorldCity('BEIJING', Offset(116.4, 39.9),
        ['beijing', '北京']),
    VelaWorldCity('SHANGHAI', Offset(121.47, 31.23),
        ['shanghai', '上海']),
    VelaWorldCity('TOKYO', Offset(139.69, 35.68),
        ['tokyo', '东京', '東京']),
    VelaWorldCity('OSAKA', Offset(135.5, 34.69),
        ['osaka', '大阪']),
    VelaWorldCity('HONG KONG', Offset(114.17, 22.32),
        ['hong kong', 'hongkong', '香港', 'hk-']),
    VelaWorldCity('TAIPEI', Offset(121.56, 25.03),
        ['taipei', '台北', '臺北', '台湾', '臺灣', 'tw-']),
    VelaWorldCity('SEOUL', Offset(126.98, 37.57),
        ['seoul', '首尔', '首爾', '韩国', '韓國', 'kr-']),
    VelaWorldCity('SINGAPORE', Offset(103.82, 1.35),
        ['singapore', '新加坡', '狮城', '獅城', 'sg-']),
    VelaWorldCity('LOS ANGELES', Offset(-118.24, 34.05),
        ['los angeles', '洛杉矶', '洛杉磯']),
    VelaWorldCity('NEW YORK', Offset(-74.01, 40.71),
        ['new york', '纽约', '紐約']),
    VelaWorldCity('SAN FRANCISCO', Offset(-122.42, 37.77),
        ['san francisco', '旧金山', '舊金山']),
    VelaWorldCity('LONDON', Offset(-.127, 51.5),
        ['london', '伦敦', '倫敦', '英国', '英國', 'uk-']),
    VelaWorldCity('FRANKFURT', Offset(8.68, 50.11),
        ['frankfurt', '法兰克福', '法蘭克福', '德国', '德國', 'de-']),
    VelaWorldCity('PARIS', Offset(2.35, 48.86),
        ['paris', '巴黎', '法国', '法國', 'fr-']),
    VelaWorldCity('AMSTERDAM', Offset(4.9, 52.37),
        ['amsterdam', '阿姆斯特丹', '荷兰', '荷蘭', 'nl-']),
    VelaWorldCity('SYDNEY', Offset(151.21, -33.86),
        ['sydney', '悉尼', '雪梨']),
    VelaWorldCity('MELBOURNE', Offset(144.96, -37.81),
        ['melbourne', '墨尔本', '墨爾本']),
    VelaWorldCity('TORONTO', Offset(-79.38, 43.65),
        ['toronto', '多伦多', '多倫多']),
  ];

  static const fallbacks = <String, String>{
    'jp': 'TOKYO',
    'sg': 'SINGAPORE',
    'us': 'LOS ANGELES',
    'gb': 'LONDON',
    'de': 'FRANKFURT',
  };

  static VelaWorldCity resolve(String? raw, VelaDemoNode fallback) {
    final input = (raw ?? '').toLowerCase();
    for (final city in cityList) {
      if (city.keywords.any(input.contains)) return city;
    }
    final country = <(String, String)>[
      ('japan', 'TOKYO'), ('日本', 'TOKYO'), ('jp-', 'TOKYO'),
      ('united states', 'LOS ANGELES'), ('美国', 'LOS ANGELES'),
      ('美國', 'LOS ANGELES'), ('usa', 'LOS ANGELES'),
      ('us-', 'LOS ANGELES'),
    ];
    for (final (keyword, label) in country) {
      if (input.contains(keyword)) {
        return cityList.firstWhere((city) => city.label == label);
      }
    }
    final expected = fallbacks[fallback.id] ?? 'BEIJING';
    return cityList.firstWhere((city) => city.label == expected);
  }
}
