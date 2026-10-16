abstract class Failure {
  final String message;
  const Failure(this.message);

  @override
  String toString() => message;
}

class AuthFailure extends Failure {
  const AuthFailure(super.message);
}

/// Login recusado porque o e-mail da conta ainda não foi confirmado.
class EmailNotConfirmedFailure extends AuthFailure {
  final String email;
  const EmailNotConfirmedFailure(this.email)
    : super('Confirme seu e-mail para entrar.');
}

class ServerFailure extends Failure {
  const ServerFailure(super.message);
}

class ValidationFailure extends Failure {
  const ValidationFailure(super.message);
}

class NotFoundFailure extends Failure {
  const NotFoundFailure(super.message);
}
