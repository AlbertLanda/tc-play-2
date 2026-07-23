import '../models/live_category.dart';
import '../models/live_channel.dart';

class SearchCache {
  static List<LiveCategory>? categories;
  static List<LiveChannel>? channels;

  static bool get hasData =>
      categories != null && channels != null;

  static void clear() {
    categories = null;
    channels = null;
  }
}