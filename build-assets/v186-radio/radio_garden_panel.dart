import 'dart:async';

import 'package:flutter/material.dart';
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
  bool _opening = false;
  String? _message;

  static final Uri _home = Uri.parse('https://radio.garden/');
  static final Uri _search = Uri.parse('https://radio.garden/search');
  static final Uri _favorites = Uri.parse('https://radio.garden/favorites');
  static final Uri _browse = Uri.parse('https://radio.garden/browse');

  Future<void> _open(Uri uri, String label) async {
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
      if (mounted) {
        setState(() => _message = 'RADIO GARDEN NOT AVAILABLE');
      }
    } finally {
      if (mounted) {
        setState(() => _opening = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = widget.compact;
    return Container(
      padding: EdgeInsets.fromLTRB(
        compact ? 18 : 22,
        compact ? 16 : 20,
        compact ? 18 : 22,
        compact ? 20 : 24,
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
                  border: Border.all(color: const Color(0xFF65D996), width: 1.5),
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
                      'ONLINE RADIO · COMPANION MODE',
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
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 8 : 10,
                  vertical: compact ? 4 : 5,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF15231C),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFF2F6E4B)),
                ),
                child: Text(
                  'ONLINE',
                  style: TextStyle(
                    color: const Color(0xFF65D996),
                    fontFamily: 'NissanBrand',
                    fontSize: compact ? 8 : 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.7,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          Center(
            child: Column(
              children: <Widget>[
                Text(
                  'WORLD RADIO',
                  style: TextStyle(
                    color: const Color(0xFF737D88),
                    fontFamily: 'NissanBrand',
                    fontSize: compact ? 9 : 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
                SizedBox(height: compact ? 5 : 7),
                Text(
                  'Stations around the world',
                  style: TextStyle(
                    color: Colors.white,
                    fontFamily: 'NissanBrand',
                    fontSize: compact ? 22 : 28,
                    fontWeight: FontWeight.w400,
                    letterSpacing: -0.35,
                  ),
                ),
                SizedBox(height: compact ? 5 : 7),
                Text(
                  'Choose a station in Radio Garden, then return to SC Drive.\nAudio continues in the background.',
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: const Color(0xFF8D97A2),
                    fontFamily: 'NissanBrand',
                    fontSize: compact ? 9.5 : 11,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          if (_message != null) ...<Widget>[
            Text(
              _message!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: const Color(0xFFE6A25D),
                fontFamily: 'NissanBrand',
                fontSize: compact ? 9 : 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: compact ? 6 : 8),
          ],
          Row(
            children: <Widget>[
              Expanded(
                child: _GardenAction(
                  compact: compact,
                  icon: Icons.favorite_border_rounded,
                  label: 'FAVORITES',
                  onTap: _opening ? null : () => _open(_favorites, 'FAVORITES'),
                ),
              ),
              SizedBox(width: compact ? 7 : 9),
              Expanded(
                child: _GardenAction(
                  compact: compact,
                  icon: Icons.search_rounded,
                  label: 'SEARCH',
                  onTap: _opening ? null : () => _open(_search, 'SEARCH'),
                ),
              ),
              SizedBox(width: compact ? 7 : 9),
              Expanded(
                child: _GardenAction(
                  compact: compact,
                  icon: Icons.explore_outlined,
                  label: 'BROWSE',
                  onTap: _opening ? null : () => _open(_browse, 'BROWSE'),
                ),
              ),
              SizedBox(width: compact ? 7 : 9),
              Expanded(
                flex: 2,
                child: _GardenAction(
                  compact: compact,
                  emphasized: true,
                  icon: _opening ? Icons.hourglass_top_rounded : Icons.open_in_new_rounded,
                  label: _opening ? 'OPENING' : 'OPEN GARDEN',
                  onTap: _opening ? null : () => _open(_home, 'OPEN GARDEN'),
                ),
              ),
            ],
          ),
        ],
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
      color: emphasized
          ? const Color(0xFF65D996)
          : const Color(0xFF151B22),
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
