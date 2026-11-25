import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planner/user/features/main_scaffold/main_user_scaffold_view.dart';
import 'package:season_planner/user/services/database_service.dart';
import 'package:season_planner/user/user_provider.dart';

/// Auswahl-Screen nach Erstregistrierung:
/// Option A: Einer bestehenden Flugschule beitreten
/// Option B: Neue Flugschule anlegen
class OnboardingChoiceView extends StatelessWidget {
  final bool isInitialOnboarding;

  const OnboardingChoiceView({super.key, this.isInitialOnboarding = true});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Flugschule zuordnen'),
        automaticallyImplyLeading: !isInitialOnboarding,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.paragliding, size: 64, color: cs.primary),
                  const SizedBox(height: 16),
                  Text(
                    'Wie möchtest du starten?',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Tritt einer oder mehreren bestehenden Flugschulen bei oder lege eine neue Flugschule an.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 28),
                  Card(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder:
                                (_) => JoinFlightSchoolView(
                                  isInitialOnboarding: isInitialOnboarding,
                                ),
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 26,
                              backgroundColor: cs.primaryContainer,
                              child: Icon(Icons.group_add, color: cs.primary),
                            ),
                            const SizedBox(width: 16),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Einer bestehenden Flugschule beitreten',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Wähle eine oder mehrere Flugschulen aus und sende eine Beitrittsanfrage.',
                                    style: TextStyle(
                                      color: Colors.black54,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Card(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder:
                                (_) => CreateFlightSchoolView(
                                  isInitialOnboarding: isInitialOnboarding,
                                ),
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 26,
                              backgroundColor: cs.secondaryContainer,
                              child: Icon(
                                Icons.add_business,
                                color: cs.onSecondaryContainer,
                              ),
                            ),
                            const SizedBox(width: 16),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Neue Flugschule anlegen',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Lege deine eigene Flugschule an und werde automatisch erster Admin.',
                                    style: TextStyle(
                                      color: Colors.black54,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (isInitialOnboarding) ...[
                    const SizedBox(height: 20),
                    TextButton(
                      onPressed: () {
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(
                            builder: (_) => MainUserScaffoldView(),
                          ),
                          (_) => false,
                        );
                      },
                      child: const Text('Später erledigen – direkt zur App'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Option A: Liste aller registrierten Flugschulen mit Mehrfachauswahl (Checkbox).
/// Kann sowohl im Onboarding als auch später aus „Mitgliedschaften verwalten“ aufgerufen werden.
class JoinFlightSchoolView extends StatefulWidget {
  final bool isInitialOnboarding;

  const JoinFlightSchoolView({super.key, this.isInitialOnboarding = false});

  @override
  State<JoinFlightSchoolView> createState() => _JoinFlightSchoolViewState();
}

class _JoinFlightSchoolViewState extends State<JoinFlightSchoolView> {
  final _db = DatabaseService();
  final _searchCtrl = TextEditingController();

  List<PublicFlightSchoolSummary> _schools = [];
  final Set<String> _selectedIds = {};
  Set<String> _alreadyMemberIds = {};
  bool _loading = true;
  bool _submitting = false;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _loadSchools();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSchools() async {
    setState(() => _loading = true);
    final user = context.read<UserProvider>().user;
    _alreadyMemberIds =
        (user?.flightSchools ?? const []).map((fs) => fs.id).toSet();

    final list = await _db.listAllFlightSchools();
    if (!mounted) return;
    setState(() {
      _schools = list;
      _loading = false;
    });
  }

  Future<void> _submit() async {
    if (_selectedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte wähle mindestens eine Flugschule aus.'),
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final count = await _db.requestJoinFlightSchools(_selectedIds.toList());
      final freshUser = await _db.getUserInformation();
      if (freshUser != null && mounted) {
        context.read<UserProvider>().setUser(freshUser);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            count == 1
                ? 'Beitrittsanfrage gesendet! Ein Admin der Flugschule wird sie prüfen.'
                : '$count Beitrittsanfragen gesendet! Die Admins werden sie prüfen.',
          ),
        ),
      );

      if (widget.isInitialOnboarding) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => MainUserScaffoldView()),
          (_) => false,
        );
      } else {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Anfrage fehlgeschlagen: $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.trim().toLowerCase();
    final filtered =
        _schools.where((s) {
          if (q.isEmpty) return true;
          return s.displayName.toLowerCase().contains(q) ||
              s.displayShortName.toLowerCase().contains(q);
        }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Flugschule beitreten')),
      body: SafeArea(
        child: Column(
          children: [
            if (_submitting) const LinearProgressIndicator(minHeight: 2),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Flugschule suchen...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon:
                      _search.isEmpty
                          ? null
                          : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _search = '');
                            },
                          ),
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
            ),
            Expanded(
              child:
                  _loading
                      ? const Center(child: CircularProgressIndicator())
                      : filtered.isEmpty
                      ? const Center(
                        child: Text(
                          'Keine registrierten Flugschulen gefunden.',
                        ),
                      )
                      : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final s = filtered[index];
                          final alreadyIn = _alreadyMemberIds.contains(s.id);
                          final checked = _selectedIds.contains(s.id);

                          return Card(
                            child: CheckboxListTile(
                              value: alreadyIn ? true : checked,
                              onChanged:
                                  alreadyIn || _submitting
                                      ? null
                                      : (v) {
                                        setState(() {
                                          if (v == true) {
                                            _selectedIds.add(s.id);
                                          } else {
                                            _selectedIds.remove(s.id);
                                          }
                                        });
                                      },
                              secondary: CircleAvatar(
                                backgroundColor:
                                    Theme.of(
                                      context,
                                    ).colorScheme.surfaceContainerHighest,
                                child:
                                    s.logoLink.isEmpty
                                        ? const Icon(Icons.flight)
                                        : ClipOval(
                                          child: Image.network(
                                            s.logoLink,
                                            width: 40,
                                            height: 40,
                                            fit: BoxFit.cover,
                                            errorBuilder:
                                                (_, __, ___) =>
                                                    const Icon(Icons.flight),
                                          ),
                                        ),
                              ),
                              title: Text(
                                s.displayName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(
                                alreadyIn
                                    ? 'Bereits Mitglied oder angefragt'
                                    : (s.displayShortName.isNotEmpty
                                        ? s.displayShortName
                                        : 'Beitritt anfragen'),
                              ),
                            ),
                          );
                        },
                      ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  onPressed:
                      _submitting || _selectedIds.isEmpty ? null : _submit,
                  icon: const Icon(Icons.send),
                  label: Text(
                    _selectedIds.isEmpty
                        ? 'Flugschulen auswählen'
                        : 'Beitritt anfragen (${_selectedIds.length})',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Option B: Neue Flugschule anlegen (Startwert subscription_status = pending).
class CreateFlightSchoolView extends StatefulWidget {
  final bool isInitialOnboarding;

  const CreateFlightSchoolView({super.key, this.isInitialOnboarding = false});

  @override
  State<CreateFlightSchoolView> createState() => _CreateFlightSchoolViewState();
}

class _CreateFlightSchoolViewState extends State<CreateFlightSchoolView> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _shortNameCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _shortNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      await DatabaseService().createFlightSchool(
        displayName: _nameCtrl.text.trim(),
        displayShortName: _shortNameCtrl.text.trim(),
      );

      final freshUser = await DatabaseService().getUserInformation();
      if (freshUser != null && mounted) {
        context.read<UserProvider>().setUser(freshUser);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Flugschule angelegt! Dein Abo wird nun aktiviert – Stammdaten kannst du bereits pflegen.',
          ),
          duration: Duration(seconds: 4),
        ),
      );

      if (widget.isInitialOnboarding) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => MainUserScaffoldView()),
          (_) => false,
        );
      } else {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Anlegen fehlgeschlagen: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Neue Flugschule anlegen')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      color: Theme.of(
                        context,
                      ).colorScheme.primaryContainer.withValues(alpha: 0.4),
                      elevation: 0,
                      child: const Padding(
                        padding: EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Du wirst automatisch als erster Admin eingetragen. '
                                'Die 4 Standardrollen (Fluglehrer, Anwärter, Sicherheitstrainer, Tandempilot) werden automatisch angelegt. '
                                'Nach Freischaltung deines Abos stehen Events & Personalverwaltung vollständig bereit.',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Name der Flugschule *',
                        hintText: 'z. B. Flugschule Alpenflug',
                      ),
                      validator:
                          (v) =>
                              (v ?? '').trim().isEmpty
                                  ? 'Bitte gib einen Namen ein.'
                                  : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _shortNameCtrl,
                      maxLength: 25,
                      decoration: const InputDecoration(
                        labelText: 'Kurzname (max. 25 Zeichen)',
                        hintText: 'z. B. Alpenflug',
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 48,
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _create,
                        icon:
                            _saving
                                ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                                : const Icon(Icons.check),
                        label: const Text('Flugschule anlegen'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
