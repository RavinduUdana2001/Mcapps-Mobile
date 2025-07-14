// home_page.dart
import 'package:flutter/material.dart';
import 'package:mcapps/services/weather_service.dart';

class HomePage extends StatefulWidget {
  final String displayName;

  const HomePage({super.key, required this.displayName});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _temperature = '--';
  String _weather = 'Unknown';

  @override
  void initState() {
    super.initState();
    _loadWeather();
  }

  Future<void> _loadWeather() async {
    final data = await WeatherService.fetchWeather("Colombo"); // You can change city
    if (data != null) {
      setState(() {
        _temperature = "${data['main']['temp'].round()}°C";
        _weather = data['weather'][0]['main']; // e.g., "Clear", "Clouds", etc.
      });
    }
  }

  Icon _getWeatherIcon(String weather) {
    switch (weather.toLowerCase()) {
      case 'clear':
        return const Icon(Icons.wb_sunny, color: Colors.orangeAccent, size: 18);
      case 'clouds':
        return const Icon(Icons.cloud, color: Colors.grey, size: 18);
      case 'rain':
        return const Icon(Icons.beach_access, color: Colors.blueAccent, size: 18);
      case 'snow':
        return const Icon(Icons.ac_unit, color: Colors.lightBlueAccent, size: 18);
      default:
        return const Icon(Icons.cloud_queue, color: Colors.white70, size: 18);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Transparent Card with Weather & Welcome Message
          Card(
            color: Colors.white.withOpacity(0.08),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Stack(
                children: [
                  // Weather (top-right)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Row(
                      children: [
                        _getWeatherIcon(_weather),
                        const SizedBox(width: 4),
                        Text(
                          _temperature,
                          style: const TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      ],
                    ),
                  ),

                  // Welcome message
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.waving_hand_rounded,
                              color: Colors.amberAccent, size: 22),
                          const SizedBox(width: 8),
                          Text(
                            "Welcome, ${widget.displayName}",
                            style: const TextStyle(
                              fontSize: 18,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "This is the official McLarens Group employee app to access alerts, news, events, and lunch selection.",
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white70,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
