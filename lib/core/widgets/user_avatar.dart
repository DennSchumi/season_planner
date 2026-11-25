import 'dart:typed_data';
import 'package:appwrite/appwrite.dart';
import 'package:flutter/material.dart';
import 'package:season_planner/core/services/auth_service.dart';

/// Universeller Nutzer-Avatar: lädt Appwrite-Storage-Avatare authentifiziert
/// über die aktive Benutzersitzung (DSGVO: Bucket `user_avatars` ist nicht
/// mehr öffentlich via `read("any")` abrufbar) und cacht die Bild-Bytes im RAM.
class UserAvatar extends StatefulWidget {
  final String avatarUrl;
  final String name;
  final double radius;
  final bool isOpenSlot;
  final Color? backgroundColor;
  final Color? foregroundColor;

  const UserAvatar({
    super.key,
    this.avatarUrl = '',
    this.name = '',
    this.radius = 20,
    this.isOpenSlot = false,
    this.backgroundColor,
    this.foregroundColor,
  });

  /// In-Memory-Cache für bereits geladene Avatar-Bytes (verhindert wiederholte Downloads).
  static final Map<String, Uint8List> _bytesCache = {};
  static final Map<String, Future<Uint8List?>> _inFlight = {};

  static ({String bucketId, String fileId})? _parseAppwriteFileUrl(String url) {
    final m = RegExp(
      r'/storage/buckets/([^/]+)/files/([^/]+)/(?:view|download|preview)',
    ).firstMatch(url);
    if (m == null) return null;
    return (bucketId: m.group(1)!, fileId: m.group(2)!);
  }

  static Future<Uint8List?> _loadAppwriteImage(String url) {
    final cached = _bytesCache[url];
    if (cached != null) return Future.value(cached);
    final pending = _inFlight[url];
    if (pending != null) return pending;

    final parsed = _parseAppwriteFileUrl(url);
    if (parsed == null) return Future.value(null);

    final fut = () async {
      try {
        final storage = Storage(AuthService().client);
        final bytes = await storage.getFileView(
          bucketId: parsed.bucketId,
          fileId: parsed.fileId,
        );
        if (bytes.isNotEmpty) {
          if (_bytesCache.length > 250) {
            _bytesCache.clear();
          }
          _bytesCache[url] = bytes;
          return bytes;
        }
      } catch (_) {}
      return null;
    }();

    _inFlight[url] = fut;
    fut.whenComplete(() => _inFlight.remove(url));
    return fut;
  }

  @override
  State<UserAvatar> createState() => _UserAvatarState();
}

class _UserAvatarState extends State<UserAvatar> {
  Uint8List? _bytes;
  String _loadedUrl = '';

  @override
  void initState() {
    super.initState();
    _syncUrl();
  }

  @override
  void didUpdateWidget(covariant UserAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.avatarUrl != widget.avatarUrl) {
      _syncUrl();
    }
  }

  void _syncUrl() {
    final url = widget.avatarUrl.trim();
    _loadedUrl = url;
    if (url.isEmpty) {
      _bytes = null;
      return;
    }
    if (UserAvatar._parseAppwriteFileUrl(url) == null) {
      _bytes = null;
      return;
    }
    final cached = UserAvatar._bytesCache[url];
    if (cached != null) {
      _bytes = cached;
      return;
    }
    _bytes = null;
    UserAvatar._loadAppwriteImage(url).then((data) {
      if (!mounted || _loadedUrl != url || data == null) return;
      setState(() => _bytes = data);
    });
  }

  String _initials(String raw) {
    final cleaned = raw.trim();
    if (cleaned.isEmpty) return '';
    final parts = cleaned.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = widget.backgroundColor ??
        (widget.isOpenSlot
            ? cs.surfaceContainerHighest
            : cs.primaryContainer.withValues(alpha: 0.85));
    final fg = widget.foregroundColor ??
        (widget.isOpenSlot ? cs.onSurfaceVariant : cs.onPrimaryContainer);

    if (widget.isOpenSlot) {
      return CircleAvatar(
        radius: widget.radius,
        backgroundColor: bg,
        child: Icon(
          Icons.person_add_alt,
          size: widget.radius * 0.95,
          color: fg,
        ),
      );
    }

    final url = widget.avatarUrl.trim();
    final initials = _initials(widget.name);

    Widget buildFallback() {
      if (initials.isNotEmpty) {
        return Center(
          child: Text(
            initials,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w700,
              fontSize: widget.radius * 0.72,
              letterSpacing: 0.2,
            ),
          ),
        );
      }
      return Icon(Icons.person, size: widget.radius * 1.0, color: fg);
    }

    if (url.isEmpty) {
      return CircleAvatar(
        radius: widget.radius,
        backgroundColor: bg,
        child: buildFallback(),
      );
    }

    final diameter = widget.radius * 2;
    final isAppwriteStorage = UserAvatar._parseAppwriteFileUrl(url) != null;

    if (isAppwriteStorage) {
      if (_bytes == null) {
        return CircleAvatar(
          radius: widget.radius,
          backgroundColor: bg,
          child: buildFallback(),
        );
      }
      return CircleAvatar(
        radius: widget.radius,
        backgroundColor: bg,
        child: ClipOval(
          child: Image.memory(
            _bytes!,
            width: diameter,
            height: diameter,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => buildFallback(),
          ),
        ),
      );
    }

    return CircleAvatar(
      radius: widget.radius,
      backgroundColor: bg,
      child: ClipOval(
        child: Image.network(
          url,
          width: diameter,
          height: diameter,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => buildFallback(),
          loadingBuilder: (ctx, child, progress) {
            if (progress == null) return child;
            return buildFallback();
          },
        ),
      ),
    );
  }
}
