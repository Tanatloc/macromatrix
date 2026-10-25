/// Hoe actief ben je? Niet meer bij de eerste stap: je begint op "licht actief", en na je eerste maaltijd vraagt een
/// kaart op Vandaag het één keer (dan betekenen je doelen pas iets). Aanpassen kan altijd in Profiel → Doelen.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n.dart';
import '../../nutrition/targets.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import 'kit.dart';

/// Instelling: de vraag staat nog open. Begint met "_": blijft op dit toestel. Wie de app al gebruikte, heeft ze
/// niet en krijgt de kaart dus nooit.
const activityAskKey = '_ask_activity';

/// Na de eerste stap: de vraag later stellen.
void askActivityLater(AppState s) => s.user.setSetting(activityAskKey, {'on': true});

/// De kaart tonen? Alleen als de vraag nog openstaat.
bool activityAskDue(AppState s) => s.user.setting(activityAskKey)?['on'] == true;

/// Gekozen (hier of in het profiel) of weggetikt: niet meer vragen.
void activityAsked(AppState s) {
  if (activityAskDue(s)) s.user.setSetting(activityAskKey, {'on': false});
}

/// Activiteit kiezen en bewaren; je doelen rekenen meteen opnieuw.
void _choose(AppState s, Activity a) {
  if (s.profile.activity != a) s.saveProfile(s.profile.copyWith(activity: a));
  activityAsked(s);
}

/// De vijf niveaus onder elkaar, met uitleg.
class ActivityChoices extends StatelessWidget {
  const ActivityChoices({super.key, required this.selected, required this.onChanged});
  final Activity selected;
  final ValueChanged<Activity> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final a in Activity.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Material(
              color: selected == a ? p.brandSoft : p.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: selected == a ? p.brand : p.line, width: selected == a ? 1.5 : 1),
              ),
              child: InkWell(
                key: ValueKey('activity-${a.name}'),
                customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onTap: () => onChanged(a),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              a.label,
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: p.ink),
                            ),
                            Text(a.description, style: TextStyle(fontSize: 12, color: p.ink3)),
                          ],
                        ),
                      ),
                      if (selected == a) Icon(Icons.check_rounded, size: 18, color: p.brand),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Onderblad met de vijf niveaus; een tik bewaart en sluit.
Future<void> showActivitySheet(BuildContext context) {
  final s = context.read<AppState>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr('How active are you?', 'Hoe actief ben je?'), style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              tr('This sets your energy goal. You can change it later under Profile.', 'Dit bepaalt je energiedoel. Je kunt het later aanpassen in je Profiel.'),
              style: TextStyle(fontSize: 13, color: ctx.pal.ink2),
            ),
            const SizedBox(height: 12),
            ActivityChoices(
              selected: s.profile.activity,
              onChanged: (a) {
                _choose(s, a);
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    ),
  );
}

/// Kaart op Vandaag na je eerste maaltijd: je doelen gaan uit van "licht actief"; klopt dat?
class ActivityAskCard extends StatefulWidget {
  const ActivityAskCard({super.key});

  @override
  State<ActivityAskCard> createState() => _ActivityAskCardState();
}

class _ActivityAskCardState extends State<ActivityAskCard> {
  /// Weggetikt: de instelling verandert het dagboek niet, dus zelf verbergen (zoals [GuestNudgeCard]).
  bool _hidden = false;

  @override
  Widget build(BuildContext context) {
    if (_hidden) return const SizedBox.shrink();
    final s = context.read<AppState>();
    final p = context.pal;
    return Panel(
      key: const ValueKey('activity-ask'),
      shadow: false,
      radius: 16,
      color: p.brandSoft,
      borderColor: p.brandSoft,
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      onTap: () => showActivitySheet(context),
      child: Row(
        children: [
          Icon(Icons.directions_walk_rounded, color: p.brand),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tr(
                'Your goals assume you are lightly active. How active are you?',
                'Je doelen gaan uit van licht actief. Hoe actief ben je?',
              ),
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.ink),
            ),
          ),
          IconButton(
            tooltip: tr('Lightly active is right', 'Licht actief klopt'),
            icon: Icon(Icons.close_rounded, size: 18, color: p.ink3),
            onPressed: () {
              activityAsked(s);
              setState(() => _hidden = true);
            },
          ),
        ],
      ),
    );
  }
}
