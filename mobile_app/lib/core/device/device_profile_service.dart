import 'package:shared_preferences/shared_preferences.dart';

import 'device_profile.dart';

class DeviceProfileService {
  DeviceProfileService._();

  static const String _profileKey = 'tcplay_device_profile';

  static Future<DeviceProfile?> getSavedProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_profileKey);

    switch (value) {
      case 'mobile':
        return DeviceProfile.mobile;

      case 'tv':
        return DeviceProfile.tv;

      default:
        return null;
    }
  }

  static Future<void> saveProfile(DeviceProfile profile) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      _profileKey,
      profile.name,
    );
  }

  static Future<void> clearProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_profileKey);
  }
}