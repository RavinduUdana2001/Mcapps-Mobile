import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'message_detail_page.dart';

class MessagesPage extends StatefulWidget {
  const MessagesPage({super.key});

  @override
  _MessagesPageState createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  final DatabaseReference _messagesRef = FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL: 'https://mcapps-6e40e-default-rtdb.asia-southeast1.firebasedatabase.app',
  ).ref().child('messages');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E3C72),
      body: SafeArea(
        child: StreamBuilder<DatabaseEvent>(
          stream: _messagesRef.orderByChild('timestamp').onValue,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: Colors.white));
            }

            if (snapshot.hasError) {
              return Center(
                child: Text(
                  'Error loading alerts: ${snapshot.error}',
                  style: const TextStyle(color: Colors.red),
                ),
              );
            }

            final raw = snapshot.data?.snapshot.value;

            if (raw == null || raw is! Map) {
              return const Center(
                child: Text('No alerts available.', style: TextStyle(color: Colors.white70, fontSize: 18)),
              );
            }

            final data = raw;
            final messages = data.entries.map((entry) {
              final msg = entry.value as Map<dynamic, dynamic>;
              return {
                'title': msg['title'] ?? '',
                'message': msg['message'] ?? '',
                'timestamp': msg['timestamp'] ?? 0,
              };
            }).toList()
              ..sort((a, b) => b['timestamp'].compareTo(a['timestamp']));

            return Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'McAlerts',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      final date = DateTime.fromMillisecondsSinceEpoch((msg['timestamp'] ?? 0) * 1000);
                      final formatted = DateFormat('MMM d, yyyy – hh:mm a').format(date);

                      return GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => MessageDetailPage(
                                title: msg['title'],
                                message: msg['message'],
                                timestamp: formatted,
                              ),
                            ),
                          );
                        },
                        child: Card(
                          color: Colors.white.withOpacity(0.08),
                          elevation: 2,
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.notifications, color: Colors.white70),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        msg['title'],
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        msg['message'],
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        formatted,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.white38,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
