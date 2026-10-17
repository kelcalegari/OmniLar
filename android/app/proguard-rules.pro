# Regras do R8 para o build de release.
# O Firebase do Flutter fala com o lado nativo por canais gerados pelo Pigeon;
# se o R8 remove ou renomeia essas classes, Firebase.initializeApp falha com
# "channel-error ... FirebaseCoreHostApi.initializeCore" só no release.
-keep class io.flutter.plugins.firebase.** { *; }
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**
