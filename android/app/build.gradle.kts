plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.flame.flame"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.flame.flame"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            // MUST stay off: R8 obfuscation renames com.sun.jna.Pointer.peer,
            // breaking JNA's JNI initIDs (GetFieldID looks the field up by the
            // literal name "peer") -> UnsatisfiedLinkError in LibVosk.<clinit>
            // kills the process. JNA keep rules in proguard-rules.pro are a
            // second line of defense if minification is ever re-enabled.
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
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

dependencies {
    // Real offline Hindi ASR engine (Kaldi-based, bundles libvosk.so for
    // arm64-v8a/armeabi-v7a/x86/x86_64). Apache-2.0.
    implementation("com.alphacephei:vosk-android:0.3.75")
    // Real on-device translation runtime (ONNX Runtime for the IndicTrans2
    // INT8 encoder/decoder sessions). MIT.
    implementation("com.microsoft.onnxruntime:onnxruntime-android:1.29.0")
}
