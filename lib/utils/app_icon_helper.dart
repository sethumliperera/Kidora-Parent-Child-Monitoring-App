import 'package:flutter/material.dart';

class AppIconHelper {
  static Widget getAppIcon(String packageName, String appName, {double size = 48}) {
    final name = appName.toLowerCase();
    IconData iconData;
    Color iconColor;

    if (name.contains('youtube') || name.contains('video')) {
      iconData = Icons.play_circle_fill_rounded;
      iconColor = Colors.red;
    } else if (name.contains('chrome') || name.contains('browser')) {
      iconData = Icons.language_rounded;
      iconColor = Colors.blue;
    } else if (name.contains('facebook') || name.contains('meta')) {
      iconData = Icons.facebook_rounded;
      iconColor = const Color(0xFF1877F2);
    } else if (name.contains('instagram')) {
      iconData = Icons.camera_alt_rounded;
      iconColor = Colors.pink;
    } else if (name.contains('snap')) {
      iconData = Icons.camera_rounded;
      iconColor = Colors.yellow[700]!;
    } else if (name.contains('tiktok') || name.contains('tik')) {
      iconData = Icons.music_note_rounded;
      iconColor = Colors.black;
    } else if (name.contains('game') || name.contains('play')) {
      iconData = Icons.videogame_asset_rounded;
      iconColor = Colors.green;
    } else if (name.contains('whatsapp') || name.contains('message')) {
      iconData = Icons.chat_bubble_rounded;
      iconColor = Colors.green;
    } else if (name.contains('gmail') || name.contains('mail')) {
      iconData = Icons.email_rounded;
      iconColor = Colors.redAccent;
    } else if (name.contains('maps') || name.contains('navigation')) {
      iconData = Icons.map_rounded;
      iconColor = Colors.green;
    } else if (name.contains('shop') || name.contains('store')) {
      iconData = Icons.shopping_bag_rounded;
      iconColor = Colors.orange;
    } else if (name.contains('music') || name.contains('spotify')) {
      iconData = Icons.headphones_rounded;
      iconColor = Colors.greenAccent;
    } else {
      iconData = Icons.apps_rounded;
      iconColor = Colors.grey;
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Icon(iconData, color: iconColor, size: size * 0.55),
    );
  }
}
