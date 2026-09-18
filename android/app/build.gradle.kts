plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.downoader"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.downoader"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24 // required by youtubedl-android
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        ndk {
            abiFilters.add("armeabi-v7a")
            abiFilters.add("arm64-v8a")
            abiFilters.add("x86_64")
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")

            // Flutter zet standaard isMinifyEnabled = true voor release. Dat
            // heeft deze app twee keer onbruikbaar gemaakt, beide keren alleen
            // in release en beide keren pas zichtbaar als een onleesbare
            // NoClassDefFoundError: eerst Jackson in youtubedl-android, daarna
            // Class.newInstance() in commons-compress. Beide leunen op
            // reflectie, waar R8 per definitie blind voor is.
            //
            // De winst staat er niet tegenover: van de ~174 MB is verreweg het
            // meeste de native python/ffmpeg-payload, die R8 niet aanraakt.
            // Het krimpen van de dex levert hooguit een paar MB op.
            //
            // proguard-rules.pro blijft bestaan en dekt de nu bekende gevallen,
            // dus wie dit weer aan wil zetten kan dat - maar test dan een
            // echte release-build op een toestel, niet alleen debug.
            isMinifyEnabled = false
            isShrinkResources = false
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
    val youtubedlAndroid = "0.18.1"
    implementation("io.github.junkfood02.youtubedl-android:library:$youtubedlAndroid")
    implementation("io.github.junkfood02.youtubedl-android:ffmpeg:$youtubedlAndroid")
    // Transitief al aanwezig, maar expliciet nodig om SharedPrefsHelper te
    // kunnen aanroepen: daar houdt de library bij welke yt-dlp-versie ze denkt
    // te hebben, en die markering moeten we kunnen resetten als hij niet meer
    // klopt met het binaire bestand.
    implementation("io.github.junkfood02.youtubedl-android:common:$youtubedlAndroid")
}
