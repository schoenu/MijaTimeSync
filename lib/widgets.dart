import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

class ScanResultTile extends StatelessWidget {
  const ScanResultTile({
    required this.device,
    required this.onTap,
    super.key,
  });

  final DiscoveredDevice device;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.watch),
      title: Text(device.name.isEmpty ? 'Unknown BLE device' : device.name),
      subtitle: Text(device.id, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Text('${device.rssi} dBm'),
      onTap: onTap,
    );
  }
}
