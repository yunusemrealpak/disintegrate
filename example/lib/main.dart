import 'dart:math' as math;

import 'package:disintegrate/disintegrate.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Compiling the program takes a moment. Paying for it here means the first
  // snap runs the shader instead of quietly falling back to a fade.
  await DisintegrateProgram.preload();
  runApp(const DisintegrateDemo());
}

class DisintegrateDemo extends StatelessWidget {
  const DisintegrateDemo({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'disintegrate',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B0B0D),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE0B341),
          surface: Color(0xFF15151A),
        ),
        useMaterial3: true,
      ),
      home: const RosterPage(),
    );
  }
}

class Member {
  const Member(this.name, this.role, this.portrait);

  final String name;
  final String role;

  /// Generated portraits, not photographs of anyone. A face is the point here:
  /// flat colour turns into flat dust, while skin, hair and cloth give the
  /// shader something worth breaking apart.
  final String portrait;
}

const List<Member> _roster = <Member>[
  Member('Eda Kaya', 'Flight lead', 'assets/portraits/p01.png'),
  Member('Mert Aydın', 'Navigator', 'assets/portraits/p02.png'),
  Member('Selin Arslan', 'Systems', 'assets/portraits/p03.png'),
  Member('Tolga Demir', 'Comms', 'assets/portraits/p04.png'),
  Member('Ayşe Yıldız', 'Medic', 'assets/portraits/p05.png'),
  Member('Kerem Şahin', 'Engineer', 'assets/portraits/p06.png'),
  Member('Nil Öztürk', 'Analyst', 'assets/portraits/p07.png'),
  Member('Barış Çelik', 'Pilot', 'assets/portraits/p08.png'),
  Member('Deniz Korkmaz', 'Quartermaster', 'assets/portraits/p09.png'),
  Member('Ece Polat', 'Geologist', 'assets/portraits/p10.png'),
  Member('Umut Ergin', 'Security', 'assets/portraits/p11.png'),
  Member('Zeynep Acar', 'Astrogator', 'assets/portraits/p12.png'),
];

class RosterPage extends StatefulWidget {
  const RosterPage({super.key});

  @override
  State<RosterPage> createState() => _RosterPageState();
}

class _RosterPageState extends State<RosterPage>
    with SingleTickerProviderStateMixin {
  // One controller for the whole screen. Every row reads a slice of it, which
  // is why a snap that takes out half the list still costs a single animation.
  late final AnimationController _snap = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
    reverseDuration: const Duration(milliseconds: 1600),
  );

  final math.Random _random = math.Random(7);
  final Set<int> _doomed = <int>{};
  late List<double> _delays = _rollDelays();

  List<double> _rollDelays() => List<double>.generate(
    _roster.length,
    (_) => _random.nextDouble() * 0.45,
  );

  bool get _snapped => _snap.value > 0.5;

  void _toggleSnap() {
    if (_snapped) {
      _snap.reverse();
      return;
    }
    _doomed
      ..clear()
      // Half of them. The choice is the joke; the stagger is what sells it.
      ..addAll(
        (List<int>.generate(_roster.length, (int i) => i)..shuffle(_random))
            .take(_roster.length ~/ 2),
      );
    _delays = _rollDelays();
    _snap.forward(from: 0);
  }

  /// A row's own progress: its slice of the shared timeline, re-normalised so
  /// every row still travels the full 0..1 no matter when it starts.
  double _progressFor(int index) {
    if (!_doomed.contains(index)) {
      return 0;
    }
    final double start = _delays[index];
    final double local = ((_snap.value - start) / (1 - start)).clamp(0.0, 1.0);
    return Curves.easeInSine.transform(local);
  }

  @override
  void dispose() {
    _snap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            const _Header(),
            Expanded(
              child: ListenableBuilder(
                listenable: _snap,
                builder: (BuildContext context, _) => ListView.builder(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 120),
                  itemCount: _roster.length,
                  itemBuilder: (BuildContext context, int index) =>
                      DisintegrateEffect(
                        progress: _progressFor(index),
                        seed: index * 31.7,
                        drift: const Offset(52, -58),
                        particleSize: 1.4,
                        turbulence: 34,
                        // The gap between rows is handed to the effect so the
                        // dust has somewhere to go; the card gives up its own
                        // margin in exchange and the layout looks the same.
                        spread: const EdgeInsets.fromLTRB(6, 40, 44, 6),
                        child: _MemberCard(member: _roster[index]),
                      ),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: ListenableBuilder(
        listenable: _snap,
        builder: (BuildContext context, _) => FloatingActionButton.extended(
          onPressed: _toggleSnap,
          backgroundColor: _snapped
              ? const Color(0xFF2A2A33)
              : const Color(0xFFE0B341),
          foregroundColor: _snapped ? Colors.white : Colors.black,
          icon: Icon(_snapped ? Icons.replay : Icons.back_hand_outlined),
          label: Text(
            _snapped ? 'BRING THEM BACK' : 'SNAP',
            style: const TextStyle(letterSpacing: 1.6, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'CREW MANIFEST',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              letterSpacing: 3,
              color: Colors.white54,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'disintegrate',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

const double _avatar = 46;

class _MemberCard extends StatelessWidget {
  const _MemberCard({required this.member});

  final Member member;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        // Light enough that the dust is visible against the background: dark
        // grains on a dark screen are just holes.
        color: const Color(0xFF1E1E27),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
      ),
      child: Row(
        children: <Widget>[
          ClipOval(
            child: Image.asset(
              member.portrait,
              width: _avatar,
              height: _avatar,
              fit: BoxFit.cover,
              // Decoded at the size it is painted at, not the size it ships at.
              cacheWidth: (_avatar * 3).round(),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  member.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  member.role,
                  style: const TextStyle(fontSize: 13, color: Colors.white54),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Colors.white24),
        ],
      ),
    );
  }
}
