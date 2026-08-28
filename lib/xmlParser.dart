import 'package:xml/xml.dart';

abstract class PlayType {
  String get protocolInfo;
}

enum MediaMime implements PlayType {
  none('');

  @override
  final String protocolInfo;
  const MediaMime(this.protocolInfo);
}

enum VideoMime implements PlayType {
  mpeg('http-get:*:video/mpeg:*'),
  mp4('http-get:*:video/mp4:*'),
  xMatroska('http-get:*:video/x-matroska:*'),
  quicktime('http-get:*:video/quicktime:*'),
  xMsWmv('http-get:*:video/x-ms-wmv:*'),
  avi('http-get:*:video/avi:*'),
  flv('http-get:*:video/flv:*'),
  ts('http-get:*:video/mp2t:*'),
  hls('http-get:*:application/vnd.apple.mpegurl:*'),
  any('http-get:*:*:*');

  @override
  final String protocolInfo;
  const VideoMime(this.protocolInfo);
}

enum AudioMime implements PlayType {
  mp3('http-get:*:audio/mp3:*'),
  mp4('http-get:*:audio/mp4:*'),
  mpeg('http-get:*:audio/mpeg:*'),
  xFlac('http-get:*:audio/x-flac:*'),
  mpegurl('http-get:*:audio/mpegurl:*'),
  wav('http-get:*:audio/wav:*'),
  wma('http-get:*:audio/wma:*'),
  xMatroska('http-get:*:audio/x-matroska:*'),
  xApe('http-get:*:audio/x-ape:*'),
  any('http-get:*:*:*');

  @override
  final String protocolInfo;
  const AudioMime(this.protocolInfo);
}

enum ImageMime implements PlayType {
  jpeg('http-get:*:image/jpeg:*'),
  png('http-get:*:image/png:*'),
  tiff('http-get:*:image/tiff:*'),
  gif('http-get:*:image/gif:*'),
  any('http-get:*:*:*');

  @override
  final String protocolInfo;
  const ImageMime(this.protocolInfo);
}

extension XmlExtension on XmlNode {
  String tagVal(String name) {
    final els = findAllElements(name);
    return els.isEmpty ? '' : els.first.innerText;
  }
}

class DeviceInfo {
  final String URLBase;
  final String deviceType;
  final String friendlyName;
  final List<dynamic> serviceList;
  DeviceInfo(
    this.URLBase,
    this.deviceType,
    this.friendlyName,
    this.serviceList,
  );
}

class PositionParser {
  String TrackDuration = '00:00:00';
  String TrackURI = '';
  String RelTime = '00:00:00';
  String AbsTime = '00:00:00';

  int get TrackDurationInt => toInt(TrackDuration);
  int get RelTimeInt => toInt(RelTime);

  PositionParser(String text) {
    if (text.isEmpty) return;
    final doc = XmlDocument.parse(text);
    final duration = doc.tagVal('TrackDuration');
    final rel = doc.tagVal('RelTime');
    final abs = doc.tagVal('AbsTime');
    if (duration.isNotEmpty) TrackDuration = duration;
    if (rel.isNotEmpty) RelTime = rel;
    if (abs.isNotEmpty) AbsTime = abs;
    TrackURI = doc.tagVal('TrackURI');
  }

  String seek(int n) => toStr((RelTimeInt + n).clamp(0, TrackDurationInt));

  static int toInt(String str) {
    var sum = 0;
    for (final part in str.split(':')) {
      sum = sum * 60 + (int.tryParse(part) ?? 0);
    }
    return sum;
  }

  static String toStr(int time) {
    final h = time ~/ 3600;
    final m = (time % 3600) ~/ 60;
    final s = time % 60;
    return '${z(h)}:${z(m)}:${z(s)}';
  }

  static String z(int n) => n > 9 ? '$n' : '0$n';
}

class VolumeParser {
  int current = 0;
  VolumeParser(String text) {
    final doc = XmlDocument.parse(text);
    current = int.tryParse(doc.tagVal('CurrentVolume')) ?? 0;
  }

  int change(int v) => (current + v).clamp(0, 100);
}

class TransportInfoParser {
  String CurrentTransportState = '';
  String CurrentTransportStatus = '';
  TransportInfoParser(String text) {
    final doc = XmlDocument.parse(text);
    CurrentTransportState = doc.tagVal('CurrentTransportState');
    CurrentTransportStatus = doc.tagVal('CurrentTransportStatus');
  }
}

class MediaInfoParser {
  String MediaDuration = '00:00';
  String CurrentURI = '';
  String NextURI = '';

  int get MediaDurationInt => PositionParser.toInt(MediaDuration);

  MediaInfoParser(String text) {
    final doc = XmlDocument.parse(text);
    final duration = doc.tagVal('MediaDuration');
    if (duration.isNotEmpty) MediaDuration = duration;
    CurrentURI = doc.tagVal('CurrentURI');
    NextURI = doc.tagVal('NextURI');
  }
}

class DeviceInfoParser {
  final String text;
  final XmlDocument doc;
  DeviceInfoParser(this.text) : doc = XmlDocument.parse(text);

  DeviceInfo parse(Uri uri) {
    var URLBase = doc.tagVal('URLBase').trim();
    if (URLBase.isEmpty) {
      URLBase = _urlBaseFromLocation(uri);
    }
    final device = _pickDevice();
    return DeviceInfo(
      URLBase,
      _directText(device, 'deviceType'),
      _directText(device, 'friendlyName'),
      _services(device),
    );
  }

  XmlElement _pickDevice() {
    final devices = doc.findAllElements('device');
    XmlElement? fallback;
    XmlElement? withAv;
    for (final d in devices) {
      fallback ??= d;
      if (_directText(d, 'deviceType').contains('MediaRenderer')) return d;
      if (withAv == null && _hasAv(d)) withAv = d;
    }
    final picked = withAv ?? fallback;
    if (picked == null) throw Exception('no device in description');
    return picked;
  }

  bool _hasAv(XmlElement device) {
    for (final sl in device.findElements('serviceList')) {
      for (final service in sl.findElements('service')) {
        if (_directText(service, 'serviceType').contains('AVTransport') ||
            _directText(service, 'serviceId').contains('AVTransport')) {
          return true;
        }
      }
    }
    return false;
  }

  List<Map<String, String>> _services(XmlElement device) {
    final items = <Map<String, String>>[];
    for (final sl in device.findElements('serviceList')) {
      for (final service in sl.findElements('service')) {
        items.add({
          'serviceType': _directText(service, 'serviceType'),
          'serviceId': _directText(service, 'serviceId'),
          'controlURL': _directText(service, 'controlURL'),
        });
      }
    }
    return items;
  }

  static String _directText(XmlElement e, String name) {
    for (final c in e.findElements(name)) {
      return c.innerText;
    }
    return '';
  }

  static String _urlBaseFromLocation(Uri uri) {
    var path = uri.path;
    if (path.isEmpty || path == '/') return uri.origin;
    if (!path.endsWith('/')) {
      final i = path.lastIndexOf('/');
      path = i <= 0 ? '/' : path.substring(0, i + 1);
    }
    return uri.origin + path;
  }
}
