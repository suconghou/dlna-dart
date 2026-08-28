import 'dart:async';
import '../lib/dlna.dart';

void main(List<String> args) async {
  final searcher = DLNAManager();
  final m = await searcher.start();
  m.devices.stream.listen((deviceList) {
    deviceList.forEach((key, value) {
      print(key);
      if (value.info.friendlyName.contains('Wireless')) return;
      print(value.info.friendlyName);
      print(value.activeTime);
      print('\r\n');
    });
  });

  Timer(Duration(seconds: 30), () {
    searcher.stop();
    print('server closed');
  });
}
