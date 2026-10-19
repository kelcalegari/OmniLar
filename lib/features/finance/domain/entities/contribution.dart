import 'package:equatable/equatable.dart';
import '../../../../core/domain/value_objects/money.dart';

class Contribution extends Equatable {
  final String id;
  final String memberId;
  final Money amount;
  final DateTime date;
  final String? paymentMethodId;
  final String? proofAttachmentId;

  const Contribution({
    required this.id,
    required this.memberId,
    required this.amount,
    required this.date,
    this.paymentMethodId,
    this.proofAttachmentId,
  });

  Contribution copyWith({
    String? id,
    String? memberId,
    Money? amount,
    DateTime? date,
    String? paymentMethodId,
    String? proofAttachmentId,
  }) {
    return Contribution(
      id: id ?? this.id,
      memberId: memberId ?? this.memberId,
      amount: amount ?? this.amount,
      date: date ?? this.date,
      paymentMethodId: paymentMethodId ?? this.paymentMethodId,
      proofAttachmentId: proofAttachmentId ?? this.proofAttachmentId,
    );
  }

  @override
  List<Object?> get props => [id, memberId, amount, date, paymentMethodId, proofAttachmentId];
}
