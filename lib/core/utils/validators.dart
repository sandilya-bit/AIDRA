/// Field validators shared by the auth and report forms.
abstract final class Validators {
  static final RegExp _email = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]{2,}$');
  static final RegExp _e164 = RegExp(r'^\+?[0-9]{7,15}$');

  /// Accepts an email OR a phone number (login screen uses one field).
  static String? emailOrPhone(String? value) {
    final String input = (value ?? '').trim();
    if (input.isEmpty) return 'Enter your email or phone number';
    if (_email.hasMatch(input)) return null;
    final String digits = input.replaceAll(RegExp(r'[\s()-]'), '');
    if (_e164.hasMatch(digits)) return null;
    return 'Enter a valid email or phone number';
  }

  static String? email(String? value) {
    final String input = (value ?? '').trim();
    if (input.isEmpty) return 'Enter your email';
    return _email.hasMatch(input) ? null : 'Enter a valid email address';
  }

  static String? phone(String? value) {
    final String input = (value ?? '').trim().replaceAll(RegExp(r'[\s()-]'), '');
    if (input.isEmpty) return 'Enter your phone number';
    return _e164.hasMatch(input) ? null : 'Enter a valid phone number';
  }

  static String? password(String? value) {
    final String input = value ?? '';
    if (input.isEmpty) return 'Enter your password';
    if (input.length < 8) return 'Use at least 8 characters';
    return null;
  }

  static String? required(String? value, {String label = 'This field'}) {
    if ((value ?? '').trim().isEmpty) return '$label is required';
    return null;
  }

  static String? fullName(String? value) {
    final String input = (value ?? '').trim();
    if (input.isEmpty) return 'Enter your full name';
    if (input.length < 3) return 'Name is too short';
    return null;
  }

  /// Report descriptions must be actionable but stay within the API limit.
  static const int maxReportLength = 500;

  static String? reportDescription(String? value) {
    final String input = (value ?? '').trim();
    if (input.isEmpty) return 'Describe what is happening';
    if (input.length < 8) return 'Add a little more detail';
    if (input.length > maxReportLength) {
      return 'Keep it under $maxReportLength characters';
    }
    return null;
  }
}
