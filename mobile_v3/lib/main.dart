import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'auth.dart';

void main() => runApp(const InsaneStrapsApp());

const red = Color(0xFFFF334F);
const gold = Color(0xFFD4AF37);
const bg = Color(0xFF0A0A0D);
const panel = Color(0xFF17171D);
const discordInvite = 'https://discord.gg/vaEXj2Yyey';
const discordUserUrl = 'https://discord.com/users/985486854159753256';

class IntroSplash extends StatefulWidget {
  const IntroSplash({super.key});
  @override State<IntroSplash> createState() => _IntroSplashState();
}
class _IntroSplashState extends State<IntroSplash> with TickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2300))..forward();
  static const _letters = 'InSaNe';
  @override void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 2600), () {
      if (mounted) Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const AppShell()));
    });
  }
  @override void dispose() { _c.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF030304),
    body: AnimatedBuilder(animation: _c, builder: (_, __) {
      final t = Curves.easeOutCubic.transform(_c.value);
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Transform.scale(scale: .65 + .35*t, child: Opacity(opacity: t, child: const Icon(Icons.workspace_premium_rounded, size: 104, color: gold))),
        const SizedBox(height: 26),
        Row(mainAxisSize: MainAxisSize.min, children: List.generate(_letters.length, (i) =>
          Opacity(opacity: ((_c.value*1.7)-i*.15).clamp(0.0, 1.0),
            child: Transform.translate(offset: Offset(0, 8*(1-((_c.value*1.7)-i*.15).clamp(0.0,1.0))),
              child: Text(_letters[i], style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: 2, color: Color(0xFFE7C46A))))))),
        const SizedBox(height: 10),
        Opacity(opacity: t, child: const Text('STRAPS', style: TextStyle(letterSpacing: 8, fontSize: 12, color: red, fontWeight: FontWeight.bold))),
      ]));
    }),
  );
}

class InsaneStrapsApp extends StatelessWidget {
  const InsaneStrapsApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'InSaNe Straps',
    theme: ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme.fromSeed(seedColor: gold, brightness: Brightness.dark),
      useMaterial3: true,
      cardTheme: const CardThemeData(color: panel, elevation: 0),
      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: panel,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      ),
    ),
    home: const IntroSplash(),
  );
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override State<AppShell> createState() => _AppShellState();
}
class _AppShellState extends State<AppShell> {
  int tab = 0;
  final flagsController = TextEditingController(text: '{\n  "DFIntTaskSchedulerTargetFps": 120\n}');
  String status = 'Local preview';
  @override void dispose() { flagsController.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) {
    final pages = [
      _home(), _games(), _plans(), _flags(), _account()
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [
          Icon(Icons.bolt, color: red), SizedBox(width: 8),
          Text('InSaNe ', style: TextStyle(fontWeight: FontWeight.w900)),
          Text('STRAPS', style: TextStyle(color: red, fontWeight: FontWeight.w900)),
        ]),
        actions: [Padding(padding: const EdgeInsets.only(right: 16), child: Center(child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: red.withValues(alpha: .13), borderRadius: BorderRadius.circular(30)),
          child: const Text('MOBILE', style: TextStyle(color: red, fontSize: 11, fontWeight: FontWeight.bold)),
        )))],
      ),
      body: SafeArea(child: IndexedStack(index: tab, children: pages)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab, onDestinationSelected: (v) => setState(() => tab = v),
        backgroundColor: panel, indicatorColor: gold.withValues(alpha: .20),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.grid_view_rounded), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.sports_esports_outlined), label: 'Games'),
          NavigationDestination(icon: Icon(Icons.workspace_premium_outlined), label: 'Pro'),
          NavigationDestination(icon: Icon(Icons.code_rounded), label: 'Fast Flags'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Account'),
        ],
      ),
    );
  }

  Widget _home() => ListView(padding: const EdgeInsets.all(18), children: [
    Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(colors: [Color(0xFF1B160A), Color(0xFF171116), Color(0xFF100D10)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        border: Border.all(color: gold.withValues(alpha: .45)),
      ),
      child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('CONTROL YOUR SETUP', style: TextStyle(color: gold, letterSpacing: 2, fontSize: 11, fontWeight: FontWeight.w800)),
        SizedBox(height: 14),
        Text('Your game.\nYour settings.', style: TextStyle(fontSize: 30, height: 1.08, fontWeight: FontWeight.w900)),
        SizedBox(height: 12),
        Text('A clean mobile companion for profiles, Fast Flags and account tools.', style: TextStyle(color: Colors.white70, height: 1.4)),
      ]),
    ),
    const SizedBox(height: 18),
    const Text('QUICK ACCESS', style: TextStyle(letterSpacing: 1.5, fontSize: 12, color: Colors.white54, fontWeight: FontWeight.bold)),
    const SizedBox(height: 10),
    Row(children: [
      Expanded(child: _quick('Profiles', Icons.layers_outlined, 'Manage presets', () => setState(() => tab = 2))),
      const SizedBox(width: 10),
      Expanded(child: _quick('Fast Flags', Icons.tune, 'Edit JSON', () => setState(() => tab = 2))),
    ]),
    const SizedBox(height: 10),
    _quick('Explore InSaNe Pro', Icons.workspace_premium, 'Plans from ₹39', () => setState(() => tab = 1), wide: true),
    const SizedBox(height: 18),
    _section('APP STATUS'),
    Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
      _statusRow(Icons.phone_android, 'Platform', 'Android'),
      const Divider(height: 22, color: Colors.white10),
      _statusRow(Icons.verified_user_outlined, 'Account services', 'Backend required'),
      const Divider(height: 22, color: Colors.white10),
      _statusRow(Icons.info_outline, 'Build channel', status),
    ]))),
    const SizedBox(height: 8),
    const Text('Note: settings are edited locally in this build. Game process controls and account licensing require platform-specific integration and a secure backend.', style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.4)),
  ]);


  Widget _games() => ListView(padding: const EdgeInsets.all(18), children: [
    const Text('Game dashboard', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900)),
    const SizedBox(height: 6),
    const Text('Choose a game and open its official app or store page.', style: TextStyle(color: Colors.white60)),
    const SizedBox(height: 18),
    _gameCard('Roblox', 'Open the installed game or its Play Store page', Icons.videogame_asset_rounded,
      'com.roblox.client', 'https://play.google.com/store/apps/details?id=com.roblox.client'),
    const SizedBox(height: 12),
    _gameCard('Free Fire', 'Open the installed game or its Play Store page', Icons.local_fire_department_rounded,
      'com.dts.freefireth', 'https://play.google.com/store/apps/details?id=com.dts.freefireth'),
    const SizedBox(height: 20),
    const Text('STRAPS TOOLS', style: TextStyle(letterSpacing: 1.5, fontSize: 12, color: Colors.white54, fontWeight: FontWeight.bold)),
    const SizedBox(height: 10),
    _quick('FPS & performance tips', Icons.speed, 'Open optimization guide', () => _showToolInfo('FPS & Boost', 'This screen can show supported Android performance tips. It cannot force a higher FPS cap or overclock your device; those depend on the game, device, and Android permissions.'), wide: true),
    const SizedBox(height: 10),
    _quick('Fast Flags', Icons.tune, 'Edit and validate JSON', () => setState(() => tab = 3), wide: true),
    const SizedBox(height: 10),
    _quick('AFK / reconnect helper', Icons.autorenew, 'Compatibility information', () => _showToolInfo('AFK & reconnect', 'A normal Android app cannot guarantee anti-AFK behavior or prevent a game server from disconnecting you. Automatic reconnect requires supported game-specific integration and may be restricted by the game.'), wide: true),
    const SizedBox(height: 10),
    _quick('Screenshot & screen recording', Icons.screen_share_outlined, 'Android capture permissions', () => _showToolInfo('Screen capture', 'Screen recording and floating overlays are not wired up in this build. Android requires a native MediaProjection consent flow for capture and special overlay permission for a floating Straps icon. Nothing is being recorded yet.'), wide: true),
    const SizedBox(height: 18),
    Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFF20190D), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFD4AF37).withValues(alpha: .45))),
      child: const Text('Compatibility note: Roblox Fast Flags are not guaranteed to work on Android, and this app currently validates JSON only—it does not inject flags into Roblox or Free Fire. We will only enable controls that are supported by Android and the games.', style: TextStyle(color: Color(0xFFE4D7B2), height: 1.4, fontSize: 12)),
    ),
  ]);

  Widget _gameCard(String name, String subtitle, IconData icon, String packageName, String storeUrlText) => Card(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0x44D4AF37))),
    child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [
      Container(width: 54, height: 54, decoration: BoxDecoration(color: const Color(0x22D4AF37), borderRadius: BorderRadius.circular(16)), child: Icon(icon, color: const Color(0xFFD4AF37), size: 30)),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(color: Colors.white60, fontSize: 12)),
      ])),
      PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert),
        onSelected: (v) async {
          if (v == 'launch') {
            try {
              await AndroidIntent(
                action: 'android.intent.action.MAIN',
                category: 'android.intent.category.LAUNCHER',
                package: packageName,
              ).launch();
              return;
            } catch (_) {
              if (mounted) _snack('$name may not be installed. Opening its store page.');
            }
          }
          final ok = await launchUrl(Uri.parse(storeUrlText), mode: LaunchMode.externalApplication);
          if (!ok && mounted) _snack('Could not open $name store page.');
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'launch', child: Text('Open installed game')),
          PopupMenuItem(value: 'store', child: Text('Open Play Store')),
        ],
      ),
    ])),
  );

  void _showToolInfo(String title, String message) {
    showDialog<void>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: panel,
      title: Text(title),
      content: Text(message, style: const TextStyle(height: 1.45, color: Colors.white70)),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Got it'))],
    ));
  }

  Widget _plans() => ListView(padding: const EdgeInsets.all(18), children: [
    const Text('Choose your plan', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
    const SizedBox(height: 6),
    const Text('Free for everyone. Upgrade when you want more.', style: TextStyle(color: Colors.white60)),
    const SizedBox(height: 18),
    _planCard('FREE', '₹0', 'Standard access', false, () => _snack('You are viewing the Free plan.')),
    _planCard('WEEKLY PRO', '₹39', '7 days', false, () => _paymentSheet('Weekly Pro', 39)),
    _planCard('MONTHLY PRO', '₹79', '30 days', true, () => _paymentSheet('Monthly Pro', 79)),
    _planCard('YEARLY PRO', '₹390', '365 days', false, () => _paymentSheet('Yearly Pro', 390)),
    _planCard('LIFETIME PRO', '₹699', 'No scheduled expiry', false, () => _paymentSheet('Lifetime Pro', 699)),
    const SizedBox(height: 8),
    const Text('Payments are not verified automatically in this build. Do not treat a payment screenshot as confirmation; Pro must be activated by the owner after checking the transaction.', style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.4)),
  ]);

  Widget _planCard(String name, String price, String term, bool featured, VoidCallback onTap) => Card(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: featured ? red : Colors.white10, width: featured ? 1.4 : 1)),
    child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [
      Container(width: 42, height: 42, decoration: BoxDecoration(color: red.withValues(alpha: .13), borderRadius: BorderRadius.circular(13)), child: const Icon(Icons.bolt, color: red)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(name, style: const TextStyle(fontSize: 12, color: red, fontWeight: FontWeight.w900, letterSpacing: 1)),
        const SizedBox(height: 4), Text(term, style: const TextStyle(color: Colors.white60, fontSize: 12)),
      ])),
      Text(price, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
      const SizedBox(width: 8),
      IconButton(onPressed: onTap, icon: const Icon(Icons.arrow_forward_ios, size: 16)),
    ])),
  );

  void _paymentSheet(String plan, int rupees) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 22, 20, 28 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.forum_rounded, color: red, size: 36),
            const SizedBox(height: 12),
            Text(plan, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text('Plan price: ₹$rupees', style: const TextStyle(color: red, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            const Text(
              'Continue to our Discord server to arrange payment and request Pro activation. Please do not send payment until the owner confirms the details.',
              style: TextStyle(color: Colors.white70, height: 1.45),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  final ok = await launchUrl(Uri.parse(discordInvite), mode: LaunchMode.externalApplication);
                  if (ctx.mounted && !ok) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Could not open Discord. Try the invite link in your browser.')),
                    );
                  }
                  if (ctx.mounted && ok) Navigator.of(ctx).pop();
                },
                icon: const Icon(Icons.forum_rounded),
                label: const Text('Continue to Discord server'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final ok = await launchUrl(Uri.parse(discordUserUrl), mode: LaunchMode.externalApplication);
                  if (ctx.mounted && !ok) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Could not open the Discord profile link.')),
                    );
                  }
                  if (ctx.mounted && ok) Navigator.of(ctx).pop();
                },
                icon: const Icon(Icons.person_outline),
                label: const Text('Open owner Discord profile'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _flags() => ListView(padding: const EdgeInsets.all(18), children: [
    const Text('Fast Flags', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
    const SizedBox(height: 6), const Text('Edit and validate a JSON configuration.', style: TextStyle(color: Colors.white60)),
    const SizedBox(height: 14),
    TextField(controller: flagsController, minLines: 12, maxLines: 22, style: const TextStyle(fontFamily: 'monospace', fontSize: 13), decoration: const InputDecoration(hintText: 'Paste JSON here', alignLabelWithHint: true)),
    const SizedBox(height: 12),
    Row(children: [
      Expanded(child: OutlinedButton.icon(onPressed: () { flagsController.text = '{\n  "DFIntTaskSchedulerTargetFps": 120\n}'; }, icon: const Icon(Icons.restart_alt), label: const Text('Reset sample'))),
      const SizedBox(width: 10),
      Expanded(child: FilledButton.icon(onPressed: () { try { final v = jsonDecode(flagsController.text); if (v is! Map<String, dynamic>) throw const FormatException('Root must be an object'); _snack('Valid JSON · ${v.length} top-level keys'); } catch (e) { _snack('Invalid JSON: ${e is FormatException ? e.message : e}'); } }, icon: const Icon(Icons.check_circle_outline), label: const Text('Validate'))),
    ]),
    const SizedBox(height: 12),
    const Text('Validation checks JSON syntax only. It does not prove a flag is supported or safe to apply. Export/apply integrations are not connected in this build.', style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.4)),
  ]);

  Widget _account() => const AuthPage();

  Widget _section(String text) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(text, style: const TextStyle(letterSpacing: 1.5, fontSize: 12, color: Colors.white54, fontWeight: FontWeight.bold)));
  Widget _statusRow(IconData icon, String label, String value) => Row(children: [Icon(icon, color: red, size: 20), const SizedBox(width: 12), Expanded(child: Text(label)), Text(value, style: const TextStyle(color: Colors.white54, fontSize: 12))]);
  Widget _quick(String title, IconData icon, String subtitle, VoidCallback onTap, {bool wide = false}) => Card(child: InkWell(borderRadius: BorderRadius.circular(16), onTap: onTap, child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [Container(width: 42, height: 42, decoration: BoxDecoration(color: red.withValues(alpha: .12), borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: red)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height: 4), Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 12))])), if (wide) const Icon(Icons.chevron_right, color: Colors.white54)]))));
  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

