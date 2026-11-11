import 'dart:io';

import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'contracts.dart';

class AndroidDeviceService implements DeviceService {
  @override
  Future<void> copy(String text) =>
      Clipboard.setData(ClipboardData(text: text));
  @override
  Future<void> shareText(String text) async {
    await SharePlus.instance.share(ShareParams(text: text));
  }

  @override
  Future<void> shareFile(File file) async {
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
  }
}
