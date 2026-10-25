import java.util.Properties

// Releasesleutel staat buiten de repo: ~/.config/macromatrix/key.properties (nooit in git)
val keystoreProperties = Properties().apply {
    val f = file(System.getProperty("user.home") + "/.config/macromatrix/key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "online.divinenet.macromatrix"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Nodig voor flutter_local_notifications (java.time op oudere Android-versies)
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // Testversie tegen de staging-server (bouwen met -P staging=true, zie server/tool/build_staging_apk.sh):
        // een eigen app-id en naam, zodat ze naast de gewone app staat en die niet raakt
        val staging = project.findProperty("staging") == "true"
        applicationId = "online.divinenet.macromatrix" + if (staging) ".staging" else ""
        manifestPlaceholders["appLabel"] = if (staging) "MM Staging" else "MacroMatrix"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Health Connect vraagt minstens Android 8 (API 26)
        minSdk = maxOf(26, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystoreProperties.containsKey("storeFile")) {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    // Geen versleutelde lijst van afhankelijkheden (alleen leesbaar door Google) in de APK, zoals IzzyOnDroid en F-Droid vragen
    dependenciesInfo {
        includeInApk = false
        includeInBundle = false
    }

    // Native bibliotheken gecomprimeerd in de APK: kleiner om te downloaden (IzzyOnDroid vraagt hoogstens ~30 MB)
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    buildTypes {
        release {
            // Met de echte sleutel als die er is; anders ongetekend (zo bouwt F-Droid, dat zelf ondertekent)
            if (keystoreProperties.containsKey("storeFile")) signingConfig = signingConfigs.getByName("release")
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
