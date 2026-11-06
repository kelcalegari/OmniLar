import 'package:clock/clock.dart';

/// Um dia no meio do ciclo de demonstração (dia 5 a dia 4), longe da virada:
/// os dados do modo demo são gerados em relação a "hoje", então os testes que
/// dependem deles rodam sempre neste dia, e não no dia em que a suíte roda.
final DateTime testToday = DateTime(2026, 10, 20, 10);

/// Roda [body] com o relógio do app (`clock.now()`) começando em [day].
///
/// O relógio continua andando a partir do relógio de fora, então dentro de um
/// `testWidgets` ele avança junto com o tempo falso do `tester.pump`.
T atDate<T>(DateTime day, T Function() body) {
  final outer = clock;
  final offset = day.difference(outer.now());
  return withClock(Clock(() => outer.now().add(offset)), body);
}
