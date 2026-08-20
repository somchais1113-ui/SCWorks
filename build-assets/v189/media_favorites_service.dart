import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum MediaFavoriteKind { radioGarden, spotify }

class MediaFavorite {
  const MediaFavorite({
    required this.id,
    required this.kind,
    required this.label,
    required this.uri,
    required this.addedAt,
    this.subtitle,
  });

  final String id;
  final MediaFavoriteKind kind;
  final String label;
  final String uri;
  final String? subtitle;
  final DateTime addedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'kind': kind.name,
        'label': label,
        'uri': uri,
        'subtitle': subtitle,
        'addedAt': addedAt.toIso8601String(),
      };

  static MediaFavorite? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final map = raw.map((key, value) => MapEntry(key.toString(), value));
    final uri = map['uri']?.toString().trim() ?? '';
    if (uri.isEmpty) return null;
    final kindName = map['kind']?.toString();
    MediaFavoriteKind? kind;
    for (final value in MediaFavoriteKind.values) {
      if (value.name == kindName) {
        kind = value;
        break;
      }
    }
    if (kind == null) return null;
    return MediaFavorite(
      id: map['id']?.toString() ?? _stableId(kind, uri),
      kind: kind,
      label: _cleanLabel(map['label']?.toString(), kind),
      uri: uri,
      subtitle: _cleanNullable(map['subtitle']?.toString()),
      addedAt: DateTime.tryParse(map['addedAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  static String _stableId(MediaFavoriteKind kind, String uri) =>
      '${kind.name}:${uri.trim().toLowerCase()}';

  static String _cleanLabel(String? value, MediaFavoriteKind kind) {
    final text = value?.trim();
    if (text != null && text.isNotEmpty) return text;
    return kind == MediaFavoriteKind.radioGarden
        ? 'Radio Garden Station'
        : 'Spotify';
  }

  static String? _cleanNullable(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }
}

class MediaFavoritesService extends ChangeNotifier {
  MediaFavoritesService._();

  static final MediaFavoritesService instance = MediaFavoritesService._();

  static const MethodChannel _control =
      MethodChannel('com.scdeport.scdrive/companion_media_control');
  static const EventChannel _shares =
      EventChannel('com.scdeport.scdrive/companion_media_share');
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static const String _favoritesKey = 'sc_drive_media_favorites_v1';
  static const String _lastRadioKey = 'sc_drive_last_radio_garden_uri_v1';
  static const String _lastSpotifyKey = 'sc_drive_last_spotify_uri_v1';

  final List<MediaFavorite> _favorites = <MediaFavorite>[];
  StreamSubscription<dynamic>? _shareSubscription;
  bool _initialized = false;
  bool _initializing = false;
  String? _lastRadioUri;
  String? _lastSpotifyUri;
  String? _lastShareMessage;

  List<MediaFavorite> get favorites => List.unmodifiable(_favorites);
  String? get lastRadioUri => _lastRadioUri;
  String? get lastSpotifyUri => _lastSpotifyUri;
  String? get lastShareMessage => _lastShareMessage;

  List<MediaFavorite> favoritesFor(MediaFavoriteKind kind) => _favorites
      .where((favorite) => favorite.kind == kind)
      .toList(growable: false);

  Future<void> initialize() async {
    if (_initialized || _initializing) return;
    _initializing = true;
    try {
      final raw = await _storage.read(key: _favoritesKey);
      if (raw != null && raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _favorites
            ..clear()
            ..addAll(decoded.map(MediaFavorite.fromJson).whereType<MediaFavorite>());
        }
      }
      _lastRadioUri = await _storage.read(key: _lastRadioKey);
      _lastSpotifyUri = await _storage.read(key: _lastSpotifyKey);

      if (defaultTargetPlatform == TargetPlatform.android) {
        _shareSubscription ??= _shares.receiveBroadcastStream().listen(
          (dynamic rawEvent) => unawaited(_handleShare(rawEvent)),
          onError: (_) {},
        );
        try {
          final pending = await _control.invokeMethod<dynamic>('getPendingShare');
          if (pending != null) await _handleShare(pending);
        } on PlatformException {
          // Bridge may not exist on older SC Drive builds.
        } on MissingPluginException {
          // Bridge may not exist on older SC Drive builds.
        }
      }
      _initialized = true;
      notifyListeners();
    } finally {
      _initializing = false;
    }
  }

  Future<void> _handleShare(dynamic raw) async {
    if (raw is! Map) return;
    final map = raw.map((key, value) => MapEntry(key.toString(), value));
    final url = map['url']?.toString().trim() ?? '';
    final source = map['source']?.toString().trim().toLowerCase();
    if (url.isEmpty) return;

    final kind = source == 'radio_garden'
        ? MediaFavoriteKind.radioGarden
        : source == 'spotify'
            ? MediaFavoriteKind.spotify
            : null;
    if (kind == null) return;

    final label = _shareLabel(
      map['label']?.toString(),
      kind: kind,
      url: url,
    );
    final favorite = MediaFavorite(
      id: '${kind.name}:${_canonicalUri(kind, url).toLowerCase()}',
      kind: kind,
      label: label,
      uri: _canonicalUri(kind, url),
      subtitle: kind == MediaFavoriteKind.radioGarden
          ? 'Saved from Radio Garden'
          : 'Saved from Spotify',
      addedAt: DateTime.now(),
    );
    await saveFavorite(favorite);
    _lastShareMessage = '$label SAVED';
    try {
      await _control.invokeMethod<bool>('clearPendingShare');
    } catch (_) {}
    notifyListeners();
  }

  Future<void> saveRadioGarden({
    required String uri,
    String? label,
    String? subtitle,
  }) async {
    await initialize();
    final canonical = _canonicalUri(MediaFavoriteKind.radioGarden, uri);
    await saveFavorite(
      MediaFavorite(
        id: 'radioGarden:${canonical.toLowerCase()}',
        kind: MediaFavoriteKind.radioGarden,
        label: _cleanLabel(label, 'Radio Garden Station'),
        uri: canonical,
        subtitle: subtitle,
        addedAt: DateTime.now(),
      ),
    );
  }

  Future<void> saveSpotify({
    required String uri,
    String? label,
    String? subtitle,
  }) async {
    await initialize();
    final canonical = _canonicalUri(MediaFavoriteKind.spotify, uri);
    await saveFavorite(
      MediaFavorite(
        id: 'spotify:${canonical.toLowerCase()}',
        kind: MediaFavoriteKind.spotify,
        label: _cleanLabel(label, 'Spotify'),
        uri: canonical,
        subtitle: subtitle,
        addedAt: DateTime.now(),
      ),
    );
  }

  Future<void> saveFavorite(MediaFavorite favorite) async {
    final index = _favorites.indexWhere(
      (item) => item.kind == favorite.kind &&
          _canonicalUri(item.kind, item.uri).toLowerCase() ==
              _canonicalUri(favorite.kind, favorite.uri).toLowerCase(),
    );
    if (index >= 0) {
      _favorites[index] = favorite;
    } else {
      _favorites.insert(0, favorite);
    }
    if (_favorites.length > 80) {
      _favorites.removeRange(80, _favorites.length);
    }
    await _persist();
    notifyListeners();
  }

  Future<void> removeFavorite(MediaFavorite favorite) async {
    _favorites.removeWhere((item) => item.id == favorite.id);
    await _persist();
    notifyListeners();
  }

  Future<bool> openRadioGarden(String uri) async {
    await initialize();
    final target = _canonicalUri(MediaFavoriteKind.radioGarden, uri);
    final ok = await _openNative('openRadioGarden', target);
    if (ok) {
      _lastRadioUri = target;
      await _storage.write(key: _lastRadioKey, value: target);
      notifyListeners();
    }
    return ok;
  }

  Future<bool> openSpotify(String? uri) async {
    await initialize();
    final target = uri == null || uri.trim().isEmpty
        ? 'spotify:'
        : _canonicalUri(MediaFavoriteKind.spotify, uri);
    final ok = await _openNative('openSpotify', target);
    if (ok) {
      _lastSpotifyUri = target;
      await _storage.write(key: _lastSpotifyKey, value: target);
      notifyListeners();
    }
    return ok;
  }

  Future<bool> isInstalled(MediaFavoriteKind kind) async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      return await _control.invokeMethod<bool>('isInstalled', <String, Object>{
            'target': kind == MediaFavoriteKind.radioGarden
                ? 'radio_garden'
                : 'spotify',
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _openNative(String method, String uri) async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      return await _control.invokeMethod<bool>(method, <String, Object>{
            'uri': uri,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _persist() async {
    final encoded = jsonEncode(_favorites.map((item) => item.toJson()).toList());
    await _storage.write(key: _favoritesKey, value: encoded);
  }

  static String _shareLabel(
    String? raw, {
    required MediaFavoriteKind kind,
    required String url,
  }) {
    var text = raw?.trim() ?? '';
    text = text.replaceAll(url, '').trim();
    text = text.replaceAll(RegExp(r'\s+'), ' ');
    if (text.length > 72) text = text.substring(0, 72).trim();
    return _cleanLabel(
      text,
      kind == MediaFavoriteKind.radioGarden
          ? 'Radio Garden Station'
          : 'Spotify',
    );
  }

  static String _cleanLabel(String? value, String fallback) {
    final text = value?.trim();
    return text == null || text.isEmpty ? fallback : text;
  }

  static String _canonicalUri(MediaFavoriteKind kind, String raw) {
    final value = raw.trim();
    if (kind == MediaFavoriteKind.spotify) {
      if (value.toLowerCase().startsWith('spotify:')) return value;
      final uri = Uri.tryParse(value);
      if (uri != null && uri.host.toLowerCase() == 'open.spotify.com') {
        final parts = uri.pathSegments.where((part) => part.isNotEmpty).toList();
        if (parts.length >= 2) {
          final type = parts[0].toLowerCase();
          const supported = <String>{
            'track',
            'playlist',
            'album',
            'artist',
            'show',
            'episode',
          };
          if (supported.contains(type)) return 'spotify:$type:${parts[1]}';
        }
      }
      return value;
    }
    final uri = Uri.tryParse(value);
    if (uri != null && uri.host.toLowerCase().endsWith('radio.garden')) {
      return uri.replace(query: null, fragment: null).toString();
    }
    return value;
  }

  @override
  void dispose() {
    _shareSubscription?.cancel();
    super.dispose();
  }
}
