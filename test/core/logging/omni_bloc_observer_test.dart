import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/logging/omni_bloc_observer.dart';

class _TestCubit extends Cubit<int> {
  _TestCubit() : super(0);

  void triggerError() {
    addError(Exception('Erro de teste do Cubit'), StackTrace.current);
  }
}

void main() {
  test('OmniBlocObserver intercepta erros de Cubit sem lançar exceção', () {
    final observer = OmniBlocObserver();
    Bloc.observer = observer;

    final cubit = _TestCubit();
    expect(() => cubit.triggerError(), returnsNormally);
    cubit.close();
  });
}
