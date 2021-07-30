import 'package:xml/xml.dart';
import 'dart:math';

class deviceInfo {
  final String URLBase;
  final String deviceType;
  final String friendlyName;
  final List<dynamic> serviceList;
  deviceInfo(
      this.URLBase, this.deviceType, this.friendlyName, this.serviceList);
}

class positionParser {
  String TrackDuration = "00:00:00";
  String TrackURI = "";
  String RelTime = "00:00:00";
  String AbsTime = "00:00:00";

  positionParser(String text) {
    var doc = XmlDocument.parse(text);
    TrackDuration = doc.findAllElements('TrackDuration').first.text;
    TrackURI = doc.findAllElements('TrackURI').first.text;
    RelTime = doc.findAllElements('RelTime').first.text;
    AbsTime = doc.findAllElements('AbsTime').first.text;
  }

  String seek(int n) {
    final total = toInt(TrackDuration);
    var x = toInt(RelTime) + n;
    if (x > total) {
      x = total;
    } else if (x < 0) {
      x = 0;
    }
    return toStr(x);
  }

  static int toInt(String str) {
    final arr = str.split(':');
    var sum = 0;
    for (var i = 0; i < arr.length; i++) {
      sum += int.parse(arr[i]) * (pow(60, arr.length - i - 1) as int);
    }
    return sum;
  }

  static String toStr(int time) {
    final h = (time / 3600).floor();
    final m = ((time - 3600 * h) / 60).floor();
    final s = time - 3600 * h - 60 * m;
    final str = "${z(h)}:${z(m)}:${z(s)}";
    return str;
  }

  static String z(int n) {
    if (n > 9) {
      return n.toString();
    }
    return "0$n";
  }
}

class xmlParser {
  final String text;
  final XmlDocument doc;
  xmlParser(this.text) : doc = XmlDocument.parse(text);
  deviceInfo parse(Uri uri) {
    String URLBase = "";
    try {
      URLBase = doc.findAllElements('URLBase').first.text;
    } catch (e) {
      URLBase = uri.origin;
    }
    final deviceType = doc.findAllElements('deviceType').first.text;
    final friendlyName = doc.findAllElements('friendlyName').first.text;
    final serviceList =
        doc.findAllElements('serviceList').first.findAllElements('service');
    final serviceListItems = [];
    for (final service in serviceList) {
      final serviceType = service.findElements('serviceType').first.text;
      final serviceId = service.findElements('serviceId').first.text;
      final controlURL = service.findElements('controlURL').first.text;
      serviceListItems.add({
        "serviceType": serviceType,
        "serviceId": serviceId,
        "controlURL": controlURL,
      });
    }
    return deviceInfo(URLBase, deviceType, friendlyName, serviceListItems);
  }
}
