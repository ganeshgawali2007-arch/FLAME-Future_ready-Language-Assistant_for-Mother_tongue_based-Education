/// Real offline two-device classroom transport over the local network.
///
/// Teacher device hosts a TCP server on an ephemeral port; student devices
/// discover it with a single UDP broadcast (`FLAME1 DISCOVER <code>`) and join
/// with the session code + token. Messages are newline-delimited JSON (small,
/// ordered per connection). No cloud, no internet, no external server — only
/// the same Wi-Fi / hotspot LAN.
///
/// Protocol (one JSON object per line):
///   discovery (UDP):  FLAME1 DISCOVER <code>   ->   FLAME1 OFFER <port> <token>
///   join:             {"t":"join","code":..,"token":..,"name":..}
///   joinAck:          {"t":"joinAck","ok":true, ...class metadata}
///   turn:             {"t":"turn","cid":..,"seq":n,"sp":..,"text":..,"src":..,"tgt":..,"ts":..}
///   ended (teacher):  {"t":"ended"}
///   leave (student):  {"t":"leave"}
///
/// Safety: every session has a random code + token; joins with a wrong code or
/// token are rejected. Turns are deduplicated and kept in order per sender
/// (cid+seq). Messages never leave the local session sockets.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../../models/enums.dart';
import 'offline_classroom_sync.dart';

/// Where a student found a teacher session (code -> host/port/token).
class DiscoveredSession {
  const DiscoveredSession({
    required this.host,
    required this.port,
    required this.token,
  });

  final InternetAddress host;
  final int port;
  final String token;
}

class LanClassroomSync implements OfflineClassroomSync {
  LanClassroomSync({
    Future<DiscoveredSession?> Function(String code)? discoverer,
    this.localName = 'student',
    this.discoveryPort = 40404,
  }) : _discoverer = discoverer;

  /// Name this device reports when joining (set before [joinSession]).
  String localName;

  /// UDP port used for discovery broadcast/reply.
  final int discoveryPort;

  final Future<DiscoveredSession?> Function(String code)? _discoverer;

  static const String _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static const int _maxReconnectAttempts = 3;

  ClassroomSyncStatus _status = ClassroomSyncStatus.idle;
  Map<String, String>? _sessionInfo;

  // Teacher side.
  ServerSocket? _server;
  RawDatagramSocket? _udp;
  final List<Socket> _clients = [];
  String? _code;
  String? _token;

  // Student side.
  Socket? _socket;
  bool _leaving = false;

  final StreamController<ClassroomSyncTurn> _turns =
      StreamController<ClassroomSyncTurn>.broadcast();
  final StreamController<String> _hostEvents =
      StreamController<String>.broadcast();

  int _seq = 0;
  final Map<String, int> _lastSeq = {};
  final Set<String> _seen = {};
  String _cid = 'teacher';

  @override
  Map<String, String>? get sessionInfo => _sessionInfo;

  ClassroomSyncStatus get status => _status;

  /// Number of connected students (teacher side; exposed for tests).
  int get clientCount => _clients.length;

  static String _randomCode(Random r) {
    final buf = StringBuffer();
    for (var i = 0; i < 6; i++) {
      buf.write(_alphabet[r.nextInt(_alphabet.length)]);
    }
    return buf.toString();
  }

  // --------------------------------------------------------------------------
  // Teacher
  // --------------------------------------------------------------------------

  @override
  Future<ClassroomSyncStatus> createSession({
    required String name,
    required String level,
    required String subject,
    required String teacherName,
    required String lesson,
    required String topic,
  }) async {
    await leaveSession();
    final r = Random.secure();
    _code = _randomCode(r);
    _token = _randomCode(r) + _randomCode(r);
    _cid = 'teacher';
    _leaving = false;

    _server = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    _udp = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      discoveryPort,
      reuseAddress: true,
    );
    _udp!.listen(_onDiscovery);

    _sessionInfo = {
      'code': _code!,
      'token': _token!,
      'port': '${_server!.port}',
      'name': name,
      'level': level,
      'subject': subject,
      'teacher': teacherName,
      'lesson': lesson,
      'topic': topic,
    };
    _server!.listen(_onClient);
    _status = ClassroomSyncStatus.hosting;
    return _status;
  }

  void _onDiscovery(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final dg = _udp?.receive();
    if (dg == null) return;
    final msg = utf8.decode(dg.data, allowMalformed: true).trim();
    final parts = msg.split(' ');
    if (parts.length == 3 &&
        parts[0] == 'FLAME1' &&
        parts[1] == 'DISCOVER' &&
        parts[2] == _code) {
      final reply = utf8.encode('FLAME1 OFFER ${_server!.port} $_token');
      _udp!.send(reply, dg.address, dg.port);
    }
  }

  void _onClient(Socket socket) {
    final lines = utf8.decoder
        .bind(socket)
        .transform(const LineSplitter());
    var joined = false;
    late StreamSubscription<String> sub;
    sub = lines.listen(
      (line) {
        Map<String, Object?> msg;
        try {
          msg = jsonDecode(line) as Map<String, Object?>;
        } catch (_) {
          return;
        }
        if (!joined) {
          if (msg['t'] == 'join' &&
              msg['code'] == _code &&
              msg['token'] == _token) {
            joined = true;
            _clients.add(socket);
            final ack = <String, Object?>{'t': 'joinAck', 'ok': true}
              ..addAll(_sessionInfo!);
            _writeln(socket, jsonEncode(ack));
          } else {
            _writeln(socket, jsonEncode({'t': 'joinAck', 'ok': false}));
            socket.destroy();
            sub.cancel();
          }
          return;
        }
        _handleStudentMessage(socket, msg);
      },
      onDone: () {
        _clients.remove(socket);
        socket.destroy();
      },
      onError: (_) {
        _clients.remove(socket);
        socket.destroy();
      },
    );
  }

  void _handleStudentMessage(Socket from, Map<String, Object?> msg) {
    switch (msg['t']) {
      case 'turn':
        final turn = _parseTurn(msg);
        if (turn == null) return;
        _turns.add(turn);
        // Relay to the other students, unchanged (same cid+seq -> dedup safe).
        final line = jsonEncode(msg);
        for (final c in _clients) {
          if (!identical(c, from)) _writeln(c, line);
        }
      case 'leave':
        _clients.remove(from);
        from.destroy();
    }
  }

  @override
  Future<void> sendTeacherTurn(ClassroomSyncTurn turn) async {
    if (_status != ClassroomSyncStatus.hosting) return;
    final line = jsonEncode(_turnMsg(turn, 'teacher'));
    for (final c in List<Socket>.from(_clients)) {
      _writeln(c, line);
    }
  }

  // --------------------------------------------------------------------------
  // Student
  // --------------------------------------------------------------------------

  @override
  Future<ClassroomSyncStatus> joinSession(String code) async {
    await leaveSession();
    _leaving = false;
    _cid = 'student-${Random.secure().nextInt(1 << 31)}';
    final discover = _discoverer ?? _udpDiscover;
    final found = await discover(code.trim().toUpperCase());
    if (found == null) {
      _status = ClassroomSyncStatus.error;
      return _status;
    }
    return _connect(found, code.trim().toUpperCase());
  }

  Future<ClassroomSyncStatus> _connect(
      DiscoveredSession found, String code) async {
    try {
      final socket = await Socket.connect(found.host, found.port,
          timeout: const Duration(seconds: 5));
      _socket = socket;

      // A Socket supports exactly one listener, so the joinAck and every
      // later message flow through this single subscription.
      final ackCompleter = Completer<bool>();
      final lines =
          utf8.decoder.bind(socket).transform(const LineSplitter());
      late StreamSubscription<String> sub;
      sub = lines.listen(
        (line) {
          Map<String, Object?> msg;
          try {
            msg = jsonDecode(line) as Map<String, Object?>;
          } catch (_) {
            return;
          }
          if (!ackCompleter.isCompleted) {
            if (msg['t'] == 'joinAck' && msg['ok'] == true) {
              _sessionInfo = {
                'code': code,
                'name': '${msg['name'] ?? ''}',
                'level': '${msg['level'] ?? ''}',
                'subject': '${msg['subject'] ?? ''}',
                'teacher': '${msg['teacher'] ?? ''}',
                'lesson': '${msg['lesson'] ?? ''}',
                'topic': '${msg['topic'] ?? ''}',
              };
              ackCompleter.complete(true);
            } else {
              ackCompleter.complete(false);
            }
            return;
          }
          _handleTeacherMessage(msg);
        },
        onDone: _onTeacherGone,
        onError: (_) => _onTeacherGone(),
      );

      _writeln(
        socket,
        jsonEncode({
          't': 'join',
          'code': code,
          'token': found.token,
          'name': localName,
        }),
      );
      final ok = await ackCompleter.future
          .timeout(const Duration(seconds: 5), onTimeout: () => false);
      if (!ok) {
        await sub.cancel();
        socket.destroy();
        _socket = null;
        _status = ClassroomSyncStatus.error;
        return _status;
      }
      _status = ClassroomSyncStatus.joined;
      return _status;
    } catch (_) {
      _socket?.destroy();
      _socket = null;
      _status = ClassroomSyncStatus.error;
      return _status;
    }
  }

  void _handleTeacherMessage(Map<String, Object?> msg) {
    switch (msg['t']) {
      case 'turn':
        final turn = _parseTurn(msg);
        if (turn != null) _turns.add(turn);
      case 'host':
        _hostEvents.add('${msg['event']}');
      case 'ended':
        _hostEvents.add('ended');
        _onTeacherGone();
    }
  }

  /// Teacher socket closed (or session ended). Try to rejoin a few times;
  /// if the session is genuinely gone, broadcast `ended` so the controller
  /// can surface "class ended". The streams stay open for reuse.
  Future<void> _onTeacherGone() async {
    if (_status != ClassroomSyncStatus.joined) return;
    _socket?.destroy();
    _socket = null;
    if (_leaving) return;
    final code = _sessionInfo?['code'];
    if (code != null) {
      final discover = _discoverer ?? _udpDiscover;
      for (var attempt = 0; attempt < _maxReconnectAttempts; attempt++) {
        await Future<void>.delayed(const Duration(seconds: 1));
        final found = await discover(code);
        if (found == null) continue;
        final reconnected = await _connect(found, code);
        if (reconnected == ClassroomSyncStatus.joined) return;
      }
    }
    _status = ClassroomSyncStatus.idle;
    _hostEvents.add('ended');
  }

  @override
  Future<void> sendStudentTurn(ClassroomSyncTurn turn) async {
    if (_status != ClassroomSyncStatus.joined || _socket == null) return;
    _writeln(_socket!, jsonEncode(_turnMsg(turn, 'student')));
  }

  @override
  Stream<ClassroomSyncTurn> receiveTurn() => _turns.stream;

  @override
  Stream<String> hostEvents() => _hostEvents.stream;

  @override
  Future<void> sendHostEvent(String event) async {
    if (_status != ClassroomSyncStatus.hosting) return;
    final line = jsonEncode({'t': 'host', 'event': event});
    for (final c in List<Socket>.from(_clients)) {
      _writeln(c, line);
    }
  }

  // --------------------------------------------------------------------------
  // Shared
  // --------------------------------------------------------------------------

  @override
  Future<void> leaveSession() async {
    _leaving = true;
    if (_status == ClassroomSyncStatus.hosting) {
      for (final c in List<Socket>.from(_clients)) {
        _writeln(c, jsonEncode({'t': 'ended'}));
        c.destroy();
      }
      _clients.clear();
      await _server?.close();
      _server = null;
      _udp?.close();
      _udp = null;
    }
    if (_socket != null) {
      _writeln(_socket!, jsonEncode({'t': 'leave'}));
      _socket!.destroy();
      _socket = null;
    }
    _status = ClassroomSyncStatus.idle;
    _sessionInfo = null;
    _lastSeq.clear();
    _seen.clear();
  }

  /// Exposed for tests: close the turn stream (e.g. after teacher ended).
  Future<void> dispose() async {
    await leaveSession();
    if (!_turns.isClosed) await _turns.close();
  }

  Map<String, Object?> _turnMsg(ClassroomSyncTurn turn, String sp) => {
        't': 'turn',
        'cid': _cid,
        'seq': ++_seq,
        'sp': sp,
        'text': turn.text,
        'src': turn.sourceLanguage.name,
        'tgt': turn.targetLanguage.name,
        'ts': turn.timestamp,
      };

  ClassroomSyncTurn? _parseTurn(Map<String, Object?> msg) {
    final cid = '${msg['cid']}';
    final seq = (msg['seq'] as num?)?.toInt() ?? 0;
    final key = '$cid:$seq';
    if (_seen.contains(key)) return null;
    final last = _lastSeq[cid] ?? 0;
    if (seq <= last) return null; // duplicate / out-of-order
    _seen.add(key);
    _lastSeq[cid] = seq;
    final sp = msg['sp'] == 'teacher' ? SpeakerRole.teacher : SpeakerRole.student;
    return ClassroomSyncTurn(
      speaker: sp,
      text: '${msg['text'] ?? ''}',
      sourceLanguage: AppLanguage.values.byName('${msg['src']}'),
      targetLanguage: AppLanguage.values.byName('${msg['tgt']}'),
      timestamp: (msg['ts'] as num?)?.toInt() ?? 0,
    );
  }

  void _writeln(Socket socket, String line) {
    try {
      socket.write('$line\n');
    } catch (_) {
      // Peer vanished; cleanup happens via onDone/onError.
    }
  }

  Future<DiscoveredSession?> _udpDiscover(String code) async {
    RawDatagramSocket? sock;
    try {
      sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      sock.broadcastEnabled = true;
      final query = utf8.encode('FLAME1 DISCOVER $code');
      final completer = Completer<DiscoveredSession?>();
      var sends = 0;
      final timer = Timer.periodic(const Duration(milliseconds: 400), (t) {
        if (sends++ >= 6) t.cancel();
        sock!.send(query, InternetAddress('255.255.255.255'), discoveryPort);
      });
      final sub = sock.listen((event) {
        if (event != RawSocketEvent.read) return;
        final dg = sock!.receive();
        if (dg == null) return;
        final msg = utf8.decode(dg.data, allowMalformed: true).trim();
        final parts = msg.split(' ');
        if (parts.length == 4 && parts[0] == 'FLAME1' && parts[1] == 'OFFER') {
          if (!completer.isCompleted) {
            completer.complete(DiscoveredSession(
              host: dg.address,
              port: int.tryParse(parts[2]) ?? 0,
              token: parts[3],
            ));
          }
        }
      });
      final result = await completer.future
          .timeout(const Duration(seconds: 3), onTimeout: () => null);
      timer.cancel();
      await sub.cancel();
      return result;
    } catch (_) {
      return null;
    } finally {
      sock?.close();
    }
  }
}
