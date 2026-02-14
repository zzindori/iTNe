import 'dart:io';

import '../config/app_strings.dart';

class CapturedPhoto {
  final String id;
  final File file;
  final DateTime capturedAt;
  bool isSaved;

  CapturedPhoto({
    required this.id,
    required this.file,
    required this.capturedAt,
    this.isSaved = false,
  });

  String get displayTime {
    final strings = AppStrings.instance;
    final now = DateTime.now();
    final diff = now.difference(capturedAt);
    
    if (diff.inMinutes < 1) return strings.timeJustNow;
    if (diff.inHours < 1) return strings.timeMinutesAgo(diff.inMinutes);
    if (diff.inDays < 1) return strings.timeHoursAgo(diff.inHours);
    return strings.timeDaysAgo(diff.inDays);
  }
}
