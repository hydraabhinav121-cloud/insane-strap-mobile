import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _apiBase = 'https://insane-straps-api.onrender.com';
const Color _authRed = Color(0xFFFF334F);
const Color _authGold = Color(0xFFD4AF37);
const Color _authPanel = Color(0xFF17171D);

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _key = TextEditingController();
  final _ownerToken = TextEditingController();
  bool _ownerSetup = false;
  bool _signup = false;
  bool _busy = false;
  String? _token;
  Map<String, dynamic>? _user;
  String _message = '';
  List<dynamic> _users = [];
  List<dynamic> _logs = [];
  List<dynamic> _keys = [];

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _password.dispose();
    _key.dispose();
    _ownerToken.dispose();
    super.dispose();
  }

  Future<void> _restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('insane_straps_token');
    if (saved == null || saved.isEmpty) return;
    try {
      final result = await _request('GET', '/me', token: saved);
      if (!mounted) return;
      setState(() {
        _token = saved;
        _user = Map<String, dynamic>.from(result);
      });
      if (_user?['role'] == 'owner') await _loadOwnerData();
    } catch (e) {
      final message = e.toString();
      if (message.contains('Invalid or expired session') || message.contains('Sign in required') || message.contains('401')) {
        await prefs.remove('insane_straps_token');
      }
      if (mounted) setState(() => _message = 'Could not reach the account server. Check connection and try again.');
    }
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? token,
  }) async {
    final client = HttpClient();
    try {
      final uri = Uri.parse('$_apiBase$path');
      final request = switch (method) {
        'GET' => await client.getUrl(uri),
        'DELETE' => await client.deleteUrl(uri),
        'PUT' => await client.putUrl(uri),
        _ => await client.postUrl(uri),
      };
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      if (token != null) request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      final response = await request.close().timeout(const Duration(seconds: 25));
      final text = await response.transform(utf8.decoder).join();
      final decoded = text.isEmpty ? <String, dynamic>{} : jsonDecode(text);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final detail = decoded is Map ? decoded['detail'] : null;
        throw Exception(detail?.toString() ?? 'Request failed (${response.statusCode})');
      }
      return Map<String, dynamic>.from(decoded as Map);
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() { _busy = true; _message = ''; });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _message = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _bootstrapOwner() async {
    await _run(() async {
      final username = _username.text.trim();
      final password = _password.text;
      await _request('POST', '/admin/bootstrap', body: {
        'token': _ownerToken.text.trim(),
        'username': username,
        'password': password,
      });
      final result = await _request('POST', '/auth/login', body: {
        'username': username,
        'password': password,
      });
      final token = result['token'] as String;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('insane_straps_token', token);
      final profile = await _request('GET', '/me', token: token);
      if (!mounted) return;
      setState(() {
        _token = token;
        _user = profile;
        _message = 'Owner account initialized successfully.';
        _ownerToken.clear();
      });
      await _loadOwnerData();
    });
  }

  Future<void> _authenticate() async {
    await _run(() async {
      final username = _username.text.trim();
      final password = _password.text;
      final result = await _request(
        'POST',
        _signup ? '/auth/signup' : '/auth/login',
        body: {
          'username': username,
          'password': password,
          if (_signup && _email.text.trim().isNotEmpty) 'email': _email.text.trim(),
        },
      );
      final token = result['token'] as String;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('insane_straps_token', token);
      final profile = await _request('GET', '/me', token: token);
      if (!mounted) return;
      setState(() {
        _token = token;
        _user = profile;
        _message = _signup ? 'Account created successfully.' : 'Signed in successfully.';
      });
      if (profile['role'] == 'owner') await _loadOwnerData();
    });
  }

  Future<void> _loadOwnerData() async {
    final token = _token;
    if (token == null) return;
    final results = await Future.wait([
      _request('GET', '/owner/users', token: token),
      _request('GET', '/owner/logs', token: token),
      _request('GET', '/owner/keys', token: token),
    ]);
    if (!mounted) return;
    setState(() {
      _users = (results[0]['users'] as List<dynamic>? ?? []);
      _logs = (results[1]['logs'] as List<dynamic>? ?? []);
      _keys = (results[2]['keys'] as List<dynamic>? ?? []);
    });
  }

  Future<void> _redeemKey() async {
    await _run(() async {
      await _request('POST', '/keys/redeem',
        token: _token, body: {'key': _key.text.trim()});
      _key.clear();
      setState(() => _message = 'Premium key redeemed successfully.');
      final profile = await _request('GET', '/me', token: _token);
      if (mounted) setState(() => _user = profile);
    });
  }

  Future<void> _createKey() async {
    final daysController = TextEditingController(text: '30');
    final days = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _authPanel,
        title: const Text('Create premium key'),
        content: TextField(
          controller: daysController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Duration in days (1–3650)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () {
            final value = int.tryParse(daysController.text);
            if (value != null && value >= 1 && value <= 3650) Navigator.pop(ctx, value);
          }, child: const Text('Create')),
        ],
      ),
    );
    daysController.dispose();
    if (days == null) return;
    await _run(() async {
      final result = await _request('POST', '/owner/keys',
        token: _token, body: {'duration_days': days});
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: _authPanel,
          title: const Text('Key created — copy it now'),
          content: SelectableText(result['key'].toString()),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
        ),
      );
      await _loadOwnerData();
    });
  }

  Future<void> _signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('insane_straps_token');
    if (!mounted) return;
    setState(() {
      _token = null; _user = null; _users = []; _logs = []; _keys = [];
      _password.clear(); _message = 'Signed out.';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_user != null && _token != null) return _accountView();
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const Text('Your account', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        const Text('Sign in to sync your account and access server-verified features.',
          style: TextStyle(color: Colors.white60, height: 1.4)),
        const SizedBox(height: 18),
        Card(color: _authPanel, child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (!_ownerSetup) SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Sign in'), icon: Icon(Icons.login)),
                ButtonSegment(value: true, label: Text('Create account'), icon: Icon(Icons.person_add_alt_1)),
              ],
              selected: {_signup},
              onSelectionChanged: _busy ? null : (v) => setState(() { _signup = v.first; _message = ''; }),
            ),
            const SizedBox(height: 16),
            if (_ownerSetup) ...[
              TextField(controller: _ownerToken, obscureText: true,
                decoration: const InputDecoration(labelText: 'One-time owner setup token')),
              const SizedBox(height: 12),
            ],
            TextField(controller: _username, textInputAction: TextInputAction.next,
              autocorrect: false, decoration: const InputDecoration(labelText: 'Username')),
            if (_signup && !_ownerSetup) ...[
              const SizedBox(height: 12),
              TextField(controller: _email, keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Email (optional)')),
            ],
            const SizedBox(height: 12),
            TextField(controller: _password, obscureText: true,
              onSubmitted: (_) => _authenticate(),
              decoration: InputDecoration(labelText: 'Password',
                helperText: _signup ? 'At least 10 characters' : null)),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : (_ownerSetup ? _bootstrapOwner : _authenticate),
              child: _busy ? const SizedBox(height: 18, width: 18,
                child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_ownerSetup ? 'Initialize owner account' : (_signup ? 'Create secure account' : 'Sign in')),
            ),
            TextButton(
              onPressed: _busy ? null : () => setState(() {
                _ownerSetup = !_ownerSetup; _signup = false; _message = '';
              }),
              child: Text(_ownerSetup ? 'Back to sign in' : 'Initial owner setup (first run only)'),
            ),
            if (_message.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(_message, style: TextStyle(color: _message.contains('success') ? Colors.greenAccent : _authRed)),
            ],
          ]),
        )),
        const SizedBox(height: 12),
        const Text('Owner setup works only once and requires the one-time token configured on Render. Keep that token private and remove it from Render after the owner account is created.',
          style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.4)),
      ],
    );
  }

  Widget _accountView() {
    final owner = _user?['role'] == 'owner';
    final isPro = owner || _user?['is_pro'] == true;
    final proUntil = _user?['pro_until'];
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text(owner ? 'Owner console' : 'Account', style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w900)),
        const SizedBox(height: 14),
        Card(color: _authPanel, child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const CircleAvatar(backgroundColor: Color(0xFF35131B),
                child: Icon(Icons.person, color: _authRed)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_user?['username']?.toString() ?? 'User',
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                Text(_user?['email']?.toString() ?? 'No email set',
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ])),
              Chip(label: Text(owner ? 'OWNER · PRO' : (isPro ? 'PREMIUM' : 'FREE')),
                backgroundColor: (owner || isPro) ? const Color(0x33D4AF37) : Colors.white10,
                labelStyle: TextStyle(color: (owner || isPro) ? const Color(0xFFD4AF37) : Colors.white70)),
            ]),
            const Divider(height: 26),
            Text('Role: ${_user?['role'] ?? 'user'}'),
            const SizedBox(height: 6),
            Text('Pro expiry: ${owner ? 'Owner · Premium enabled' : (proUntil ?? (isPro ? 'Premium active' : 'Free plan'))}'),
            const SizedBox(height: 14),
            OutlinedButton.icon(onPressed: _signOut,
              icon: const Icon(Icons.logout), label: const Text('Sign out')),
          ]),
        )),
        if ((_user?['email'] == null || _user?['email'].toString().isEmpty == true) && !owner) ...[
          const SizedBox(height: 16),
          const Text('Link email (optional)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(controller: _email, keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email address')),
          const SizedBox(height: 8),
          FilledButton.tonal(onPressed: _busy ? null : () => _run(() async {
            await _request('POST', '/account/email', token: _token,
              body: {'email': _email.text.trim()});
            final profile = await _request('GET', '/me', token: _token);
            if (mounted) setState(() { _user = profile; _message = 'Email linked. Verification is not configured yet.'; });
          }), child: const Text('Link email')),
        ],
        if (!owner && !isPro) ...[
          const SizedBox(height: 16),
          const Text('Redeem a premium key', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(controller: _key, decoration: const InputDecoration(labelText: 'Premium key')),
          const SizedBox(height: 10),
          FilledButton(onPressed: _busy ? null : _redeemKey,
            child: const Text('Redeem key')),
        ],
        if (owner) ...[
          const SizedBox(height: 16),
          Row(children: [
            const Expanded(child: Text('Owner tools', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
            IconButton(onPressed: _busy ? null : () => _run(_loadOwnerData),
              icon: const Icon(Icons.refresh)),
          ]),
          FilledButton.icon(onPressed: _busy ? null : _createKey,
            icon: const Icon(Icons.key), label: const Text('Generate premium key')),
          const SizedBox(height: 14),
          Text('Users (${_users.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
          ..._users.take(100).map((u) => Card(color: _authPanel, child: ListTile(
            dense: true, title: Text(u['username']?.toString() ?? 'Unknown'),
            subtitle: Text(u['email']?.toString() ?? 'No email'),
            trailing: Text(u['role']?.toString() ?? 'user'),
          ))),
          const SizedBox(height: 14),
          Text('Premium keys (${_keys.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
          ..._keys.take(100).map((k) => Card(color: _authPanel, child: ListTile(
            dense: true,
            title: Text('${k['duration_days']} days · ${k['redeemed_by'] == null ? 'Unused' : 'Redeemed'}'),
            subtitle: Text('Created: ${k['created_at'] ?? ''}'),
            trailing: k['redeemed_by'] == null ? IconButton(
              tooltip: 'Revoke unused key',
              icon: const Icon(Icons.delete_outline, color: _authRed),
              onPressed: _busy ? null : () => _run(() async {
                await _request('DELETE', '/owner/keys/${k['id']}', token: _token);
                await _loadOwnerData();
                if (mounted) setState(() => _message = 'Unused key revoked.');
              }),
            ) : const Icon(Icons.check_circle_outline, color: Colors.greenAccent),
          ))),
          const SizedBox(height: 14),
          Text('Recent audit logs (${_logs.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
          ..._logs.take(50).map((log) => Card(color: _authPanel, child: ListTile(
            dense: true, title: Text(log['action']?.toString() ?? 'event'),
            subtitle: Text('${log['username'] ?? 'system'} · ${log['created_at'] ?? ''}'),
          ))),
        ],
        if (_message.isNotEmpty) Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(_message, style: const TextStyle(color: Colors.greenAccent)),
        ),
      ],
    );
  }
}
