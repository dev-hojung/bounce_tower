import java.util.Properties
import java.io.FileInputStream

// 릴리스 서명 — android/key.properties(gitignore 대상)가 있으면 그 키로 서명하고,
// 없으면 debug 키로 폴백한다(로컬에서 flutter run --release가 그대로 되도록).
// ⚠️ 스토어 업로드 빌드는 반드시 key.properties가 있는 상태에서 만들 것.
//    키스토어와 비밀번호는 분실 시 앱 업데이트가 영구 불가하므로 안전하게 백업.
//
// 녹화·QA용 release APK는 업로드 키 없이 만든다:
//   flutter build apk --release -P debugSign=true
// → key.properties를 읽지 않고 debug 키로 서명(업무 #54). 스토어 업로드 불가.
val forceDebugSign = (project.findProperty("debugSign") as String?) == "true"
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val useReleaseKey = keystorePropertiesFile.exists() && !forceDebugSign
if (useReleaseKey) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.bouncetower.bounce_tower"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications(22.x)가 요구 — 없으면 :app:checkDebugAarMetadata에서
        // "requires core library desugaring to be enabled"로 빌드 실패한다.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.bounce.tower"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (useReleaseKey) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (useReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                // 키가 없으면 debug 서명으로 폴백 — 스토어 업로드는 불가하다.
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // isCoreLibraryDesugaringEnabled 와 짝. flutter_local_notifications 22.x 요구 버전.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
