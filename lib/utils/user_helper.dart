import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class UserHelper {
  // Get the currently logged-in user data
  static Future<Map<String, dynamic>?> getLoggedInUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userStr = prefs.getString('logged_in_user');

    if (userStr != null) {
      try {
        return json.decode(userStr) as Map<String, dynamic>;
      } catch (e) {
        return null;
      }
    }
    return null;
  }

  // Get the logged-in user ID
  static Future<int?> getLoggedInUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('logged_in_user_id');
  }

  // Get the logged-in user's first name
  static Future<String?> getLoggedInUserName() async {
    final prefs = await SharedPreferences.getInstance();
    final String first = prefs.getString('logged_in_user_fname') ?? '';
    final String last = prefs.getString('logged_in_user_lname') ?? '';
    final full = ('$first $last').trim();
    return full.isEmpty ? null : full;
  }

  // Clear logged-in user data (for logout)
  static Future<void> clearLoggedInUser() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('logged_in_user');
    await prefs.remove('logged_in_user_id');
    await prefs.remove('logged_in_user_fname');
  }
}
