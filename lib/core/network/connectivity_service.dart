import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Connectivity monitor.
///
/// `connectivity_plus` changed its stream/return shape between major versions
/// (single `ConnectivityResult` → `List<ConnectivityResult>`). Parsing is done
/// through `dynamic` so the app compiles and runs correctly on either version —
/// the app only ever cares about "is there any usable transport".
class ConnectivityService {
  ConnectivityService({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  Stream<bool> get onStatusChanged =>
      _connectivity.onConnectivityChanged.map(_parse).distinct();

  Future<bool> checkOnline() async {
    try {
      final dynamic result = await _connectivity.checkConnectivity();
      return _parse(result);
    } catch (_) {
      // If the platform channel is unavailable, assume online and let the
      // HTTP layer report the real problem.
      return true;
    }
  }

  bool _parse(dynamic result) {
    if (result == null) return true;
    if (result is List) {
      if (result.isEmpty) return false;
      return result.any(_isUsableTransport);
    }
    return _isUsableTransport(result);
  }

  bool _isUsableTransport(dynamic entry) {
    final String value = entry.toString();
    // ConnectivityResult.none.toString() => "ConnectivityResult.none"
    return !value.endsWith('.none');
  }
}
