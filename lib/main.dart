import 'package:flutter/material.dart';
import 'package:vela_shuo/src/app.dart';
import 'package:vela_shuo/src/settings/settings_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = SettingsController();
  await settings.load();
  runApp(VelaShuoApp(settings: settings));
}
