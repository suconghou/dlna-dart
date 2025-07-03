# dlna_dart

simple dlna client

## Getting Started

```dart
import 'dart:async';
import 'package:dlna_dart/dlna.dart';

main(List<String> args) async {
  final searcher = DLNAManager();
  final m = await searcher.start();
  m.devices.stream.listen((deviceList) {
    deviceList.forEach((key, value) async {
      print(key);
      if (value.info.friendlyName.contains('Wireless')) return;
      print(value.info.friendlyName);
      print(value.activeTime);
      print('\r\n');
      // final text = await value.position();
      // final r = await value.seekByCurrent(text, 10);
      // print(r);
    });
  });

  // close the server,the closed server can be start by call searcher.start()
  Timer(Duration(seconds: 30), () {
    searcher.stop();
    print('server closed');
  });

  // if you new DLNAManager() many times , you must use start(reusePort:true)
}


```

**python version**

https://github.com/suconghou/dlna-python


**app example**

https://github.com/suconghou/u2flutter
