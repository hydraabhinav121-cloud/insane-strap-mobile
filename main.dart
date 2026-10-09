import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:app_links/app_links.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:android_intent_plus/android_intent.dart';

const red = Color(0xFFFF3048);
const bg = Color(0xFF080709);
const panel = Color(0xFF151216);
const muted = Color(0xFFB4AEB8);
const apiBase = String.fromEnvironment('INSANE_API_BASE_URL', defaultValue: '');

void main() => runApp(const InsaneStrapsApp());

class InsaneStrapsApp extends StatelessWidget {
  const InsaneStrapsApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Insane Straps',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: bg,
          colorScheme: ColorScheme.fromSeed(seedColor: red, brightness: Brightness.dark),
          useMaterial3: true,
          appBarTheme: const AppBarTheme(backgroundColor: bg, foregroundColor: Colors.white),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: panel,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.white12)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.white12)),
          ),
        ),
        home: const AuthGate(),
      );
}

class Plan {
  final String id, name, duration;
  final int defaultPrice;
  const Plan(this.id, this.name, this.duration, this.defaultPrice);
}
const plans = [Plan('day', '1 Day', '24 hours', 20), Plan('month', '1 Month', '30 days', 120), Plan('lifetime', 'Permanent', 'Lifetime access', 500)];

class PaymentRequest {
  final String id, planId, transactionRef, createdAt, status;
  final int amount;
  const PaymentRequest({required this.id, required this.planId, required this.transactionRef, required this.createdAt, required this.status, required this.amount});
  Map<String, dynamic> toJson() => {'id': id, 'planId': planId, 'transactionRef': transactionRef, 'createdAt': createdAt, 'status': status, 'amount': amount};
  factory PaymentRequest.fromJson(Map<String, dynamic> j) => PaymentRequest(id: '${j['id']}', planId: '${j['planId']}', transactionRef: '${j['transactionRef']}', createdAt: '${j['createdAt']}', status: '${j['status']}', amount: (j['amount'] as num).toInt());
  PaymentRequest withStatus(String next) => PaymentRequest(id: id, planId: planId, transactionRef: transactionRef, createdAt: createdAt, status: next, amount: amount);
}


class AuthGate extends StatefulWidget { const AuthGate({super.key}); @override State<AuthGate> createState() => _AuthGateState(); }
class _AuthGateState extends State<AuthGate> {
  bool checking = true; bool signedIn = false;
  @override void initState() { super.initState(); _check(); }
  Future<void> _check() async {
    final store = const FlutterSecureStorage(); final token = await store.read(key: 'apiToken') ?? '';
    if (token.isNotEmpty && apiBase.isNotEmpty) { try { final r = await http.get(Uri.parse('$apiBase/me'), headers: {'Authorization':'Bearer $token'}).timeout(const Duration(seconds: 8)); signedIn = r.statusCode == 200; if (!signedIn) await store.delete(key:'apiToken'); } catch (_) { signedIn = false; } }
    if (mounted) setState(() => checking = false);
  }
  @override Widget build(BuildContext context) => checking ? const Scaffold(body:Center(child:CircularProgressIndicator(color:red))) : signedIn ? const AppShell() : const AuthScreen();
}

class AuthScreen extends StatefulWidget { const AuthScreen({super.key}); @override State<AuthScreen> createState() => _AuthScreenState(); }
class _AuthScreenState extends State<AuthScreen> {
  String mode='login'; bool busy=false, obscure=true; String pendingEmail='';
  final loginC=TextEditingController(), usernameC=TextEditingController(), emailC=TextEditingController(), passwordC=TextEditingController(), codeC=TextEditingController(), newPasswordC=TextEditingController();
  final store=const FlutterSecureStorage();
  @override void dispose(){loginC.dispose();usernameC.dispose();emailC.dispose();passwordC.dispose();codeC.dispose();newPasswordC.dispose();super.dispose();}
  void message(String text){if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(text)));}
  Future<Map<String,dynamic>?> request(String path, Map<String,dynamic> body) async {
    if(apiBase.trim().isEmpty){message('Account service is not configured. Deploy the backend and set INSANE_API_BASE_URL first.');return null;}
    try { final r=await http.post(Uri.parse('$apiBase$path'),headers:{'Content-Type':'application/json'},body:jsonEncode(body)).timeout(const Duration(seconds:15)); final data=Map<String,dynamic>.from(jsonDecode(r.body) as Map); if(r.statusCode<200||r.statusCode>=300){message('${data['error']??'Request failed'}');return null;} return data; }
    catch(_){message('Cannot reach the account server. Check internet and backend status.');return null;}
  }
  Future<void> submit() async {
    if(busy)return; setState(()=>busy=true);
    try {
      Map<String,dynamic>? data;
      if(mode=='login'){
        data=await request('/auth/login',{'login':loginC.text.trim(),'password':passwordC.text});
        if(data!=null){await store.write(key:'apiToken',value:data['token'] as String); if(mounted) Navigator.of(context).pushReplacement(MaterialPageRoute(builder:(_)=>const AppShell()));}
      } else if(mode=='register'){
        data=await request('/auth/register',{'username':usernameC.text.trim(),'email':emailC.text.trim(),'password':passwordC.text});
        if(data!=null){pendingEmail=emailC.text.trim(); setState(()=>mode='verify'); message('Check your email for the verification code.');}
      } else if(mode=='verify'){
        data=await request('/auth/verify-email',{'email':(pendingEmail.isEmpty?emailC.text:pendingEmail).trim(),'code':codeC.text.trim()});
        if(data!=null){setState(()=>mode='login');loginC.text=pendingEmail.isEmpty?emailC.text:pendingEmail;message('Email verified. Sign in now.');}
      } else if(mode=='forgot'){
        data=await request('/auth/forgot-password',{'email':emailC.text.trim()}); if(data!=null){pendingEmail=emailC.text.trim();setState(()=>mode='reset');message('If that verified account exists, a reset code has been sent.');}
      } else if(mode=='reset'){
        data=await request('/auth/reset-password',{'email':(pendingEmail.isEmpty?emailC.text:pendingEmail).trim(),'code':codeC.text.trim(),'newPassword':newPasswordC.text}); if(data!=null){setState(()=>mode='login');loginC.text=pendingEmail.isEmpty?emailC.text:pendingEmail;message('Password reset successfully. Sign in with your new password.');}
      }
    } finally { if(mounted)setState(()=>busy=false); }
  }
  Widget field(String label,TextEditingController c,{bool secret=false,TextInputType? type})=>Padding(padding:const EdgeInsets.only(bottom:12),child:TextField(controller:c,keyboardType:type,obscureText:secret&&obscure,textCapitalization:TextCapitalization.none,decoration:InputDecoration(labelText:label,suffixIcon:secret?IconButton(onPressed:()=>setState(()=>obscure=!obscure),icon:Icon(obscure?Icons.visibility_outlined:Icons.visibility_off_outlined)):null)));
  String get heading=>{'login':'Welcome back.','register':'Create account.','verify':'Verify your email.','forgot':'Recover account.','reset':'Set a new password.'}[mode]!;
  String get detail=>{'login':'Sign in to your Insane Straps profile.','register':'A verification code is required before your first login.','verify':'Enter the 6-digit code sent to your email.','forgot':'We will send a reset code to your registered email.','reset':'Enter the code and choose a new password.'}[mode]!;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const SizedBox(height: 16),
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: red.withOpacity(.13),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: red.withOpacity(.5)),
                    ),
                    child: const Icon(Icons.bolt, color: red, size: 36),
                  ),
                  const SizedBox(height: 22),
                  const Text('INSANE STRAPS', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2, color: red)),
                  const SizedBox(height: 10),
                  Text(heading, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text(detail, style: const TextStyle(color: muted)),
                  const SizedBox(height: 24),
                  if (mode == 'login') ...[
                    field('Username or email', loginC),
                    field('Password', passwordC, secret: true),
                    Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => setState(() => mode = 'forgot'), child: const Text('Forgot password?'))),
                  ] else if (mode == 'register') ...[
                    field('Username', usernameC),
                    field('Email address', emailC, type: TextInputType.emailAddress),
                    field('Password (10+ characters)', passwordC, secret: true),
                  ] else if (mode == 'verify') ...[
                    field('Email address', emailC, type: TextInputType.emailAddress),
                    field('6-digit verification code', codeC, type: TextInputType.number),
                    TextButton(
                      onPressed: () async {
                        final d = await request('/auth/resend-verification', {'email': (pendingEmail.isEmpty ? emailC.text : pendingEmail).trim()});
                        if (d != null) message('${d['message']}');
                      },
                      child: const Text('Resend verification code'),
                    ),
                  ] else if (mode == 'forgot') ...[
                    field('Registered email', emailC, type: TextInputType.emailAddress),
                  ] else ...[
                    field('Email address', emailC, type: TextInputType.emailAddress),
                    field('Reset code', codeC, type: TextInputType.number),
                    field('New password (10+ characters)', newPasswordC, secret: true),
                  ],
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: busy ? null : submit,
                      style: FilledButton.styleFrom(backgroundColor: red, foregroundColor: Colors.white),
                      child: busy
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text({'login':'SIGN IN','register':'CREATE ACCOUNT','verify':'VERIFY EMAIL','forgot':'SEND RESET CODE','reset':'RESET PASSWORD'}[mode]!, style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (mode == 'login') ...[
                    TextButton(onPressed: () => setState(() => mode = 'register'), child: const Text('New here? Create an account')),
                    TextButton(onPressed: () => setState(() { pendingEmail = loginC.text.contains('@') ? loginC.text.trim() : 'hydraabhinav121@gmail.com'; emailC.text = pendingEmail; mode = 'verify'; }), child: const Text('Need to verify your email?')),
                  ] else if (mode != 'verify')
                    TextButton(onPressed: () => setState(() => mode = 'login'), child: const Text('Back to sign in')),
                  const SizedBox(height: 14),
                  const Text('Secure sign-in · Email verification · Discord linking optional', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: muted)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

}

class AppShell extends StatefulWidget { const AppShell({super.key}); @override State<AppShell> createState() => _AppShellState(); }
class _AppShellState extends State<AppShell> {
  int tab = 0;
  bool loading = true;
  String displayName = 'Insane User', username = '', bio = 'Configure your setup. Make it yours.';
  bool discordLinked = false;
  bool isOwner = false;
  String accountEmail = '';
  String accountRole = 'user';
  String discordName = '';
  String activePlan = 'Free';
  String proExpiry = '';
  Map<String, int> prices = {'day': 20, 'month': 120, 'lifetime': 500};
  List<String> profiles = ['Main Profile'];
  List<PaymentRequest> payments = [];
  List<String> presets = ['Default preset'];
  String activeGame = 'Free Fire';
  String performanceProfile = 'Maximum FPS';
  bool removeBlur = true, enableFpsDisplay = true, enableTextSizeChanger = false;
  final hideGuisController = TextEditingController(text: '0');
  final keyController = TextEditingController();
  bool showFlagEditor = false;
  String jsonText = const JsonEncoder.withIndent('  ').convert({'flags': <String, dynamic>{}});
  final secureStore = const FlutterSecureStorage();
  String apiToken = '';
  AppLinks? appLinks;
  final flagsController = TextEditingController(text: const JsonEncoder.withIndent('  ').convert({'flags': <String, dynamic>{}}));

  bool get backendConfigured => apiBase.trim().isNotEmpty;
  @override void initState() { super.initState(); _load(); _listenForDiscordCallback(); }
  Future<void> _listenForDiscordCallback() async {
    try { appLinks = AppLinks(); appLinks!.uriLinkStream.listen((uri) { if (uri.scheme == 'insanestraps' && uri.host == 'oauth' && uri.path == '/discord') { final ticket = uri.queryParameters['ticket']; if (ticket != null) _exchangeDiscordTicket(ticket); } }); } catch (_) {}
  }
  Future<void> _exchangeDiscordTicket(String ticket) async {
    if (!backendConfigured) return;
    try { final r = await http.post(Uri.parse('$apiBase/auth/discord/exchange'), headers: {'Content-Type':'application/json'}, body: jsonEncode({'ticket': ticket})).timeout(const Duration(seconds: 15)); if (r.statusCode != 200) { notice('Discord link failed. Please try again.'); return; } final data = jsonDecode(r.body) as Map<String,dynamic>; apiToken = data['token'] as String; await secureStore.write(key: 'apiToken', value: apiToken); final user = Map<String,dynamic>.from(data['user'] as Map); setState(() { discordLinked = true; discordName = '${user['globalName'] ?? user['username'] ?? 'Discord user'}'; }); await _save(); notice('Discord account linked.'); } catch (_) { notice('Could not complete Discord linking.'); }
  }
  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    apiToken = await secureStore.read(key: 'apiToken') ?? '';
    setState(() {
      displayName = p.getString('displayName') ?? displayName;
      username = p.getString('username') ?? username;
      bio = p.getString('bio') ?? bio;
      profiles = p.getStringList('profiles') ?? profiles;
      presets = p.getStringList('presets') ?? presets;
      activeGame = p.getString('activeGame') ?? activeGame;
      performanceProfile = p.getString('performanceProfile') ?? performanceProfile;
      removeBlur = p.getBool('ff_removeBlur') ?? removeBlur;
      enableFpsDisplay = p.getBool('ff_enableFps') ?? enableFpsDisplay;
      enableTextSizeChanger = p.getBool('ff_textSizeChanger') ?? enableTextSizeChanger;
      hideGuisController.text = p.getString('ff_hideGuis') ?? '0';
      jsonText = p.getString('jsonText') ?? jsonText;
      flagsController.text = jsonText;
      activePlan = p.getString('activePlan') ?? 'Free';
      proExpiry = p.getString('proExpiry') ?? '';
      discordLinked = p.getBool('discordLinked') ?? false;
      discordName = p.getString('discordName') ?? '';
      final savedPrices = p.getString('prices');
      if (savedPrices != null) { try { prices = Map<String, int>.from(jsonDecode(savedPrices).map((k,v) => MapEntry('$k', (v as num).toInt()))); } catch (_) {} }
      final savedPayments = p.getString('payments');
      if (savedPayments != null) { try { payments = (jsonDecode(savedPayments) as List).map((e) => PaymentRequest.fromJson(Map<String,dynamic>.from(e))).toList(); } catch (_) {} }
      loading = false;
    });
    if (backendConfigured) { try { final r = await http.get(Uri.parse('$apiBase/config/prices')).timeout(const Duration(seconds: 8)); if (r.statusCode == 200) { final m = Map<String,dynamic>.from(jsonDecode(r.body)); setState(() { prices = m.map((k,v) => MapEntry(k, (v as num).toInt())); }); } } catch (_) {} }
    if (backendConfigured && apiToken.isNotEmpty) { try { final r = await http.get(Uri.parse('$apiBase/me'), headers: {'Authorization':'Bearer $apiToken'}).timeout(const Duration(seconds: 8)); if (r.statusCode == 200) { final data = Map<String,dynamic>.from(jsonDecode(r.body)); final user = Map<String,dynamic>.from(data['user']); final ent = Map<String,dynamic>.from(data['entitlement']); setState(() { accountRole = '${data['role'] ?? user['role'] ?? 'user'}'; isOwner = accountRole == 'owner'; accountEmail = '${user['email'] ?? ''}'; username = '${user['username'] ?? username}'; displayName = '${(user['profile'] is Map ? user['profile']['displayName'] : null) ?? user['globalName'] ?? user['username'] ?? displayName}'; discordLinked = user['discordId'] != null; discordName = '${user['globalName'] ?? user['username'] ?? 'Discord user'}'; final planId = '${ent['planId'] ?? 'free'}'; activePlan = planId == 'free' ? 'Free' : _planName(planId); proExpiry = ent['expiresAt'] == null ? (planId == 'lifetime' ? 'Lifetime' : '') : '${ent['expiresAt']}'; }); final pr = await http.get(Uri.parse('$apiBase/payments/mine'), headers: {'Authorization':'Bearer $apiToken'}).timeout(const Duration(seconds: 8)); if (pr.statusCode == 200) { final rows = (jsonDecode(pr.body) as List).map((e) => PaymentRequest.fromJson(Map<String,dynamic>.from(e))).toList(); setState(() => payments = rows); } await _save(); } else if (r.statusCode == 401) { apiToken = ''; await secureStore.delete(key: 'apiToken'); } } catch (_) {} }
  }
  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('displayName', displayName); await p.setString('username', username); await p.setString('bio', bio);
    await p.setStringList('profiles', profiles); await p.setStringList('presets', presets);
    await p.setString('activeGame', activeGame); await p.setString('performanceProfile', performanceProfile);
    await p.setBool('ff_removeBlur', removeBlur); await p.setBool('ff_enableFps', enableFpsDisplay);
    await p.setBool('ff_textSizeChanger', enableTextSizeChanger); await p.setString('ff_hideGuis', hideGuisController.text);
    await p.setString('jsonText', jsonText); await p.setString('activePlan', activePlan); await p.setString('proExpiry', proExpiry);
    await p.setBool('discordLinked', discordLinked); await p.setString('discordName', discordName);
    await p.setString('prices', jsonEncode(prices)); await p.setString('payments', jsonEncode(payments.map((e) => e.toJson()).toList()));
  }
  void notice(String s) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s))); }
  Widget badge(String label, {bool hot = false}) => Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: hot ? red.withOpacity(.14) : Colors.white10, border: Border.all(color: hot ? red.withOpacity(.65) : Colors.white12), borderRadius: BorderRadius.circular(99)), child: Text(label, style: TextStyle(color: hot ? red : Colors.white, fontSize: 11, fontWeight: FontWeight.w800)));
  Widget panelCard(Widget child, {EdgeInsets padding = const EdgeInsets.all(16)}) => Container(padding: padding, decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withOpacity(.08))), child: child);
  Widget section(String text) => Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(text.toUpperCase(), style: const TextStyle(color: muted, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1.3)));
  Widget button(String label, IconData icon, VoidCallback? fn, {bool filled = false}) => SizedBox(height: 48, child: filled ? FilledButton.icon(onPressed: fn, icon: Icon(icon), label: Text(label), style: FilledButton.styleFrom(backgroundColor: red, foregroundColor: Colors.white)) : OutlinedButton.icon(onPressed: fn, icon: Icon(icon, color: red), label: Text(label), style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: red))));

  @override void dispose() { flagsController.dispose(); hideGuisController.dispose(); keyController.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) {
    final pages = [homePage(), profilePage(), accountsPage(), flagsPage(), proPage(), settingsPage()];
    return Scaffold(
      appBar: AppBar(title: const Row(children: [Icon(Icons.local_fire_department, color: red, size: 28), SizedBox(width: 8), Text('INSANE STRAPS', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2))]), actions: [Padding(padding: const EdgeInsets.only(right: 14), child: Center(child: badge(activePlan == 'Free' ? 'FREE' : 'PRO', hot: activePlan != 'Free')))]),
      body: loading ? const Center(child: CircularProgressIndicator(color: red)) : SafeArea(child: IndexedStack(index: tab, children: pages)),
      bottomNavigationBar: NavigationBar(backgroundColor: const Color(0xFF100D11), indicatorColor: red.withOpacity(.18), selectedIndex: tab, onDestinationSelected: (v) => setState(() => tab = v), destinations: const [NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'), NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'), NavigationDestination(icon: Icon(Icons.groups_outlined), selectedIcon: Icon(Icons.groups), label: 'Profiles'), NavigationDestination(icon: Icon(Icons.data_object), label: 'Flags'), NavigationDestination(icon: Icon(Icons.workspace_premium_outlined), selectedIcon: Icon(Icons.workspace_premium), label: 'Go Pro'), NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Settings')]),
    );
  }

  Widget homePage() => ListView(padding: const EdgeInsets.all(18), children: [
    Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(borderRadius: BorderRadius.circular(26), border: Border.all(color: red.withOpacity(.5)), gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF350A13), Color(0xFF171116), bg])), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.local_fire_department, color: red, size: 34), const SizedBox(height: 12), const Text('YOUR GAME. YOUR SETUP.', style: TextStyle(color: red, fontWeight: FontWeight.w900, letterSpacing: 1.2)), const SizedBox(height: 7), Text('Welcome, $displayName', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)), const SizedBox(height: 6), const Text('Your mobile control center for profiles, presets and membership.', style: TextStyle(color: muted)), const SizedBox(height: 18), Wrap(spacing: 8, runSpacing: 8, children: [badge(activePlan == 'Free' ? 'FREE MEMBER' : '$activePlan MEMBER', hot: activePlan != 'Free'), badge('${profiles.length} PROFILES'), badge('${presets.length} PRESETS')])])),
    const SizedBox(height: 18), section('Quick actions'), GridView.count(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 1.45, children: [_quick('Profiles', Icons.groups, 'Organize profiles', () => setState(() => tab = 2)), _quick('Performance', Icons.speed, performanceProfile, () => setState(() => tab = 3)), _quick('Go Pro', Icons.workspace_premium, 'See membership', () => setState(() => tab = 4)), _quick('Account', Icons.person, 'Profile & Discord', () => setState(() => tab = 1))]),
    const SizedBox(height: 18), section('Performance profile'), panelCard(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [DropdownButtonFormField<String>(value: performanceProfile, decoration: const InputDecoration(labelText: 'Optimization target'), items: const [DropdownMenuItem(value: 'Maximum FPS', child: Text('Maximum FPS')), DropdownMenuItem(value: 'Balanced', child: Text('Balanced')), DropdownMenuItem(value: 'Better Graphics', child: Text('Better Graphics')), DropdownMenuItem(value: 'Headshot Practice', child: Text('Headshot Practice'))], onChanged: (v) async { if (v == null) return; setState(() => performanceProfile = v); await _save(); notice('Insane Straps profile saved. In-game effects depend on supported game settings.'); }), const SizedBox(height: 8), DropdownButtonFormField<String>(value: activeGame, decoration: const InputDecoration(labelText: 'Game profile'), items: const [DropdownMenuItem(value: 'Roblox', child: Text('Roblox')), DropdownMenuItem(value: 'Free Fire', child: Text('Free Fire')), DropdownMenuItem(value: 'Free Fire MAX', child: Text('Free Fire MAX'))], onChanged: (v) async { if (v == null) return; setState(() => activeGame = v); await _save(); }), const SizedBox(height: 8), const Text('These profiles save recommendations; they do not force changes inside protected games or guarantee FPS/ping gains.', style: TextStyle(color: muted, fontSize: 12))])), const SizedBox(height: 18), section('Game library'),
    const Text('Launch supported games installed on this phone. Insane Straps does not modify protected game files or promise unsupported FPS boosts.', style: TextStyle(color: muted, fontSize: 12)),
    const SizedBox(height: 10),
    _gameCard('Roblox', 'com.roblox.client', Icons.sports_esports, 'Open Roblox'),
    const SizedBox(height: 9),
    _gameCard('Free Fire', 'com.dts.freefireth', Icons.local_fire_department, 'Open Free Fire'),
    const SizedBox(height: 9),
    _gameCard('Free Fire MAX', 'com.dts.freefiremax', Icons.bolt, 'Open Free Fire MAX'),
    const SizedBox(height: 18), section('Mobile status'), panelCard(Column(children: [ _statusRow(Icons.save_outlined, 'Local data', 'Saved on this device', true), const Divider(color: Colors.white10), _statusRow(Icons.discord, 'Discord', discordLinked ? 'Linked: $discordName' : 'Not linked', discordLinked), const Divider(color: Colors.white10), _statusRow(Icons.cloud_outlined, 'Secure backend', backendConfigured ? 'Configured' : 'Not configured', backendConfigured)])),
    if (!backendConfigured) ...[const SizedBox(height: 12), const Text('Online payments and Discord linking remain unavailable until a backend URL is configured. Local settings work on this device.', style: TextStyle(color: muted, fontSize: 12))],
  ]);
  Widget _gameCard(String name, String packageName, IconData icon, String actionLabel) => panelCard(Row(children: [Container(width: 44, height: 44, decoration: BoxDecoration(color: red.withOpacity(.12), borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: red)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(name, style: const TextStyle(fontWeight: FontWeight.w900)), const SizedBox(height: 3), const Text('Installed app launch shortcut', style: TextStyle(color: muted, fontSize: 11))])), const SizedBox(width: 8), OutlinedButton(onPressed: () => launchGame(packageName, name), child: Text(actionLabel))]));

  Future<void> launchGame(String packageName, String name) async {
    try {
      final intent = AndroidIntent(action: 'android.intent.action.MAIN', category: 'android.intent.category.LAUNCHER', package: packageName);
      await intent.launch();
    } catch (_) {
      if (!mounted) return;
      notice('$name could not be opened. Check that it is installed and available in your region.');
    }
  }

  Widget _quick(String title, IconData icon, String sub, VoidCallback fn) => InkWell(onTap: fn, borderRadius: BorderRadius.circular(18), child: panelCard(Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, color: red, size: 25), const SizedBox(height: 9), Text(title, style: const TextStyle(fontWeight: FontWeight.w900)), const SizedBox(height: 3), Text(sub, style: const TextStyle(color: muted, fontSize: 11))])));
  Widget _statusRow(IconData icon, String label, String status, bool ok) => Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(children: [Icon(icon, color: red), const SizedBox(width: 12), Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))), Flexible(child: Text(status, textAlign: TextAlign.end, style: TextStyle(color: ok ? Colors.greenAccent : muted, fontSize: 12)))]));

  Widget profilePage() => ListView(padding: const EdgeInsets.all(18), children: [
    panelCard(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Container(width: 68, height: 68, decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF290A11), border: Border.all(color: red, width: 2)), child: const Icon(Icons.person, color: red, size: 36)), const SizedBox(width: 14), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(displayName, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)), const SizedBox(height: 6), badge(activePlan == 'Free' ? 'FREE' : 'PRO MEMBER', hot: activePlan != 'Free'), const SizedBox(height: 6), Text(discordLinked ? 'Discord: $discordName' : 'Discord not connected', style: const TextStyle(color: muted, fontSize: 12))])), IconButton(onPressed: editProfile, icon: const Icon(Icons.edit, color: red))]), const SizedBox(height: 16), Text(bio, style: const TextStyle(color: muted, height: 1.5)), const SizedBox(height: 14), button(discordLinked ? 'Discord linked' : 'Connect Discord', Icons.discord, connectDiscord, filled: true), const SizedBox(height: 7), const Text('Discord OAuth requires a configured backend and Discord application. This button will report setup status if these are not configured.', style: TextStyle(color: muted, fontSize: 11))])),
    const SizedBox(height: 16), section('Membership'), panelCard(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(activePlan == 'Free' ? 'You are on the Free plan' : 'Your plan: $activePlan', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)), if (proExpiry.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Expires: $proExpiry', style: const TextStyle(color: muted))), const SizedBox(height: 12), button('View Pro benefits', Icons.workspace_premium, () => setState(() => tab = 4))]))
  ]);
  Future<void> editProfile() async { final n = TextEditingController(text: displayName), u = TextEditingController(text: username), b = TextEditingController(text: bio); final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: const Text('Edit profile'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: n, decoration: const InputDecoration(labelText: 'Display name')), const SizedBox(height: 10), TextField(controller: u, decoration: const InputDecoration(labelText: 'Username (local label)')), const SizedBox(height: 10), TextField(controller: b, maxLines: 3, decoration: const InputDecoration(labelText: 'Bio'))])), actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save'))])); if (ok == true) { setState(() { if (n.text.trim().isNotEmpty) displayName = n.text.trim(); username = u.text.trim().replaceAll(RegExp(r'\s+'), '').replaceFirst(RegExp(r'^@'), ''); bio = b.text.trim(); }); await _save(); } n.dispose(); u.dispose(); b.dispose(); }
  Future<void> connectDiscord() async { if (!backendConfigured) { notice('Discord linking is not configured yet. Set INSANE_API_BASE_URL after deploying the backend.'); return; } final uri = Uri.parse('$apiBase/auth/discord/start'); if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) notice('Could not open Discord authorization.'); }

  Widget accountsPage() => ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text('YOUR PROFILES', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          const Text('These are local profile labels, not saved account credentials.', style: TextStyle(color: muted)),
          const SizedBox(height: 14),
          ...profiles.asMap().entries.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: panelCard(ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFF2B0B12),
                    child: Icon(Icons.person, color: red),
                  ),
                  title: Text(e.value),
                  subtitle: const Text('Saved on this device', style: TextStyle(color: muted)),
                  trailing: IconButton(
                    onPressed: profiles.length <= 1
                        ? null
                        : () async {
                            setState(() => profiles.removeAt(e.key));
                            await _save();
                          },
                    icon: const Icon(Icons.delete_outline, color: red),
                  ),
                )),
              )),
          button('Add profile', Icons.add, addProfile, filled: true),
          const SizedBox(height: 14),
          section('Configuration presets'),
          ...presets.map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: panelCard(ListTile(
                  leading: const Icon(Icons.tune, color: red),
                  title: Text(p),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: red),
                    onPressed: presets.length <= 1
                        ? null
                        : () async {
                            setState(() => presets.remove(p));
                            await _save();
                          },
                  ),
                )),
              )),
          button('Add preset', Icons.add_box_outlined, addPreset),
        ],
      );
  Future<void> addProfile() async { final c = TextEditingController(); final v = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(title: const Text('New profile'), content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(labelText: 'Profile name')), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Add'))])); c.dispose(); if (v != null && v.isNotEmpty && !profiles.contains(v)) { setState(() => profiles.add(v)); await _save(); } }
  Future<void> addPreset() async { final c = TextEditingController(); final v = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(title: const Text('New preset'), content: TextField(controller: c, decoration: const InputDecoration(labelText: 'Preset name')), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Add'))])); c.dispose(); if (v != null && v.isNotEmpty && !presets.contains(v)) { setState(() => presets.add(v)); await _save(); } }

  Widget flagsPage() => ListView(padding: const EdgeInsets.all(16), children: [const Text('INSANE STRAPS PERFORMANCE', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)), const SizedBox(height: 7), const Text('Saved settings and practical game preparation. Values below do not automatically modify Roblox or Free Fire.', style: TextStyle(color: muted)), const SizedBox(height: 12), SegmentedButton<bool>(segments: const [ButtonSegment(value: false, label: Text('FFlags Settings'), icon: Icon(Icons.tune)), ButtonSegment(value: true, label: Text('FFlags Editor'), icon: Icon(Icons.data_object))], selected: {showFlagEditor}, onSelectionChanged: (v) => setState(() => showFlagEditor = v.first)), const SizedBox(height: 12), if (!showFlagEditor) ...[panelCard(Column(children: [SwitchListTile(value: removeBlur, activeColor: red, title: const Text('Remove Blur Effect'), subtitle: const Text('Preference only; applies only if a supported game-side method exists.'), onChanged: (v) => setState(() => removeBlur = v)), const Divider(color: Colors.white10), SwitchListTile(value: enableFpsDisplay, activeColor: red, title: const Text('Enable FPS Display'), subtitle: const Text('Preference for FPS visibility; actual overlay is device/game dependent.'), onChanged: (v) => setState(() => enableFpsDisplay = v)), const Divider(color: Colors.white10), SwitchListTile(value: enableTextSizeChanger, activeColor: red, title: const Text('Enable Text Size Changer'), subtitle: const Text('Saved preference only.'), onChanged: (v) => setState(() => enableTextSizeChanger = v)), const Divider(color: Colors.white10), Padding(padding: const EdgeInsets.all(14), child: TextField(controller: hideGuisController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Hide GUIs value', helperText: 'Saved locally; no effect on the game unless supported.')))])), const SizedBox(height: 12), panelCard(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('PRE-GAME PREPARATION', style: TextStyle(fontWeight: FontWeight.w900)), const SizedBox(height: 8), const Text('• Choose Smooth/low graphics in the game settings if FPS is unstable.\n• Close heavy apps yourself and avoid playing while the phone is overheating.\n• Prefer a stable nearby Wi-Fi or mobile connection.\n• Headshot Practice provides training and sensitivity guidance, not auto-aim.', style: TextStyle(color: muted, height: 1.5)), const SizedBox(height: 10), button('Save settings', Icons.save, () async { await _save(); notice('Insane Straps settings saved. Game effects are not guaranteed.'); }, filled: true), const SizedBox(height: 8), button('Save And Launch ${activeGame}', Icons.rocket_launch, () async { await _save(); final pkg = activeGame == 'Roblox' ? 'com.roblox.client' : activeGame == 'Free Fire MAX' ? 'com.dts.freefiremax' : 'com.dts.freefireth'; await launchGame(pkg, activeGame); }), const SizedBox(height: 8), button('Close settings', Icons.close, () => setState(() => tab = 0))])),] else ...[SizedBox(height: 330, child: TextField(controller: flagsController, onChanged: (v) { jsonText = v; }, expands: true, maxLines: null, style: const TextStyle(fontFamily: 'monospace', fontSize: 13), decoration: const InputDecoration(hintText: '{ }'))), const SizedBox(height: 10), Row(children: [Expanded(child: button('Validate', Icons.check_circle_outline, validateJson)), const SizedBox(width: 8), Expanded(child: button('Format', Icons.auto_fix_high, formatJson, filled: true))]), const SizedBox(height: 8), button('Save configuration', Icons.save_outlined, () async { await _save(); notice('Insane Straps configuration saved locally; it is not injected into a game.'); })]]);
  Future<void> validateJson() async { try { jsonDecode(jsonText); notice('Valid JSON ✓'); } catch (e) { notice('Invalid JSON: ${e.toString().split('\n').first}'); } }
  Future<void> formatJson() async { try { final obj = jsonDecode(jsonText); setState(() { jsonText = const JsonEncoder.withIndent('  ').convert(obj); flagsController.text = jsonText; flagsController.selection = TextSelection.collapsed(offset: jsonText.length); }); await _save(); notice('JSON formatted and saved.'); } catch (_) { notice('Cannot format invalid JSON. Validate it first.'); } }

  Widget proPage() => ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: const LinearGradient(colors: [Color(0xFF3B0914), Color(0xFF151116)]),
              border: Border.all(color: red.withOpacity(.5)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.workspace_premium, color: red, size: 38),
                SizedBox(height: 12),
                Text('INSANE STRAPS PRO', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900)),
                SizedBox(height: 7),
                Text('More profiles, advanced settings and customization. No fake FPS promises.', style: TextStyle(color: muted)),
              ],
            ),
          ),
          const SizedBox(height: 18),
          section('Choose your plan'),
          ...plans.map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: panelCard(Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(color: red.withOpacity(.12), borderRadius: BorderRadius.circular(13)),
                      child: Icon(
                        p.id == 'lifetime'
                            ? Icons.workspace_premium
                            : p.id == 'month'
                                ? Icons.calendar_month
                                : Icons.bolt,
                        color: red,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                          Text(p.duration, style: const TextStyle(color: muted, fontSize: 12)),
                        ],
                      ),
                    ),
                    Text('₹${prices[p.id] ?? p.defaultPrice}', style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => showPayment(p),
                      icon: const Icon(Icons.arrow_forward_ios, color: red, size: 18),
                    ),
                  ],
                )),
              )),
          const SizedBox(height: 8),
          section('Pro benefits'),
          panelCard(Column(
            children: [
              _benefit(Icons.tune, 'Advanced settings', 'Saved FFlags editor and configuration validation.'),
              _benefit(Icons.palette_outlined, 'Game profiles', 'More profile and preset organization.'),
              _benefit(Icons.verified, 'Pro membership', 'Membership verified through the backend.'),
              _benefit(Icons.sports_esports, 'Game support', 'Roblox, Free Fire and Free Fire MAX preparation tools.'),
            ],
          )),
          const SizedBox(height: 14),
          section('Payment requests'),
          if (payments.isEmpty)
            panelCard(const Text('No payment requests yet.', style: TextStyle(color: muted)))
          else
            ...payments.reversed.map((p) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: panelCard(ListTile(
                    title: Text('${_planName(p.planId)} · ₹${p.amount}'),
                    subtitle: Text('Ref: ${p.transactionRef}\n${p.createdAt}', style: const TextStyle(color: muted)),
                    isThreeLine: true,
                    trailing: badge(p.status.toUpperCase(), hot: p.status == 'approved'),
                  )),
                )),
          const SizedBox(height: 8),
          const Text('UPI payments require independent verification by the owner. Local demo status does not grant real Pro.', style: TextStyle(color: muted, fontSize: 12)),
          const SizedBox(height: 14),
          _redeemKeyCard(),
        ],
      );
  Widget _benefit(IconData icon, String title, String sub) => Padding(padding: const EdgeInsets.symmetric(vertical: 9), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, color: red), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 3), Text(sub, style: const TextStyle(color: muted, fontSize: 12))]))]));
  String _planName(String id) { for (final p in plans) { if (p.id == id) return p.name; } return id; }
  Widget _redeemKeyCard() => panelCard(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('REDEEM INSANE STRAPS PRO KEY', style: TextStyle(fontWeight: FontWeight.w900)), const SizedBox(height: 8), const Text('Connect Discord and configure the backend to redeem a real membership key.', style: TextStyle(color: muted, fontSize: 12)), const SizedBox(height: 10), TextField(controller: keyController, decoration: const InputDecoration(labelText: 'Premium key', hintText: 'Paste key from Insane Straps owner')), const SizedBox(height: 8), button('Redeem key', Icons.key, redeemPremiumKey, filled: true)]));
  Future<void> redeemPremiumKey() async { final key = keyController.text.trim(); if (key.isEmpty) { notice('Enter an Insane Straps key.'); return; } if (!backendConfigured || apiToken.isEmpty) { notice('Connect Discord and configure the Insane Straps backend first.'); return; } try { final r = await http.post(Uri.parse('$apiBase/keys/redeem'), headers: {'Content-Type':'application/json', 'Authorization':'Bearer $apiToken'}, body: jsonEncode({'key': key})).timeout(const Duration(seconds: 12)); if (r.statusCode != 200) { notice('Key rejected: ${r.statusCode == 409 ? 'already used or unavailable' : 'check key and account'}'); return; } final data = Map<String,dynamic>.from(jsonDecode(r.body)); setState(() { activePlan = _planName('${data['planId']}'); proExpiry = data['expiresAt'] == null ? 'Lifetime' : '${data['expiresAt']}'; }); await _save(); keyController.clear(); notice('Insane Straps Pro activated.'); } catch (_) { notice('Could not contact the Insane Straps key service.'); } }

  Future<void> showPayment(Plan plan) async {
    final controller = TextEditingController();
    final amount = prices[plan.id] ?? plan.defaultPrice;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: panel,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('UPI PAYMENT', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.3)),
              const SizedBox(height: 6),
              Text('${plan.name} · ₹$amount', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              Text(plan.duration, style: const TextStyle(color: muted)),
              const SizedBox(height: 14),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                  child: Image.asset('assets/payment_qr.png', width: 250, height: 250, fit: BoxFit.contain),
                ),
              ),
              const SizedBox(height: 10),
              const Text('Scan this QR in your UPI app and pay the exact amount. Verify the receiver name before confirming payment.', style: TextStyle(color: muted, fontSize: 12)),
              const SizedBox(height: 14),
              TextField(controller: controller, decoration: const InputDecoration(labelText: 'UPI transaction reference / UTR', hintText: 'Enter your transaction reference')),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () async {
                    final ref = controller.text.trim();
                    if (ref.length < 6) {
                      notice('Enter a valid transaction reference.');
                      return;
                    }
                    Navigator.pop(ctx);
                    await submitPayment(plan, amount, ref);
                  },
                  icon: const Icon(Icons.send),
                  label: const Text('Submit for admin approval'),
                  style: FilledButton.styleFrom(backgroundColor: red),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    controller.dispose();
  }

  Future<void> submitPayment(Plan plan, int amount, String ref) async { if (payments.any((p) => p.transactionRef.toLowerCase() == ref.toLowerCase())) { notice('That transaction reference has already been submitted on this device.'); return; } final request = PaymentRequest(id: DateTime.now().microsecondsSinceEpoch.toString(), planId: plan.id, transactionRef: ref, createdAt: DateTime.now().toIso8601String(), status: 'pending', amount: amount); if (backendConfigured) { if (apiToken.isEmpty) { notice('Connect Discord before submitting a payment request.'); return; } try { final response = await http.post(Uri.parse('$apiBase/payments'), headers: {'Content-Type':'application/json', 'Authorization':'Bearer $apiToken'}, body: jsonEncode({'planId': plan.id, 'amount': amount, 'transactionRef': ref})).timeout(const Duration(seconds: 12)); if (response.statusCode < 200 || response.statusCode >= 300) { notice('Server rejected the request (${response.statusCode}).'); return; } final data = Map<String,dynamic>.from(jsonDecode(response.body)); final serverRequest = PaymentRequest(id: '${data['id']}', planId: plan.id, transactionRef: ref, createdAt: request.createdAt, status: 'pending', amount: amount); setState(() => payments.add(serverRequest)); } catch (_) { notice('Could not reach payment service. No request was submitted.'); return; } } else { setState(() => payments.add(request)); } await _save(); notice(backendConfigured ? 'Payment request sent. Pro activates after admin approval.' : 'Saved as a local demo request only. Configure the backend for real admin review.'); }

  Widget settingsPage() => ListView(padding: const EdgeInsets.all(18), children: [const Text('SETTINGS', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900)), const SizedBox(height: 14), panelCard(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('App status', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)), const SizedBox(height: 10), _statusRow(Icons.cloud_done, 'Backend', backendConfigured ? apiBase : 'Not configured', backendConfigured), const Divider(color: Colors.white10), _statusRow(Icons.storage, 'Local persistence', 'Enabled', true), const Divider(color: Colors.white10), _statusRow(Icons.lock_outline, 'Payment review', backendConfigured ? 'Backend request mode' : 'Local demo only', backendConfigured)])), const SizedBox(height: 14), section('Account & security'), panelCard(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Signed in as $username${accountEmail.isNotEmpty ? ' · $accountEmail' : ''}', style: const TextStyle(fontWeight: FontWeight.w700)), const SizedBox(height: 6), Text(isOwner ? 'Owner access verified by the backend.' : 'Standard account · Discord linking is optional.', style: const TextStyle(color: muted)), const SizedBox(height: 12), if (isOwner) ...[button('Edit server prices', Icons.price_change, editPrices), const SizedBox(height: 8), button('Admin payment queue', Icons.fact_check, openAdminQueue), const SizedBox(height: 8), button('Premium key manager', Icons.key, openKeyManager), const SizedBox(height: 8)], button('Log out', Icons.logout, () async { await secureStore.delete(key: 'apiToken'); if (context.mounted) Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const AuthScreen()), (route) => false); })])), const SizedBox(height: 14), panelCard(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Build configuration', style: TextStyle(fontWeight: FontWeight.w900)), const SizedBox(height: 7), Text(backendConfigured ? 'API URL configured: $apiBase' : 'Build with --dart-define=INSANE_API_BASE_URL=https://your-api.example to enable backend requests.', style: const TextStyle(color: muted, fontSize: 12))]))]);
  Future<void> openKeyManager() async {
    if (!backendConfigured || apiToken.isEmpty) {
      notice('Configure the Insane Straps backend and sign in with the owner Discord account.');
      return;
    }
    final qty = TextEditingController(text: '1');
    final uses = TextEditingController(text: '1');
    String plan = 'month';
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, localSet) => AlertDialog(
          title: const Text('Insane Straps · Owner Key Manager'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: plan,
                  decoration: const InputDecoration(labelText: 'Membership plan'),
                  items: const [
                    DropdownMenuItem(value: 'day', child: Text('1 Day Pro')),
                    DropdownMenuItem(value: 'month', child: Text('1 Month Pro')),
                    DropdownMenuItem(value: 'lifetime', child: Text('Lifetime Pro')),
                  ],
                  onChanged: (value) {
                    if (value != null) localSet(() => plan = value);
                  },
                ),
                TextField(controller: qty, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Number of keys (1–50)')),
                TextField(controller: uses, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Uses per key (1 = single-use)')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final q = int.tryParse(qty.text) ?? 0;
                final u = int.tryParse(uses.text) ?? 0;
                if (q < 1 || q > 50 || u < 1 || u > 500) {
                  notice('Quantity must be 1–50 and uses 1–500.');
                  return;
                }
                try {
                  final response = await http.post(
                    Uri.parse('$apiBase/admin/keys'),
                    headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $apiToken'},
                    body: jsonEncode({'planId': plan, 'quantity': q, 'uses': u}),
                  ).timeout(const Duration(seconds: 15));
                  if (response.statusCode != 201) {
                    notice(response.statusCode == 403 ? 'Owner only.' : 'Key generation failed (${response.statusCode}).');
                    return;
                  }
                  final data = Map<String, dynamic>.from(jsonDecode(response.body));
                  final codes = (data['keys'] as List).join('\n');
                  if (!mounted) return;
                  Navigator.pop(ctx);
                  await showDialog<void>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('Insane Straps keys created'),
                      content: SingleChildScrollView(child: SelectableText('$codes\n\nCopy and deliver these now. Plaintext will not be shown again.')),
                      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Done'))],
                    ),
                  );
                } catch (_) {
                  notice('Could not contact the Insane Straps key service.');
                }
              },
              child: const Text('Generate keys'),
            ),
          ],
        ),
      ),
    );
    qty.dispose();
    uses.dispose();
  }

  Future<void> editPrices() async {
    if (backendConfigured && apiToken.isEmpty) { notice('Link Discord first. Only the configured owner Discord account can change server prices.'); return; }
    final cs = {for (final p in plans) p.id: TextEditingController(text: '${prices[p.id] ?? p.defaultPrice}')};
    await showDialog<void>(context: context, builder: (ctx) => AlertDialog(title: Text(backendConfigured ? 'Edit server prices (owner only)' : 'Edit demo prices'), content: Column(mainAxisSize: MainAxisSize.min, children: [for (final p in plans) Padding(padding: const EdgeInsets.only(bottom: 9), child: TextField(controller: cs[p.id], keyboardType: TextInputType.number, decoration: InputDecoration(labelText: '${p.name} price (₹)')))]), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), FilledButton(onPressed: () async {
      final next = <String,int>{}; for (final p in plans) { final n = int.tryParse(cs[p.id]!.text); if (n == null || n < 1) { notice('Enter a positive price for every plan.'); return; } next[p.id] = n; }
      if (backendConfigured) { try { final r = await http.put(Uri.parse('$apiBase/admin/prices'), headers: {'Content-Type':'application/json', 'Authorization':'Bearer $apiToken'}, body: jsonEncode(next)).timeout(const Duration(seconds: 12)); if (r.statusCode != 200) { notice(r.statusCode == 403 ? 'Owner access only. Sign in with the owner Discord account.' : 'Server rejected price changes (${r.statusCode}).'); return; } } catch (_) { notice('Could not update server prices.'); return; } }
      setState(() => prices = next); Navigator.pop(ctx); await _save(); notice(backendConfigured ? 'Server prices updated.' : 'Demo prices saved on this device only.');
    }, child: const Text('Save'))])); for (final c in cs.values) { c.dispose(); }
  }
  Future<void> openAdminQueue() async {
    if (!backendConfigured) { notice('Deploy the backend before using secure owner-only review.'); return; }
    if (apiToken.isEmpty) { notice('Link Discord first. Only the configured owner Discord account can access payment review.'); return; }
    await showRemoteAdminQueue();
  }
  Future<void> showRemoteAdminQueue() async {
    try {
      final r = await http.get(Uri.parse('$apiBase/admin/payments'), headers: {'Authorization':'Bearer $apiToken'}).timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) { notice(r.statusCode == 403 ? 'Owner access only. Sign in with the owner Discord account.' : 'Owner authorization failed.'); return; }
      final rows = (jsonDecode(r.body) as List).map((e) => Map<String,dynamic>.from(e)).toList();
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (ctx) => AlertDialog(title: const Text('Owner-only payment review'), content: SizedBox(width: 440, child: rows.isEmpty ? const Text('No payment requests.') : SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: rows.map((row) { final status = '${row['status']}'; return ListTile(title: Text('${_planName('${row['planId']}')} · ₹${row['amount']}'), subtitle: Text('${row['user']?['username'] ?? row['discordId']}\n${row['transactionRef']}\n$status'), isThreeLine: true, trailing: status == 'pending' ? PopupMenuButton<String>(onSelected: (v) => reviewRemotePayment('${row['id']}', v), itemBuilder: (_) => const [PopupMenuItem(value: 'approved', child: Text('Approve')), PopupMenuItem(value: 'rejected', child: Text('Reject'))], child: const Icon(Icons.more_vert)) : badge(status.toUpperCase(), hot: status == 'approved')); }).toList()))), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))]));
    } catch (_) { notice('Could not load the owner-only payment queue.'); }
  }
  Future<void> reviewRemotePayment(String id, String status) async {
    try { final r = await http.post(Uri.parse('$apiBase/admin/payments/$id/review'), headers: {'Content-Type':'application/json', 'Authorization':'Bearer $apiToken'}, body: jsonEncode({'status': status})).timeout(const Duration(seconds: 12)); if (r.statusCode != 200) { notice(r.statusCode == 403 ? 'Owner access only.' : 'Review failed (${r.statusCode}).'); return; } notice('Payment $status. The linked user entitlement was updated by the backend.'); await showRemoteAdminQueue(); } catch (_) { notice('Could not submit payment review.'); }
  }
  Future<void> showAdminQueue() async { await showDialog<void>(context: context, builder: (ctx) => AlertDialog(title: const Text('Payment review'), content: SizedBox(width: 400, child: payments.isEmpty ? const Text('No requests yet.') : SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: payments.map((p) => ListTile(title: Text('${_planName(p.planId)} · ₹${p.amount}'), subtitle: Text('${p.transactionRef}\n${p.status}'), isThreeLine: true, trailing: p.status == 'pending' ? PopupMenuButton<String>(onSelected: (v) => _changeStatus(p, v), itemBuilder: (_) => const [PopupMenuItem(value: 'approved', child: Text('Approve (demo only)')), PopupMenuItem(value: 'rejected', child: Text('Reject'))], child: const Icon(Icons.more_vert)) : badge(p.status.toUpperCase()))).toList()))), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))])); }
  Future<void> _changeStatus(PaymentRequest request, String status) async { if (backendConfigured) { notice('Use the protected backend admin panel to approve real payments.'); return; } setState(() { payments = payments.map((p) => p.id == request.id ? p.withStatus(status) : p).toList(); if (status == 'approved') { final plan = plans.firstWhere((p) => p.id == request.planId); activePlan = plan.name; proExpiry = plan.id == 'lifetime' ? 'Lifetime' : DateTime.now().add(Duration(hours: plan.id == 'day' ? 24 : 24 * 30)).toLocal().toString().split('.').first; } }); await _save(); notice('Local demo status changed only; this does not grant server-backed Pro.'); if (mounted) { Navigator.of(context).pop(); showAdminQueue(); } }
}
