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

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    val cameraxVersion = "1.3.4"

    implementation("androidx.camera:camera-core:$cameraxVersion")
    implementation("androidx.camera:camera-camera2:$cameraxVersion")
    implementation("androidx.camera:camera-lifecycle:$cameraxVersion")
    implementation("androidx.camera:camera-view:$cameraxVersion")

    // Pin versions (avoid protobuf "field ... not found" from mismatched tasks-core / tasks-vision).
    val mediaPipeVersion = "0.10.29"
    implementation("com.google.mediapipe:tasks-vision:$mediaPipeVersion")
    implementation("com.google.mediapipe:tasks-core:$mediaPipeVersion")
}

flutter {
    source = "../.."
}