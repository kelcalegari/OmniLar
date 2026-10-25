import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Chave de assinatura do release (ver Documentacao/assinatura_android.md).
// Vem das variáveis de ambiente (CI) ou de android/key.properties (máquina local).
// Nenhum dos dois vai para o repositório.
val keyProperties = Properties().apply {
    val keyPropertiesFile = rootProject.file("key.properties")
    if (keyPropertiesFile.exists()) keyPropertiesFile.inputStream().use { load(it) }
}

fun releaseSigningValue(property: String, envVar: String): String? =
    System.getenv(envVar)?.takeIf { it.isNotBlank() }
        ?: keyProperties.getProperty(property)?.takeIf { it.isNotBlank() }

val releaseStoreFile = releaseSigningValue("storeFile", "OMNILAR_KEYSTORE_PATH")
val releaseStorePassword = releaseSigningValue("storePassword", "OMNILAR_KEYSTORE_PASSWORD")
val releaseKeyAlias = releaseSigningValue("keyAlias", "OMNILAR_KEY_ALIAS")
val releaseKeyPassword = releaseSigningValue("keyPassword", "OMNILAR_KEY_PASSWORD")
val hasReleaseSigning = listOf(releaseStoreFile, releaseStorePassword, releaseKeyAlias, releaseKeyPassword)
    .all { it != null }
// Quem publica o APK (CI e scripts/publicar_apk_supabase.ps1) liga esta variável para que
// a falta da chave pare o build em vez de cair na chave de debug.
val requireReleaseSigning = System.getenv("OMNILAR_REQUIRE_RELEASE_SIGNING") == "true"

if (!hasReleaseSigning) {
    if (requireReleaseSigning) {
        throw GradleException(
            "Chave de release ausente: defina OMNILAR_KEYSTORE_PATH, OMNILAR_KEYSTORE_PASSWORD, " +
                "OMNILAR_KEY_ALIAS e OMNILAR_KEY_PASSWORD ou crie android/key.properties " +
                "(ver Documentacao/assinatura_android.md).",
        )
    }
    logger.warn("OmniLar: sem chave de release; o build release será assinado com a chave de debug.")
}

android {
    namespace = "br.com.omnilar.omni_lar"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "br.com.omnilar.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        getByName("debug") {
            val keystoreFile = file("debug.keystore")
            if (keystoreFile.exists()) {
                storeFile = keystoreFile
                storePassword = "android"
                keyAlias = "androiddebugkey"
                keyPassword = "android"
            }
            enableV1Signing = true
            enableV2Signing = true
        }
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(releaseStoreFile!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
                enableV1Signing = true
                enableV2Signing = true
            }
        }
    }

    buildTypes {
        release {
            // Sem a chave de release (build local de teste), assina com a de debug
            // para `flutter run --release` continuar funcionando.
            signingConfig = signingConfigs.getByName(if (hasReleaseSigning) "release" else "debug")
            // Mantém as classes do Firebase que o R8 removeria (ver proguard-rules.pro)
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
