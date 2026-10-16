import 'push_environment.dart';

PushEnvironment readPushEnvironment() =>
    const PushEnvironment(isIos: false, isStandalone: false, hasNotificationApi: false);
