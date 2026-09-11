import 'package:core_models/core_models.dart';
import 'package:core_networking/core_networking.dart';
import 'package:core_profile/core_profile.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../screens/wake_on_lan_screen.dart';
import '../dashboard_widget_card.dart';
import '../dashboard_widget_kind.dart';

/// Wakes the machines on the active profile without a detour into settings.
///
/// Issue #151: waking something was buried behind the settings screen, which
/// is a long way to go for a button you press when a server is asleep. The
/// devices themselves still live on the profile and are managed there; this is
/// only a shortcut to firing at them.
class DashboardWakeOnLanWidget extends ConsumerStatefulWidget {
  const DashboardWakeOnLanWidget({super.key});

  @override
  ConsumerState<DashboardWakeOnLanWidget> createState() =>
      _DashboardWakeOnLanWidgetState();
}

class _DashboardWakeOnLanWidgetState
    extends ConsumerState<DashboardWakeOnLanWidget> {
  /// The device a packet is in flight for, so only that row shows a spinner.
  String? _sendingId;

  Future<void> _wake(WolDevice device) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    setState(() => _sendingId = device.id);
    try {
      await sendWol(
        mac: device.mac,
        broadcastAddress: device.broadcastAddress,
        port: device.port,
      );
      if (!mounted) return;
      // A magic packet is fire and forget: nothing answers it, and the machine
      // takes a while to come up. Saying "sent" is the honest claim; saying
      // "woken" would be a promise this cannot keep.
      messenger.showSnackBar(
        SnackBar(content: Text('Magic packet sent to ${device.name}')),
      );
    } on Object {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not reach the network for '
            '${device.name}')),
      );
    } finally {
      if (mounted) setState(() => _sendingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final List<WolDevice> devices =
        ref.watch(activeProfileProvider)?.wolDevices ?? const <WolDevice>[];

    return DashboardWidgetCard(
      kind: DashboardWidgetKind.wakeOnLan,
      accent: cs.primary,
      // Managing devices stays where it was; this only shortcuts to it.
      onTap: () => pushScreen<void>(context, const WakeOnLanScreen()),
      child: devices.isEmpty
          ? const DashboardIdleRow(text: 'No devices yet')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (final WolDevice d in devices.take(4))
                  _WakeRow(
                    device: d,
                    sending: _sendingId == d.id,
                    // One packet at a time keeps the spinner honest about
                    // which row it belongs to.
                    onWake: _sendingId == null ? () => _wake(d) : null,
                  ),
                if (devices.length > 4)
                  DashboardIdleRow(text: '+${devices.length - 4} more'),
              ],
            ),
    );
  }
}

class _WakeRow extends StatelessWidget {
  const _WakeRow({
    required this.device,
    required this.sending,
    required this.onWake,
  });

  final WolDevice device;
  final bool sending;
  final VoidCallback? onWake;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Insets.xxs),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  device.name,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  device.mac,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: Insets.sm),
          if (sending)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: Insets.sm),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            FilledButton.tonalIcon(
              onPressed: onWake,
              icon: const Icon(Icons.power_settings_new_rounded, size: 18),
              label: const Text('Wake'),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
    );
  }
}
