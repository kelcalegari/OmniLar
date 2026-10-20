import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/logging/omni_bloc_observer.dart';

class _TestCubit extends Cubit<int> {
  _TestCubit() : super(0);

  void triggerError() {
    addError(Exception('Erro de teste do Cubit'), StackTrace.current);
  }
}

abstract class _DummyState {}

class _DummyInitial extends _DummyState {}

class _DummyError extends _DummyState {
  final String message;
  _DummyError(this.message);
}

class _DummyErrorCubit extends Cubit<_DummyState> {
  _DummyErrorCubit() : super(_DummyInitial());

  void emitError() {
    emit(_DummyError('Falha simulada'));
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

  test('OmniBlocObserver intercepta transição para estado de erro no onChange', () {
    final observer = OmniBlocObserver();
    Bloc.observer = observer;

    final cubit = _DummyErrorCubit();
    expect(() => cubit.emitError(), returnsNormally);
    expect(cubit.state, isA<_DummyError>());
    cubit.close();
  });
}
