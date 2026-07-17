/// Pref keys owned by Dart (identity + Gate A). Secrets stay native-only.
abstract final class GateAPrefs {
  static const rememberedMac = 'remembered_mac';
  static const rememberedName = 'remembered_name';
  static const gateAKillOk = 'gate_a_kill_ok';
  static const gateARebootOk = 'gate_a_reboot_ok';
  static const gateABtToggleOk = 'gate_a_bt_toggle_ok';
  static const gateAPassed = 'gate_a_passed';
  static const lastSyncCursor = 'last_sync_cursor';
  static const lastR11Path = 'last_r11_winning_path';
}
