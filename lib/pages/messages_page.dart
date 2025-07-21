import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';

class MessagesPage extends StatefulWidget {
  @override
  _MessagesPageState createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  final DatabaseReference _messagesRef = FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL:
        'https://mcapps-6e40e-default-rtdb.asia-southeast1.firebasedatabase.app',
  ).ref().child('messages');

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1E3C72), Color(0xFF2A5298)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        child: StreamBuilder<DatabaseEvent>(
          stream: _messagesRef.orderByChild('timestamp').onValue,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: Colors.white),
              );
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
                child: Text(
                  'No alerts available.',
                  style: TextStyle(color: Colors.white70, fontSize: 18),
                ),
              );
            }

            final data = raw as Map<dynamic, dynamic>;

            final messages =
                data.entries.map((entry) {
                    final msg = entry.value as Map<dynamic, dynamic>;
                    return {
                      'title': msg['title'] ?? '',
                      'message': msg['message'] ?? '',
                      'timestamp': msg['timestamp'] ?? 0,
                    };
                  }).toList()
                  ..sort((a, b) => b['timestamp'].compareTo(a['timestamp']));

            if (messages.isEmpty) {
              return const Center(
                child: Text(
                  'No alerts available.',
                  style: TextStyle(color: Colors.white70, fontSize: 18),
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 20, 12, 12),
              itemCount: messages.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        'McAlerts',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                          shadows: [
                            Shadow(
                              color: Colors.black45,
                              blurRadius: 4,
                              offset: Offset(1, 1),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }

                final msg = messages[index - 1];
                final date = DateTime.fromMillisecondsSinceEpoch(
                  (msg['timestamp'] ?? 0) * 1000,
                );
                final formatted = DateFormat(
                  'yyyy-MM-dd – hh:mm a',
                ).format(date);

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white30),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(right: 10),
                          child: Icon(
                            Icons.notifications,
                            color: Colors.white70,
                            size: 26,
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                msg['title'],
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                msg['message'],
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                formatted,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.white54,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
