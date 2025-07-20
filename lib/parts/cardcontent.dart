import 'package:flutter/material.dart';

class CardContent extends StatelessWidget {
  final void Function(int index) onCardTap;

  const CardContent({super.key, required this.onCardTap});

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> cardItems = [
      {'title': 'Webmail', 'icon': Icons.mail_outline},
      {'title': 'HRIS', 'icon': Icons.badge_outlined},
      {'title': 'More Apps', 'icon': Icons.apps},
      {'title': 'McAlerts', 'icon': Icons.notifications_active_outlined},
      {'title': 'News & Events', 'icon': Icons.event_note},
      {'title': 'Lunch', 'icon': Icons.restaurant_menu},
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: GridView.builder(
        itemCount: cardItems.length,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
          childAspectRatio: 0.95,
        ),
        itemBuilder: (context, index) {
          final item = cardItems[index];
          return GestureDetector(
            onTap: () => onCardTap(index),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    item['icon'],
                    size: 30,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    item['title'],
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
