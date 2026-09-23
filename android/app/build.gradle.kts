import java.net.URI

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Official bundle (same URL as google-ai-edge/mediapipe-samples face_landmarker).
private val faceLandmarkerModelUrl =
    "https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task"

tasks.register("downloadFaceLandmarkerModel") {
    val outFile = layout.projectDirectory.file("src/main/assets/face_landmarker.task").asFile
    outputs.file(outFile)
    doLast {
        if (!outFile.exists()) {
            outFile.parentFile.mkdirs()
            URI.create(faceLandmarkerModelUrl).toURL().openStream().use { input ->
                outFile.outputStream().use { output -> input.copyTo(output) }
            }
        }
    }
}

tasks.named("preBuild") {
    dependsOn("downloadFaceLandmarkerModel")
}

android {
    namespace = "com.example.test_face"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.example.test_face"

        // IMPORTANTE:
        // Para evitar problemas con CameraX / MediaPipe, usa 26 o más.
        minSdk = 26

        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildFeatures {
        viewBinding = true
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")

            // R8 rompe MediaPipe en release. Sus mensajes protobuf se
            // resuelven por reflection y la ofuscación los deja
            // irreconocibles: al abrir la cámara saltaba
            // `PlatformException(TRACKING_ERROR, Field platform_ for r2.a
            // not found)` — ese `r2.a` ES el nombre ya ofuscado, por eso
            // solo ocurría en release y nunca en debug. Filament/SceneView
            // y el puente JNI corren el mismo riesgo.
            //
            // Se desactiva en vez de escribir reglas `-keep`: el APK pesa
            // ~140 MB por los modelos .task/.glb, así que lo que R8 podía
            // ahorrar en bytecode es marginal frente al riesgo de que
            // falte un keep y vuelva a romperse solo en producción.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    val cameraxVersion = "1.3.4"

    implementation("androidx.camera:camera-core:$cameraxVersion")
    implementation("androidx.camera:camera-camera2:$cameraxVersion")
    implementation("androidx.camera:camera-lifecycle:$cameraxVersion")
    implementation("androidx.camera:camera-view:$cameraxVersion")
    implementation("androidx.camera:camera-video:$cameraxVersion")

    // Pin versions (avoid protobuf "field ... not found" from mismatched tasks-core / tasks-vision).
    val mediaPipeVersion = "0.10.29"
    implementation("com.google.mediapipe:tasks-vision:$mediaPipeVersion")
    implementation("com.google.mediapipe:tasks-core:$mediaPipeVersion")

    implementation("io.github.sceneview:sceneview:2.1.1")

    // Requerido por flutter_local_notifications (core library desugaring).
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}