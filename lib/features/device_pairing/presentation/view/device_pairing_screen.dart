import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fitness_os/core/di/injector.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/device_pairing/domain/repositories/device_pairing_repository.dart';
import 'package:fitness_os/features/device_pairing/presentation/bloc/device_pairing_bloc.dart';
import 'package:fitness_os/features/device_pairing/presentation/bloc/device_pairing_event.dart';
import 'package:fitness_os/features/device_pairing/presentation/bloc/device_pairing_state.dart';

class DevicePairingScreen extends StatelessWidget {
  const DevicePairingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<DevicePairingBloc>()..add(const DevicePairingStarted()),
      child: const _DevicePairingView(),
    );
  }
}

class _DevicePairingView extends StatefulWidget {
  const _DevicePairingView();

  @override
  State<_DevicePairingView> createState() => _DevicePairingViewState();
}

class _DevicePairingViewState extends State<_DevicePairingView> {
  final _authKeyController = TextEditingController();

  @override
  void dispose() {
    _authKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GT5 pairing'),
        actions: [
          TextButton(
            onPressed: () => context
                .read<DevicePairingBloc>()
                .add(const DevicePairingForgetRequested()),
            child: const Text('Forget'),
          ),
        ],
      ),
      body: BlocBuilder<DevicePairingBloc, DevicePairingState>(
        builder: (context, state) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _StatusCard(state: state),
              const SizedBox(height: 16),
              if (state.remembered != null) ...[
                Text(
                  'Remembered: ${state.remembered!.name}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  _redactMac(state.remembered!.mac),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
              ],
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton(
                    onPressed: () => context
                        .read<DevicePairingBloc>()
                        .add(const DevicePairingScanRequested()),
                    child: const Text('Scan GT5'),
                  ),
                  OutlinedButton(
                    onPressed: () => context
                        .read<DevicePairingBloc>()
                        .add(const DevicePairingStopScanRequested()),
                    child: const Text('Stop scan'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (state.devices.isEmpty &&
                  state.linkState == LinkState.scanning)
                const Text('Scanning for HUAWEI Watch GT 5…'),
              if (state.devices.isEmpty &&
                  state.linkState == LinkState.disconnected &&
                  state.remembered == null)
                const Text(
                  'No devices yet. Force-stop Huawei Health and Gadgetbridge, then Scan.',
                ),
              ...state.devices.map(
                (d) => ListTile(
                  title: Text(d.name),
                  subtitle: Text(_redactMac(d.mac)),
                  trailing: const Icon(Icons.link),
                  onTap: () => context.read<DevicePairingBloc>().add(
                        DevicePairingSelectDevice(mac: d.mac, name: d.name),
                      ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Auth key (17-digit Huawei userId)',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _authKeyController,
                obscureText: state.authKeyMasked,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: state.authKeyMasked
                      ? '•••••••••••••••••'
                      : 'Optional — R11 recovery',
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonal(
                  onPressed: () {
                    context.read<DevicePairingBloc>().add(
                          DevicePairingAuthKeySubmitted(
                            _authKeyController.text,
                          ),
                        );
                    _authKeyController.clear();
                  },
                  child: const Text('Save auth key'),
                ),
              ),
              if (state.linkState == LinkState.authFailed) ...[
                const SizedBox(height: 16),
                Text(
                  'R11 recovery',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Text(
                  '1) Force-stop Health  2) Enter account userId  3) Factory reset if needed',
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    ActionChip(
                      label: const Text('Won: account ID'),
                      onPressed: () => context.read<DevicePairingBloc>().add(
                            const DevicePairingR11Recorded('account_id'),
                          ),
                    ),
                    ActionChip(
                      label: const Text('Won: factory reset'),
                      onPressed: () => context.read<DevicePairingBloc>().add(
                            const DevicePairingR11Recorded('factory_reset'),
                          ),
                    ),
                    ActionChip(
                      label: const Text('Won: no-vendor pair'),
                      onPressed: () => context.read<DevicePairingBloc>().add(
                            const DevicePairingR11Recorded('no_vendor_pair'),
                          ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              Text(
                'Gate A interrupt checklist',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              const Text(
                'Credit only after that interrupt reached authenticated session.',
              ),
              CheckboxListTile(
                value: state.gateA.killOk,
                onChanged: (_) => context.read<DevicePairingBloc>().add(
                      const DevicePairingCreditInterrupt(GateAInterrupt.kill),
                    ),
                title: const Text('App kill → reopen reconnect OK'),
              ),
              CheckboxListTile(
                value: state.gateA.rebootOk,
                onChanged: (_) => context.read<DevicePairingBloc>().add(
                      const DevicePairingCreditInterrupt(GateAInterrupt.reboot),
                    ),
                title: const Text('Phone reboot → open app reconnect OK'),
              ),
              CheckboxListTile(
                value: state.gateA.btToggleOk,
                onChanged: (_) => context.read<DevicePairingBloc>().add(
                      const DevicePairingCreditInterrupt(
                        GateAInterrupt.btToggle,
                      ),
                    ),
                title: const Text('Bluetooth toggle reconnect OK'),
              ),
              Text(
                state.gateA.passed
                    ? 'Gate A PASSED — sync remains Phase 2 (U7)'
                    : 'Gate A incomplete — Sync blocked',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: state.gateA.passed
                      ? Colors.green.shade700
                      : Colors.orange.shade800,
                ),
              ),
              if (state.message != null) ...[
                const SizedBox(height: 16),
                Text(
                  state.message!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  String _redactMac(String mac) {
    final parts = mac.split(':');
    if (parts.length < 3) return '••:••:••';
    return '••:••:••:${parts.sublist(parts.length - 3).join(':')}';
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.state});
  final DevicePairingState state;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(_label(state.linkState)),
        subtitle: Text(
          [
            if (state.recoveryHint != null) 'Next: ${state.recoveryHint}',
            'No Sync button in Phase 1 (AE5)',
          ].join('\n'),
        ),
        leading: Icon(_icon(state.linkState)),
      ),
    );
  }

  String _label(LinkState s) => switch (s) {
        LinkState.disconnected => 'Disconnected',
        LinkState.permissionRequired => 'Permission required',
        LinkState.scanning => 'Scanning',
        LinkState.connecting => 'Connecting',
        LinkState.authenticating => 'Authenticating',
        LinkState.authFailed => 'Auth failed',
        LinkState.bondRequired => 'Bond required',
        LinkState.reconnectFailed => 'Reconnect failed',
        LinkState.gateAIncomplete => 'Session ready — Gate A incomplete',
        LinkState.connected => 'Connected (Gate A passed)',
      };

  IconData _icon(LinkState s) => switch (s) {
        LinkState.connected => Icons.check_circle,
        LinkState.gateAIncomplete => Icons.verified_user,
        LinkState.authFailed ||
        LinkState.reconnectFailed =>
          Icons.error_outline,
        LinkState.scanning ||
        LinkState.connecting ||
        LinkState.authenticating =>
          Icons.sync,
        _ => Icons.bluetooth,
      };
}
