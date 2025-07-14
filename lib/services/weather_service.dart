// weather_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class WeatherService {
  static const String _apiKey = '3222bbdb39f967da86d6873a58b25b9d'; // replace this!
  static const String _baseUrl = 'https://api.openweathermap.org/data/2.5/weather';

  static Future<Map<String, dynamic>?> fetchWeather(String city) async {
    final url = '$_baseUrl?q=$city&units=metric&appid=$_apiKey';

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        print('❌ Weather fetch failed: ${response.body}');
        return null;
      }
    } catch (e) {
      print('❌ Weather exception: $e');
      return null;
    }
  }
}
