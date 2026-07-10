# SpeedTrack ProGuard rules
# Keep Flutter, Firebase, AppsFlyer, notifications & WebView glue.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-keep class com.appsflyer.** { *; }
-keep class com.dexterous.** { *; }
-keep class io.flutter.plugins.webviewflutter.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.appsflyer.**
-dontwarn com.google.android.play.core.**
