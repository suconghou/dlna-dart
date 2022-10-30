import 'package:xml/xml.dart';
import 'dart:math';

enum PlayType {
  Video,
  Image,
  Audio,
}

class DeviceInfo {
  final String URLBase;
  final String deviceType;
  final String friendlyName;
  final List<dynamic> serviceList;
  DeviceInfo(
      this.URLBase, this.deviceType, this.friendlyName, this.serviceList);
}

class PositionParser {
  String TrackDuration = "00:00:00"; // 总时长
  String TrackURI = "";
  String RelTime = "00:00:00"; // 当前播放时间点
  String AbsTime = "00:00:00";

  int get TrackDurationInt {
    return toInt(TrackDuration);
  }

  int get RelTimeInt {
    return toInt(RelTime);
  }

  PositionParser(String text) {
    if (text.isEmpty) {
      return;
    }
    final doc = XmlDocument.parse(text);
    final duration = doc.findAllElements('TrackDuration').first.text;
    final rel = doc.findAllElements('RelTime').first.text;
    final abs = doc.findAllElements('AbsTime').first.text;
    if (duration.isNotEmpty) {
      TrackDuration = duration;
    }
    if (rel.isNotEmpty) {
      RelTime = rel;
    }
    if (abs.isNotEmpty) {
      AbsTime = abs;
    }
    TrackURI = doc.findAllElements('TrackURI').first.text;
  }

  String seek(int n) {
    final total = TrackDurationInt;
    var x = RelTimeInt + n;
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

class VolumeParser {
  int current = 0;
  VolumeParser(String text) {
    final doc = XmlDocument.parse(text);
    String v = doc.findAllElements('CurrentVolume').first.text;
    current = int.parse(v);
  }

  int change(int v) {
    int target = current + v;
    if (target > 100) {
      target = 100;
    }
    if (target < 0) {
      target = 0;
    }
    return target;
  }
}

class TransportInfoParser {
  String CurrentTransportState = '';
  String CurrentTransportStatus = '';
  TransportInfoParser(String text) {
    final doc = XmlDocument.parse(text);
    CurrentTransportState =
        doc.findAllElements('CurrentTransportState').first.text;
    CurrentTransportStatus =
        doc.findAllElements('CurrentTransportStatus').first.text;
  }
}

class MediaInfoParser {
  String MediaDuration = '00:00';
  String CurrentURI = '';
  String NextURI = '';

  int get MediaDurationInt {
    return PositionParser.toInt(MediaDuration);
  }

  MediaInfoParser(String text) {
    final doc = XmlDocument.parse(text);
    MediaDuration = doc.findAllElements('MediaDuration').first.text;
    CurrentURI = doc.findAllElements('CurrentURI').first.text;
    NextURI = doc.findAllElements('NextURI').first.text;
  }
}

class DeviceInfoParser {
  final String text;
  final XmlDocument doc;
  DeviceInfoParser(this.text) : doc = XmlDocument.parse(text);
  DeviceInfo parse(Uri uri) {
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
    return DeviceInfo(URLBase, deviceType, friendlyName, serviceListItems);
  }
}
