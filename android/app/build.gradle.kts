import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Firebase (FCM push) — apply the Google Services plugin ONLY when its Android
// config is present (android/app/google-services.json). On a machine/CI without
// the Firebase file the build proceeds and push silently disables at runtime
// (PushNotifications.init() guards Firebase init). Mirrors the conditional
// release-signing below.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

// Release signing — loaded from android/key.properties (gitignored). When the
// file is absent (e.g. CI without secrets), release falls back to debug keys.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "uz.kadastr.kadastr"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications (uses java.time APIs).
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "uz.kadastr.kadastr"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val storeFilePath = keystoreProperties["storeFile"] as String?
            if (storeFilePath != null) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(storeFilePath)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Use the upload key when key.properties is present, else debug
            // (keeps `flutter run --release` working without secrets).
            signingConfig = if (keystorePropertiesFile.exists())
                signingConfigs.getByName("release")
            else
                signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // ── CameraX va guava: BITTA versiya, ikki iste'molchi ────────────────────
    // :app ning o'z kodi (VideoCaptureActivity — debug-only video yozuv, eng
    // past zoom 0.5x/0.6x + HD) va `camera_android_camerax` plagini (360°
    // panorama capture ekrani, docs/panorama-360-plan.md) BIR XIL CameraX
    // sinflarini yuklaydi. Ikki xil versiya e'lon qilinsa Gradle baribir
    // eng yuqorisini tanlaydi, lekin :app pastroq versiyaga qarab
    // kompilyatsiya bo'lardi — runtime'da `NoSuchMethodError` xavfi.
    // Shuning uchun versiya SHU YERDA, bitta joyda qotiriladi.
    //
    // NEGA 1.4.2 → 1.6.0: `camera_android_camerax 0.7.2` o'z build faylida
    // `cameraxVersion = "1.6.0"` deb e'lon qiladi. Uni pastga tushirib
    // bo'lmaydi (plagin 1.6 API'siga tayanadi), demak :app ko'tariladi.
    val cameraxVersion = "1.6.0"
    implementation("androidx.camera:camera-core:$cameraxVersion")
    implementation("androidx.camera:camera-camera2:$cameraxVersion")
    implementation("androidx.camera:camera-lifecycle:$cameraxVersion")
    implementation("androidx.camera:camera-video:$cameraxVersion")
    // camera-view'ni faqat :app ishlatadi (PreviewView), plaginda yo'q —
    // lekin u ham camera-core bilan bir xil versiyada bo'lishi SHART.
    implementation("androidx.camera:camera-view:$cameraxVersion")
    implementation("androidx.activity:activity-ktx:1.9.3")

    // CameraX ning `ListenableFuture` i uchun guava. video_player_android
    // (media3 1.9.x) guava'ni `implementation` sifatida olib keladi — u :app
    // ning compile classpath'iga CHIQMAYDI, lekin butun grafda
    // `com.google.guava:listenablefuture` ni BO'SH artefaktga
    // (9999.0-empty-to-avoid-conflict-with-guava) ko'taradi. Natijada
    // VideoCaptureActivity.kt "Cannot access class 'ListenableFuture'" deb
    // kompilyatsiya bo'lmay qolardi. Guava'ni ochiq qo'shib sinfni qaytaramiz.
    //
    // NEGA 33.3.1 → 33.5.0: ilgari versiya media3 talab qilgani bilan bir xil
    // ushlab turilgandi. Endi `camera_android_camerax 0.7.2` guava:33.5.0-android
    // ni tortadi va u media3'nikidan yuqori — Gradle grafda baribir 33.5.0 ga
    // ko'tarilgan bo'lardi. media3 uchun bu xavfsiz: u guava'dan faqat
    // `ListenableFuture`/`Futures` ni oladi, ular 33.x ichida barqaror.
    implementation("com.google.guava:guava:33.5.0-android")
}
