import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vibration/vibration.dart';

import '../models/cashless_request.dart';
import 'cashless_service.dart';

/// Live state for the Payments tab. Lives as long as the main screen, so the
/// tab badge and the new-request alert work while staff are on other tabs.
///
/// Realtime is used as a "something changed" signal; each change triggers a
/// fresh query, so approved/expired requests always drop out of Pending.
class CashlessController extends ChangeNotifier {
  final CashlessService _service = CashlessService();

  RealtimeChannel? _channel;
  Timer? _pollTimer;
  Timer? _debounce;
  bool _loading = false;
  bool _reloadQueued = false;
  bool _disposed = false;
  Set<String>? _knownPendingIds;

  List<CashlessRequest> pending = const [];
  List<CashlessRequest> history = const [];
  int todayCount = 0;
  double todayTotal = 0;
  bool isLoading = true;
  String? error;
  bool realtimeConnected = false;

  void start() {
    _channel = Supabase.instance.client
        .channel('cashless-requests')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: CashlessService.requestsTable,
          callback: (_) => _scheduleReload(),
        )
        .subscribe((status, [_]) {
          realtimeConnected = status == RealtimeSubscribeStatus.subscribed;
          if (realtimeConnected) _scheduleReload();
          _notify();
        });

    // Fallback if realtime drops, and keeps "x min ago" fresh.
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) => reload());
    reload();
  }

  void _scheduleReload() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), reload);
  }

  Future<void> reload() async {
    if (_loading) {
      _reloadQueued = true;
      return;
    }
    _loading = true;
    try {
      final results = await Future.wait([
        _service.pendingRequests(),
        _service.recentHistory(),
        _service.todaysCompletedTotal(),
      ]);
      if (_disposed) return;
      final newPending = results[0] as List<CashlessRequest>;
      final today = results[2] as ({int count, double total});

      final ids = newPending.map((r) => r.id).toSet();
      final known = _knownPendingIds;
      if (known != null && ids.difference(known).isNotEmpty) {
        _alertNewRequest();
      }
      _knownPendingIds = ids;

      pending = newPending;
      history = results[1] as List<CashlessRequest>;
      todayCount = today.count;
      todayTotal = today.total;
      error = null;
    } catch (e) {
      error = CashlessService.errorMessage(e);
    } finally {
      _loading = false;
      isLoading = false;
      _notify();
    }
    if (_reloadQueued && !_disposed) {
      _reloadQueued = false;
      await reload();
    }
  }

  Future<void> _alertNewRequest() async {
    try {
      FlutterRingtonePlayer().playNotification();
    } catch (_) {}
    try {
      if (await Vibration.hasVibrator()) {
        Vibration.vibrate(pattern: [0, 400, 200, 400]);
      }
    } catch (_) {}
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    _debounce?.cancel();
    final channel = _channel;
    if (channel != null) {
      Supabase.instance.client.removeChannel(channel);
    }
    super.dispose();
  }
}
