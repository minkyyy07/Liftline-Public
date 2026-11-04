import 'package:flutter/material.dart';
import 'athletic_components.dart';
import 'auth/auth_service.dart';
import 'auth/cloud_workout_sync.dart';
import 'db.dart';
import 'theme.dart';

/// Displays clear, distinguished synchronization status for local vs cloud workouts:
/// - pending: "Сохранено локально, ожидает отправки"
/// - syncing: "Синхронизация..."
/// - synced: "Синхронизировано"
/// - error: "Ошибка с повтором" (with retry action)
/// - conflict: "Конфликт правок (сохранено локально)"
class SyncStatusBadge extends StatefulWidget {
  final String workoutId;
  final String syncStatus;
  final String? syncError;
  final VoidCallback? onRetryFinished;

  const SyncStatusBadge({
    super.key,
    required this.workoutId,
    required this.syncStatus,
    this.syncError,
    this.onRetryFinished,
  });

  @override
  State<SyncStatusBadge> createState() => _SyncStatusBadgeState();
}

class _SyncStatusBadgeState extends State<SyncStatusBadge> {
  bool _retrying = false;
  bool _resolving = false;

  Future<void> _resolveKeepLocal() async {
    if (_resolving) return;
    setState(() => _resolving = true);
    try {
      if (AuthService.instance.isAuthenticated && AppDb.instance.isOpen) {
        await CloudWorkoutSync().resolveConflictKeepLocal(AppDb.instance.db, widget.workoutId);
      }
    } finally {
      if (mounted) {
        setState(() => _resolving = false);
        widget.onRetryFinished?.call();
      }
    }
  }

  Future<void> _resolveAcceptServer() async {
    if (_resolving) return;
    setState(() => _resolving = true);
    try {
      if (AuthService.instance.isAuthenticated && AppDb.instance.isOpen) {
        await CloudWorkoutSync().resolveConflictAcceptServer(AppDb.instance.db, widget.workoutId);
      }
    } finally {
      if (mounted) {
        setState(() => _resolving = false);
        widget.onRetryFinished?.call();
      }
    }
  }

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    try {
      if (AuthService.instance.isAuthenticated && AppDb.instance.isOpen) {
        await CloudWorkoutSync().pushWorkout(AppDb.instance.db, widget.workoutId);
      }
    } finally {
      if (mounted) {
        setState(() => _retrying = false);
        widget.onRetryFinished?.call();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!AuthService.instance.isAuthenticated) {
      // In guest mode, all data is purely local
      return const SizedBox.shrink();
    }

    final status = widget.syncStatus.toLowerCase();
    Color badgeColor;
    IconData icon;
    String label;
    bool showRetry = false;

    switch (status) {
      case 'pending':
        badgeColor = const Color(0xFFFFB020);
        icon = Icons.cloud_upload_outlined;
        label = 'Сохранено локально, ожидает отправки';
        break;
      case 'syncing':
        badgeColor = AthleticTokens.electricBlue;
        icon = Icons.sync;
        label = 'Синхронизация...';
        break;
      case 'error':
        badgeColor = LlColors.error;
        icon = Icons.sync_problem_outlined;
        label = widget.syncError != null && widget.syncError!.isNotEmpty
            ? 'Ошибка: ${widget.syncError}'
            : 'Ошибка отправки (повторить)';
        showRetry = true;
        break;
      case 'conflict':
        badgeColor = const Color(0xFFFF7043);
        icon = Icons.warning_amber_rounded;
        label = 'Конфликт правок';
        break;
      case 'synced':
      default:
        badgeColor = const Color(0xFF22C55E);
        icon = Icons.cloud_done_outlined;
        label = 'Синхронизировано';
        break;
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        children: [
          Icon(icon, size: 14, color: badgeColor),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: badgeColor,
            ),
          ),
          if (showRetry)
            InkWell(
              onTap: _retrying ? null : _retry,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  _retrying ? 'Отправка...' : 'Повторить',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AthleticTokens.electricBlue,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
          if (status == 'conflict') ...[
            InkWell(
              onTap: _resolving ? null : _resolveKeepLocal,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  _resolving ? '...' : 'Оставить мою',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AthleticTokens.electricBlue,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
            const Text('•', style: TextStyle(fontSize: 10, color: AthleticTokens.textMuted)),
            InkWell(
              onTap: _resolving ? null : _resolveAcceptServer,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  _resolving ? '...' : 'Принять серверную',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFF7043),
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
