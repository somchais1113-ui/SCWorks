import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class RadioGardenPanel extends StatefulWidget {
  const RadioGardenPanel({
    required this.compact,
    super.key,
  });

  final bool compact;

  @override
  State<RadioGardenPanel> createState() => _RadioGardenPanelState();
}

class _RadioGardenPanelState extends State<RadioGardenPanel> {
  static const MethodChannel _mediaControl =
      MethodChannel('com.scdeport.scdrive/radio_garden_media_control');
  static const EventChannel _mediaEvents =
      EventChannel('com.scdeport.scdrive/radio_garden_media');

  static final Uri _home = Uri.parse('https://radio.garden/');
  static final Uri _search = Uri.parse('https://radio.garden/search');
  static final Uri _favorites = Uri.parse('https://radio.garden/favorites');
  static final Uri _browse = Uri.parse('https://radio.garden/browse');

  StreamSubscription<dynamic>? _mediaSubscription;
  bool _opening = false;
  bool _permissionGranted = false;
  bool _sessionActive = false;
  bool _isPlaying = false;
  String? _title;
  String? _artist;
  String? _album;
  String? _message;

  @override
  void initState() {
    super.initState();
    _mediaSubscription = _mediaEvents.receiveBroadcastStream().listen(
      _onMediaEvent,
      onError: (_) {
        if (mounted) {
          setState(() {
            _sessionActive = false;
            _message = 'MEDIA SESSION UNAVAILABLE';
          });
        }
      },
    );
    unawaited(_refreshMedia());
  }

  @override
  void dispose() {
    _mediaSubscription?.cancel();
    super.dispose();
  }

  void _onMediaEvent(dynamic raw) {
    if (raw is! Map) return;
    final map = raw.map((key, value) => MapEntry(key.toString(), value));
    if (!mounted) return;
    setState(() {
      _permissionGranted = map['permissionGranted'] == true;
      _sessionActive = map['radioGardenSessionActive'] == true;
      _isPlaying = map['isPlaying'] == true;
      _title = _clean(map['title']);
      _artist = _clean(map['artist']);
      _album = _clean(map['album']);
      if (_sessionActive) _message = null;
    });
  }

  String? _clean(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  Future<void> _refreshMedia() async {
    try {
      final granted =
          await _mediaControl.invokeMethod<bool>('isPermissionGranted');
      if (mounted && granted != null) {
        setState(() => _permissionGranted = granted);
      }
      await _mediaControl.invokeMethod<bool>('refresh');
    } catch (_) {
      if (mounted) setState(() => _message = 'MEDIA CONTROL NOT READY');
    }
  }

  Future<void> _requestPermission() async {
    try {
      await _mediaControl.invokeMethod<bool>('requestPermission');
    } catch (_) {
      if (mounted) setState(() => _message = 'OPEN SETTINGS FAILED');
    }
  }

  Future<void> _transport(String method) async {
    try {
      final ok = await _mediaControl.invokeMethod<bool>(method) ?? false;
      if (!ok && mounted) {
        setState(() => _message = 'RADIO GARDEN SESSION NOT ACTIVE');
      }
    } catch (_) {
      if (mounted) setState(() => _message = 'MEDIA CONTROL FAILED');
    }
  }

  Future<void> _open(Uri uri) async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _message = null;
    });
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        setState(() => _message = 'UNABLE TO OPEN RADIO GARDEN');
      }
    } catch (_) {
      if (mounted) setState(() => _message = 'RADIO GARDEN NOT AVAILABLE');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = widget.compact;
    final station =
        _title ?? (_sessionActive ? 'RADIO GARDEN' : 'WORLD RADIO');
    final secondary = _artist ??
        _album ??
        (_permissionGranted
            ? 'Open a station in Radio Garden'
            : 'Enable media access for live controls');

    return Container(
      padding: EdgeInsets.fromLTRB(
        compact ? 18 : 22,
        compact ? 16 : 20,
        compact ? 18 : 22,
        compact ? 18 : 22,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF30343B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: compact ? 30 : 36,
                height: compact ? 30 : 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF65D996),
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  Icons.public_rounded,
                  color: const Color(0xFF65D996),
                  size: compact ? 18 : 21,
                ),
              ),
              SizedBox(width: compact ? 10 : 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'RADIO GARDEN',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontFamily: 'NissanBrand',
                        fontSize: compact ? 16 : 19,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.45,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _sessionActive
                          ? 'MEDIA SESSION · LIVE CONTROL'
                          : 'ONLINE RADIO · COMPANION MODE',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: const Color(0xFF7A8591),
                        fontFamily: 'NissanBrand',
                        fontSize: compact ? 8.5 : 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.55,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusPill(
                compact: compact,
                active: _sessionActive,
                permissionGranted: _permissionGranted,
              ),
            ],
          ),
          const Spacer(),
          Center(
            child: Column(
              children: <Widget>[
                Text(
                  _sessionActive && _isPlaying ? 'NOW PLAYING' : 'WORLD RADIO',
                  style: TextStyle(
                    color: const Color(0xFF737D88),
                    fontFamily: 'NissanBrand',
                    fontSize: compact ? 9 : 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
                SizedBox(height: compact ? 6 : 8),
                Text(
                  station,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontFamily: 'NissanBrand',
                    fontSize: compact ? 23 : 29,
                    fontWeight: FontWeight.w400,
                    letterSpacing: -0.35,
                  ),
                ),
                SizedBox(height: compact ? 4 : 6),
                Text(
                  secondary,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: const Color(0xFF8D97A2),
                    fontFamily: 'NissanBrand',
                    fontSize: compact ? 9.5 : 11,
                  ),
                ),
                SizedBox(height: compact ? 12 : 15),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    _TransportButton(
                      compact: compact,
                      icon: Icons.skip_previous_rounded,
                      enabled: _sessionActive,
                      onTap: () => unawaited(_transport('previous')),
                    ),
                    SizedBox(width: compact ? 10 : 14),
                    _TransportButton(
                      compact: compact,
                      primary: true,
                      icon: _isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      enabled: _sessionActive,
                      onTap: () => unawaited(_transport('togglePlayPause')),
                    ),
                    SizedBox(width: compact ? 10 : 14),
                    _TransportButton(
                      compact: compact,
                      icon: Icons.skip_next_rounded,
                      enabled: _sessionActive,
                      onTap: () => unawaited(_transport('next')),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Spacer(),
          if (_message != null) ...<Widget>[
            Text(
              _message!,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: const Color(0xFFE6A25D),
                fontFamily: 'NissanBrand',
                fontSize: compact ? 8.5 : 10,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: compact ? 6 : 8),
          ],
          Row(
            children: <Widget>[
              if (!_permissionGranted) ...<Widget>[
                Expanded(
                  child: _GardenAction(
                    compact: compact,
                    icon: Icons.settings_rounded,
                    label: 'MEDIA ACCESS',
                    onTap: () => unawaited(_requestPermission()),
                  ),
                ),
                SizedBox(width: compact ? 7 : 9),
              ],
              Expanded(
                child: _GardenAction(
                  compact: compact,
                  icon: Icons.favorite_border_rounded,
                  label: 'FAVORITES',
                  onTap:
                      _opening ? null : () => unawaited(_open(_favorites)),
                ),
              ),
              SizedBox(width: compact ? 7 : 9),
              Expanded(
                child: _GardenAction(
                  compact: compact,
                  icon: Icons.search_rounded,
                  label: 'SEARCH',
                  onTap: _opening ? null : () => unawaited(_open(_search)),
                ),
              ),
              SizedBox(width: compact ? 7 : 9),
              Expanded(
                child: _GardenAction(
                  compact: compact,
                  icon: Icons.explore_outlined,
                  label: 'BROWSE',
                  onTap: _opening ? null : () => unawaited(_open(_browse)),
                ),
              ),
              SizedBox(width: compact ? 7 : 9),
              Expanded(
                flex: 2,
                child: _GardenAction(
                  compact: compact,
                  emphasized: true,
                  icon: _opening
                      ? Icons.hourglass_top_rounded
                      : Icons.open_in_new_rounded,
                  label: _opening ? 'OPENING' : 'OPEN GARDEN',
                  onTap: _opening ? null : () => unawaited(_open(_home)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.compact,
    required this.active,
    required this.permissionGranted,
  });

  final bool compact;
  final bool active;
  final bool permissionGranted;

  @override
  Widget build(BuildContext context) {
    final text = active
        ? 'LIVE'
        : permissionGranted
            ? 'READY'
            : 'ACCESS';
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 5,
      ),
      decoration: BoxDecoration(
        color: active ? const Color(0xFF15231C) : const Color(0xFF171C22),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active ? const Color(0xFF2F6E4B) : const Color(0xFF3A424B),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: active ? const Color(0xFF65D996) : const Color(0xFF9AA4AE),
          fontFamily: 'NissanBrand',
          fontSize: compact ? 8 : 9.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.7,
        ),
      ),
    );
  }
}

class _TransportButton extends StatelessWidget {
  const _TransportButton({
    required this.compact,
    required this.icon,
    required this.enabled,
    required this.onTap,
    this.primary = false,
  });

  final bool compact;
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final size =
        primary ? (compact ? 50.0 : 58.0) : (compact ? 38.0 : 44.0);
    return Material(
      color: primary
          ? (enabled ? const Color(0xFF65D996) : const Color(0xFF26302B))
          : const Color(0xFF151B22),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: enabled ? onTap : null,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            icon,
            size: primary ? (compact ? 28 : 32) : (compact ? 20 : 23),
            color: primary
                ? (enabled ? const Color(0xFF07100B) : const Color(0xFF68716C))
                : (enabled
                    ? const Color(0xFFD8DEE5)
                    : const Color(0xFF59616B)),
          ),
        ),
      ),
    );
  }
}

class _GardenAction extends StatelessWidget {
  const _GardenAction({
    required this.compact,
    required this.icon,
    required this.label,
    required this.onTap,
    this.emphasized = false,
  });

  final bool compact;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final foreground = emphasized
        ? const Color(0xFF07100B)
        : enabled
            ? const Color(0xFFD8DEE5)
            : const Color(0xFF59616B);
    return Material(
      color:
          emphasized ? const Color(0xFF65D996) : const Color(0xFF151B22),
      borderRadius: BorderRadius.circular(compact ? 10 : 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(compact ? 10 : 12),
        child: Container(
          height: compact ? 42 : 49,
          padding: EdgeInsets.symmetric(horizontal: compact ? 7 : 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(compact ? 10 : 12),
            border: emphasized
                ? null
                : Border.all(color: const Color(0xFF313943)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, color: foreground, size: compact ? 15 : 17),
              SizedBox(width: compact ? 5 : 7),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: TextStyle(
                    color: foreground,
                    fontFamily: 'NissanBrand',
                    fontSize: compact ? 8 : 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
