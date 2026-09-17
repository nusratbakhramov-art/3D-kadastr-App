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
if (file("google-services.json").exists() && !providers.gradleProperty("panoDeviceTest").isPresent) {
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
    ndkVersion = "28.2.13676358"

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
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        versionName = flutter.versionName
        externalNativeBuild {
            cmake {
                arguments += listOf(
                    "-DANDROID_STL=c++_shared",
                    "-DOpenCV_DIR=${rootProject.projectDir}/third_party/OpenCV-android-sdk/sdk/native/jni",
                    "-DCMAKE_BUILD_TYPE=Release",
                    "-DUY360_DEVICE_TESTS=${providers.gradleProperty("panoDeviceTest").isPresent}",
                )
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
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
        debug {
            // Opt-in side-by-side device validation; never uninstall a differently signed store app.
            if (providers.gradleProperty("panoDeviceTest").isPresent) applicationIdSuffix = ".astra"
        }
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

    // ── CameraX ────────────────────────────────────────────────────────────
    // Endi YAGONA iste'molchi — :app ning o'z `VideoCaptureActivity` si
    // (debug-only video yozuv, eng past zoom 0.5x/0.6x + HD).
    //
    // ⚠️ Ilgari ikkinchi iste'molchi bor edi: `camera_android_camerax`
    // plagini (`camera` paketi orqali, eski qurilmadagi panorama capture
    // uchun). U 2026-09-12 da olib tashlandi — 360° capture endi NATIV
    // (ARCore). Versiya 1.6.0 da QOLDIRILDI: 1.4.2 ga tushirishning
    // foydasi yo'q va `VideoCaptureActivity` allaqachon shunga qarab
    // yozilgan.
    val cameraxVersion = "1.6.0"
    implementation("androidx.camera:camera-core:$cameraxVersion")
    implementation("androidx.camera:camera-camera2:$cameraxVersion")
    implementation("androidx.camera:camera-lifecycle:$cameraxVersion")
    implementation("androidx.camera:camera-video:$cameraxVersion")
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
    // ⚠️ 33.5.0 ni ilgari `camera_android_camerax 0.7.2` tortardi; u ketdi,
    // lekin versiya QOLDIRILDI — media3 pastroq so'raydi va tushirishning
    // foydasi yo'q. media3 guava'dan faqat `ListenableFuture`/`Futures` ni
    // oladi, ular 33.x ichida barqaror.
    implementation("com.google.guava:guava:33.5.0-android")

    // ── ARCore — 360° panorama capture ──────────────────────────────────────
    // Nativ capture (`pano/PanoCaptureActivity.kt`) har kadr bilan KAMERA
    // POZASINI (`camera.pose`) va `intrinsics` ni oladi; serverdagi tikish
    // aynan shularga tayanadi. Flutter'ning `camera` paketi ikkalasini ham
    // bermaydi — shuning uchun ekran nativ.
    //
    // ⚠️ Bu bog'liqlik ilovani ARCore'siz qurilmalarda CHEKLAMAYDI:
    // manifestda `com.google.ar.core` = `optional` va `camera.ar` majburiy
    // emas. Qurilma qo'llamasa Dart tarafda 360 bo'limi umuman chizilmaydi
    // (`PanoCaptureChannel.isSupported`).
    implementation("com.google.ar:core:1.49.0")

    // Sof JVM testlari (`src/test/kotlin`). Hozircha faqat panorama
    // capture'ning platformadan MUSTAQIL qismlari uchun: YUV→NV21 o'girish
    // va nishon panjarasi. Ikkalasi ham indeks/burchak arifmetikasi, ya'ni
    // xatosi faqat qurilmada ko'rinadigan tur. Ishga tushirish:
    //     cd android && ./gradlew :app:testDebugUnitTest
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
}
