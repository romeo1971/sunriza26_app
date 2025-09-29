import 'dart:convert';
import 'package:http/http.dart' as http;

class GeoService {
  GeoService._();

  static const _baseHost = 'nominatim.openstreetmap.org';
  static const _userAgent = 'sunriza-app/1.0 (+https://sunriza.ai)';

  static final Map<String, String?> _postalToCityCache = {};
  static final Map<String, String?> _cityToPostalCache = {};

  static Future<String?> lookupCityForPostal(
    String postal,
    String country,
  ) async {
    final key = '${postal.toLowerCase()}|${country.toLowerCase()}';
    if (_postalToCityCache.containsKey(key)) return _postalToCityCache[key];

    try {
      await Future.delayed(const Duration(milliseconds: 400));
      final uri = Uri.https(_baseHost, '/search', {
        'postalcode': postal,
        'country': country,
        'format': 'json',
        'addressdetails': '1',
        'limit': '1',
      });
      final res = await http.get(uri, headers: {'User-Agent': _userAgent});
      if (res.statusCode != 200) {
        _postalToCityCache[key] = null;
        return null;
      }
      final data = jsonDecode(res.body);
      if (data is List && data.isNotEmpty) {
        final first = data.first;
        final address = first['address'] as Map<String, dynamic>?;
        final city =
            address?['city'] ??
            address?['town'] ??
            address?['village'] ??
            address?['municipality'] ??
            address?['state_district'];
        if (city is String && city.trim().isNotEmpty) {
          _postalToCityCache[key] = city.trim();
          return _postalToCityCache[key];
        }
      }
      _postalToCityCache[key] = null;
      return null;
    } catch (_) {
      _postalToCityCache[key] = null;
      return null;
    }
  }

  static Future<String?> lookupPostalForCity(
    String city,
    String country,
  ) async {
    final key = '${city.toLowerCase()}|${country.toLowerCase()}';
    if (_cityToPostalCache.containsKey(key)) return _cityToPostalCache[key];

    try {
      await Future.delayed(const Duration(milliseconds: 400));
      final uri = Uri.https(_baseHost, '/search', {
        'city': city,
        'country': country,
        'format': 'json',
        'addressdetails': '1',
        'limit': '1',
      });
      final res = await http.get(uri, headers: {'User-Agent': _userAgent});
      if (res.statusCode != 200) {
        _cityToPostalCache[key] = null;
        return null;
      }
      final data = jsonDecode(res.body);
      if (data is List && data.isNotEmpty) {
        final first = data.first;
        final address = first['address'] as Map<String, dynamic>?;
        final postal = address?['postcode'];
        if (postal is String && postal.trim().isNotEmpty) {
          _cityToPostalCache[key] = postal.trim();
          return _cityToPostalCache[key];
        }
      }
      _cityToPostalCache[key] = null;
      return null;
    } catch (_) {
      _cityToPostalCache[key] = null;
      return null;
    }
  }
}
