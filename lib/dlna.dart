import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'xmlParser.dart';

String removeTrailing(String pattern, String from) {
  if (pattern.isEmpty) return from;
  var i = from.length;
  while (i >= pattern.length && from.startsWith(pattern, i - pattern.length)) {
    i -= pattern.length;
  }
  return from.substring(0, i);
}

String trimLeading(String pattern, String from) {
  var i = 0;
  while (from.startsWith(pattern, i)) {
    i += pattern.length;
  }
  return from.substring(i);
}

String htmlEncode(String text) {
  return text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll("'", '&#39;')
      .replaceAll('"', '&quot;');
}

class DLNADevice {
  static const _rcActions = {'SetMute', 'GetMute', 'SetVolume', 'GetVolume'};

  final DeviceInfo info;
  DateTime activeTime = DateTime.now();
  final currPosition = StreamController<PositionParser>.broadcast();
  late final PositionPoller positionPoller = PositionPoller(this, currPosition);

  DLNADevice(this.info);

  void updateActive(DateTime t) {
    activeTime = t;
  }

  String controlURL(String type) {
    final s = info.serviceList.where((e) {
      final id = e['serviceId']?.toString() ?? '';
      final st = e['serviceType']?.toString() ?? '';
      return id.contains(type) || st.contains(type);
    }).firstOrNull;
    if (s == null) {
      throw Exception('not found controlURL');
    }
    final path = s['controlURL']?.toString() ?? '';
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    final base = info.URLBase.endsWith('/') ? info.URLBase : '${info.URLBase}/';
    return Uri.parse(base).resolve(path).toString();
  }

  Future<String> request(String action, List<int> data) {
    final soapAction = _rcActions.contains(action)
        ? 'RenderingControl'
        : 'AVTransport';
    return DLNAHttp.post(Uri.parse(controlURL(soapAction)), {
      'SOAPAction': '"urn:schemas-upnp-org:service:$soapAction:1#$action"',
      'Content-Type': 'text/xml; charset="utf-8"',
    }, data);
  }

  Future<String> _act(String action, String xml) =>
      request(action, utf8.encode(xml));

  Future<String> setUrl(
    String url, {
    String title = '',
    PlayType type = VideoMime.any,
  }) {
    return _act(
      'SetAVTransportURI',
      XmlText.setPlayURLXml(url, title: title, type: type),
    );
  }

  Future<String> play() => _act('Play', XmlText.playActionXml());
  Future<String> pause() => _act('Pause', XmlText.pauseActionXml());
  Future<String> stop() => _act('Stop', XmlText.stopActionXml());
  Future<String> seek(String sk) => _act('Seek', XmlText.seekToXml(sk));
  Future<String> position() =>
      _act('GetPositionInfo', XmlText.getPositionXml());
  Future<String> seekByCurrent(String text, int n) =>
      seek(PositionParser(text).seek(n));
  Future<String> getCurrentTransportActions() => _act(
    'GetCurrentTransportActions',
    XmlText.getCurrentTransportActionsXml(),
  );
  Future<String> getMediaInfo() =>
      _act('GetMediaInfo', XmlText.getMediaInfoXml());
  Future<String> getTransportInfo() =>
      _act('GetTransportInfo', XmlText.getTransportInfoXml());
  Future<String> next() => _act('Next', XmlText.nextXml());
  Future<String> previous() => _act('Previous', XmlText.previousXml());
  Future<String> setPlayMode(String modeName) =>
      _act('SetPlayMode', XmlText.setPlayModeXml(modeName));
  Future<String> getDeviceCapabilities() =>
      _act('GetDeviceCapabilities', XmlText.getDeviceCapabilitiesXml());
  Future<String> mute(bool mute) => _act('SetMute', XmlText.muteXml(mute));
  Future<String> getMute() => _act('GetMute', XmlText.muteStateXml());
  Future<String> volume(int volume) =>
      _act('SetVolume', XmlText.volumeXml(volume));
  Future<String> getVolume() => _act('GetVolume', XmlText.volumeStateXml());

  Future<String> changeVolume(int value) async {
    return volume(VolumeParser(await getVolume()).change(value));
  }

  void dispose() {
    positionPoller.stop();
    if (!currPosition.isClosed) currPosition.close();
  }
}

class PositionPoller {
  final DLNADevice _dev;
  StreamController<PositionParser> position;
  Timer? _timer;
  bool _isPolling = false;
  PositionPoller(this._dev, this.position);

  void start() {
    if (_isPolling) return;
    _isPolling = true;
    _tick();
  }

  void stop() {
    if (!_isPolling) return;
    _isPolling = false;
    _timer?.cancel();
  }

  Future<void> _tick() async {
    if (!_isPolling) return;
    try {
      final text = await _dev.position();
      if (_isPolling && !position.isClosed) {
        position.add(PositionParser(text));
      }
    } catch (_) {
    } finally {
      if (_isPolling) {
        _timer = Timer(const Duration(seconds: 2), _tick);
      }
    }
  }
}

class XmlText {
  static const _av = 'AVTransport';
  static const _rc = 'RenderingControl';

  static String _envelope(String service, String action, [String extra = '']) {
    return '<?xml version="1.0" encoding="utf-8" standalone="yes"?>'
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
        '<s:Body>'
        '<u:$action xmlns:u="urn:schemas-upnp-org:service:$service:1">'
        '<InstanceID>0</InstanceID>$extra'
        '</u:$action>'
        '</s:Body></s:Envelope>';
  }

  static String setPlayURLXml(
    String url, {
    String title = '',
    required PlayType type,
  }) {
    final douyu = RegExp(r'^https?://(\d+)\?douyu$').firstMatch(url);
    if (douyu != null) {
      // 斗鱼 DLNA 只接受直播间 ID，不能传播放地址
      title = 'roomId = ${douyu.group(1)}, line = 0';
    } else if (title.isEmpty) {
      title = url;
    }
    title = htmlEncode(title);
    url = htmlEncode(url);
    var oclass = 'object.item.videoItem';
    if (type is AudioMime) {
      oclass = 'object.item.audioItem';
    } else if (type is ImageMime) {
      oclass = 'object.item.imageItem';
    }
    final res = type.protocolInfo.isEmpty
        ? ''
        : '<res protocolInfo="${type.protocolInfo}">$url</res>';
    final didl =
        '<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns:dlna="urn:schemas-dlna-org:metadata-1-0/">'
        '<item id="id" parentID="0" restricted="0"><dc:title>$title</dc:title><upnp:artist>unknow</upnp:artist><dc:date>${DateTime.now().toUtc().toIso8601String()}</dc:date><upnp:class>$oclass</upnp:class>$res</item>'
        '</DIDL-Lite>';
    return _envelope(
      _av,
      'SetAVTransportURI',
      '<CurrentURI>$url</CurrentURI><CurrentURIMetaData>${htmlEncode(didl)}</CurrentURIMetaData>',
    );
  }

  static String playActionXml() => _envelope(_av, 'Play', '<Speed>1</Speed>');
  static String pauseActionXml() => _envelope(_av, 'Pause');
  static String stopActionXml() => _envelope(_av, 'Stop');
  static String getPositionXml() => _envelope(_av, 'GetPositionInfo');
  static String seekToXml(sk) =>
      _envelope(_av, 'Seek', '<Unit>REL_TIME</Unit><Target>$sk</Target>');
  static String getCurrentTransportActionsXml() =>
      _envelope(_av, 'GetCurrentTransportActions');
  static String getMediaInfoXml() => _envelope(_av, 'GetMediaInfo');
  static String getTransportInfoXml() => _envelope(_av, 'GetTransportInfo');
  static String nextXml() => _envelope(_av, 'Next');
  static String previousXml() => _envelope(_av, 'Previous');
  static String setPlayModeXml(String modeName) => _envelope(
    _av,
    'SetPlayMode',
    '<NewPlayMode>${htmlEncode(modeName)}</NewPlayMode>',
  );
  static String getDeviceCapabilitiesXml() =>
      _envelope(_av, 'GetDeviceCapabilities');
  static String muteXml(bool mute) => _envelope(
    _rc,
    'SetMute',
    '<Channel>Master</Channel><DesiredMute>${mute ? 1 : 0}</DesiredMute>',
  );
  static String muteStateXml() =>
      _envelope(_rc, 'GetMute', '<Channel>Master</Channel>');
  static String volumeXml(int volume) => _envelope(
    _rc,
    'SetVolume',
    '<Channel>Master</Channel><DesiredVolume>$volume</DesiredVolume>',
  );
  static String volumeStateXml() =>
      _envelope(_rc, 'GetVolume', '<Channel>Master</Channel>');
}

class DLNAHttp {
  static final _client = HttpClient();
  static const _timeout = Duration(seconds: 15);

  static Future<String> _send(
    Future<HttpClientRequest> reqFuture,
    Uri uri, {
    Map<String, Object>? headers,
    List<int>? data,
  }) async {
    final req = await reqFuture.timeout(_timeout);
    headers?.forEach(req.headers.set);
    if (data != null) {
      req.contentLength = data.length;
      req.add(data);
    }
    final res = await req.close().timeout(_timeout);
    final body = await res.transform(utf8.decoder).join().timeout(_timeout);
    if (res.statusCode != HttpStatus.ok) {
      throw Exception('request $uri error , status ${res.statusCode} $body');
    }
    return body;
  }

  static Future<String> get(Uri uri) => _send(_client.getUrl(uri), uri);

  static Future<String> post(
    Uri uri,
    Map<String, Object> headers,
    List<int> data,
  ) {
    return _send(_client.postUrl(uri), uri, headers: headers, data: data);
  }
}

class _SsdpPacket {
  final Map<String, String> headers;
  _SsdpPacket(this.headers);
  String get location => headers['LOCATION'] ?? '';
  bool get isByebye => (headers['NTS'] ?? '').toLowerCase() == 'ssdp:byebye';

  static _SsdpPacket? parse(String message) {
    final lines = message.split('\n');
    if (lines.isEmpty) return null;
    final method = lines.first.trim().split(' ').first;
    if (method == 'M-SEARCH' ||
        (method != 'NOTIFY' && method != 'HTTP/1.1' && method != 'HTTP/1.0')) {
      return null;
    }
    final headers = <String, String>{};
    for (var i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      final idx = line.indexOf(':');
      if (idx <= 0) continue;
      headers[line.substring(0, idx).trim().toUpperCase()] = line
          .substring(idx + 1)
          .trim();
    }
    return _SsdpPacket(headers);
  }
}

class DeviceManager {
  var t = DateTime.now();
  final Map<String, DLNADevice> deviceList = {};
  final StreamController<Map<String, DLNADevice>> devices =
      StreamController.broadcast();
  final Map<String, String> _locationKeys = {};
  final Set<String> _inflight = {};
  Timer? _janitor;
  bool _disposed = false;

  DeviceManager() {
    _janitor = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_disposed) return;
      final n = deviceList.length;
      cleanInactiveDevices(DateTime.now());
      if (deviceList.length != n) _push();
    });
  }

  void cleanInactiveDevices(DateTime now) {
    deviceList.removeWhere((key, device) {
      final dead = now.difference(device.activeTime).inSeconds > 120;
      if (dead) device.dispose();
      return dead;
    });
    _locationKeys.removeWhere((_, key) => !deviceList.containsKey(key));
  }

  onMessage(String message) async {
    if (_disposed) return;
    final pkt = _SsdpPacket.parse(message);
    if (pkt == null) return;
    final loc = pkt.location;
    if (pkt.isByebye) {
      _removeByLocation(loc);
      return;
    }
    if (loc.isEmpty) return;

    final known = _locationKeys[loc];
    final cached = known == null ? null : deviceList[known];
    if (cached != null) {
      cached.updateActive(DateTime.now());
      _emit(false);
      return;
    }
    if (!_inflight.add(loc)) return;
    try {
      final info = await _fetchInfo(loc);
      if (info == null || _disposed) return;
      _locationKeys[loc] = info.URLBase;
      final existed = deviceList.containsKey(info.URLBase);
      deviceList
          .putIfAbsent(info.URLBase, () => DLNADevice(info))
          .updateActive(DateTime.now());
      _emit(!existed);
    } finally {
      _inflight.remove(loc);
    }
  }

  void _removeByLocation(String loc) {
    if (_disposed || loc.isEmpty) return;
    final key = _locationKeys.remove(loc);
    if (key == null || _locationKeys.containsValue(key)) return;
    deviceList.remove(key)?.dispose();
    _push();
  }

  void _emit(bool force) {
    if (_disposed) return;
    final now = DateTime.now();
    if (!force && now.difference(t).inSeconds.abs() <= 5) return;
    cleanInactiveDevices(now);
    _push();
  }

  void _push() {
    if (_disposed || devices.isClosed) return;
    devices.add(Map<String, DLNADevice>.from(deviceList));
    t = DateTime.now();
  }

  static Future<DeviceInfo?> _fetchInfo(String uri) async {
    try {
      final target = Uri.parse(uri);
      return DeviceInfoParser(await DLNAHttp.get(target)).parse(target);
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    _disposed = true;
    _janitor?.cancel();
    _janitor = null;
    for (final d in deviceList.values) {
      d.dispose();
    }
    deviceList.clear();
    _locationKeys.clear();
    _inflight.clear();
    if (!devices.isClosed) devices.close();
  }
}

class DLNAManager {
  static const String UPNP_IP_V4 = '239.255.255.250';
  static const int UPNP_PORT = 1900;
  final InternetAddress UPNP_AddressIPv4 = InternetAddress(UPNP_IP_V4);
  Timer? _sender;
  RawDatagramSocket? _socket_server;
  RawDatagramSocket? _socket_client;
  StreamSubscription? _clientSubscription;
  StreamSubscription? _serverSubscription;
  int _searchCount = 0;
  DeviceManager? _deviceManager;

  bool _isCurrent(DeviceManager dm) => identical(_deviceManager, dm);

  Future<DeviceManager> start({reusePort = false}) async {
    stop();
    _searchCount = 0;
    final dm = DeviceManager();
    _deviceManager = dm;
    try {
      final server = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        UPNP_PORT,
        reusePort: reusePort,
      );
      if (!_isCurrent(dm)) {
        server.close();
        return dm;
      }
      _socket_server = server;
      await _joinMulticast(server);
      if (!_isCurrent(dm)) return dm;

      final client = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      if (!_isCurrent(dm)) {
        client.close();
        return dm;
      }
      _socket_client = client;

      _clientSubscription = _listen(client, dm);
      _serverSubscription = _listen(server, dm);
      if (!_isCurrent(dm)) return dm;

      _sendSearchRequest(client);
      _sender = Timer.periodic(const Duration(seconds: 2), (_) {
        _sendSearchRequest(client);
      });
      return dm;
    } catch (_) {
      if (_isCurrent(dm)) stop();
      rethrow;
    }
  }

  StreamSubscription<RawSocketEvent> _listen(
    RawDatagramSocket socket,
    DeviceManager dm,
  ) {
    return socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      while (true) {
        final d = socket.receive();
        if (d == null) break;
        try {
          dm.onMessage(String.fromCharCodes(d.data).trim());
        } catch (_) {}
      }
    });
  }

  Future<void> _joinMulticast(RawDatagramSocket socket) async {
    List<NetworkInterface> interfaces;
    try {
      interfaces = await NetworkInterface.list(
        includeLinkLocal: false,
        type: InternetAddress.anyIPv4.type,
        includeLoopback: false,
      );
    } catch (_) {
      socket.joinMulticast(UPNP_AddressIPv4);
      return;
    }
    // https://github.com/dart-lang/sdk/issues/42250
    if (Platform.isIOS) {
      for (final interface in interfaces) {
        if (interface.addresses.isEmpty) continue;
        socket.setRawOption(
          RawSocketOption(
            RawSocketOption.levelIPv4,
            12,
            Uint8List.fromList(
              UPNP_AddressIPv4.rawAddress +
                  interface.addresses.first.rawAddress,
            ),
          ),
        );
      }
      return;
    }
    var joined = false;
    for (final interface in interfaces) {
      try {
        socket.joinMulticast(UPNP_AddressIPv4, interface);
        joined = true;
      } catch (_) {}
    }
    if (!joined) socket.joinMulticast(UPNP_AddressIPv4);
  }

  Future<void> _sendSearchRequest(RawDatagramSocket socket) async {
    const renderer = 'urn:schemas-upnp-org:device:MediaRenderer:1';
    const av = 'urn:schemas-upnp-org:service:AVTransport:1';
    final List<String> stList;
    if (_searchCount == 0) {
      stList = ['ssdp:all', renderer, av];
    } else {
      switch (_searchCount % 5) {
        case 0:
          stList = ['ssdp:all'];
        case 1:
        case 3:
          stList = [renderer];
        default:
          stList = [av];
      }
    }

    for (var i = 0; i < stList.length; i++) {
      if (!identical(_socket_client, socket)) return;
      socket.send(
        utf8.encode(
          'M-SEARCH * HTTP/1.1\r\n'
          'HOST: 239.255.255.250:1900\r\n'
          'ST: ${stList[i]}\r\n'
          'MX: ${_searchCount == 0 ? 1 : 3}\r\n'
          'MAN: "ssdp:discover"\r\n\r\n',
        ),
        UPNP_AddressIPv4,
        UPNP_PORT,
      );
      if (i < stList.length - 1) {
        await Future.delayed(const Duration(milliseconds: 30));
      }
    }
    _searchCount++;
  }

  stop() {
    _sender?.cancel();
    _sender = null;
    _clientSubscription?.cancel();
    _clientSubscription = null;
    _serverSubscription?.cancel();
    _serverSubscription = null;
    _socket_client?.close();
    _socket_client = null;
    _socket_server?.close();
    _socket_server = null;
    _deviceManager?.dispose();
    _deviceManager = null;
  }
}
