/// Adapted from the user's FlClash-Custom smart country filter. The country
/// is inferred only from node display names; no geolocation claims.
const velaSmartCountries = <String, String>{
  'HK': '🇭🇰 香港',
  'JP': '🇯🇵 日本',
  'SG': '🇸🇬 新加坡',
  'TW': '🇹🇼 台湾',
  'US': '🇺🇸 美国',
  'KR': '🇰🇷 韩国',
  'DE': '🇩🇪 德国',
  'GB': '🇬🇧 英国',
};

bool velaSmartCountryMatches(String name, String country) {
  final patterns = <String, RegExp>{
    'HK': RegExp(r'🇭🇰|香港|Hong\s*Kong|(?:^|[^A-Za-z])HK(?:$|[^A-Za-z])',
        caseSensitive: false),
    'JP': RegExp(r'🇯🇵|日本|Japan|Tokyo|Osaka|(?:^|[^A-Za-z])JP(?:$|[^A-Za-z])',
        caseSensitive: false),
    'SG': RegExp(r'🇸🇬|新加坡|Singapore|(?:^|[^A-Za-z])SG(?:$|[^A-Za-z])',
        caseSensitive: false),
    'TW': RegExp(r'🇹🇼|台湾|臺灣|Taiwan|(?:^|[^A-Za-z])TW(?:$|[^A-Za-z])',
        caseSensitive: false),
    'US': RegExp(r'🇺🇸|美国|美國|United\s*States|America|(?:^|[^A-Za-z])US(?:$|[^A-Za-z])',
        caseSensitive: false),
    'KR': RegExp(r'🇰🇷|韩国|韓國|Korea|Seoul|(?:^|[^A-Za-z])KR(?:$|[^A-Za-z])',
        caseSensitive: false),
    'DE': RegExp(r'🇩🇪|德国|德國|Germany|Frankfurt|(?:^|[^A-Za-z])DE(?:$|[^A-Za-z])',
        caseSensitive: false),
    'GB': RegExp(r'🇬🇧|英国|英國|Britain|London|(?:^|[^A-Za-z])(?:GB|UK)(?:$|[^A-Za-z])',
        caseSensitive: false),
  };
  return patterns[country]?.hasMatch(name) ?? false;
}
