# flutter_local_notifications Gson-serializes the pending scheduled-notification
# list to SharedPreferences on every schedule/cancel call (no consumer-rules.pro
# ships with the plugin to protect this). R8 renames/strips fields by default,
# which silently breaks that round-trip without an explicit keep rule.
-keep class com.dexterous.flutterlocalnotifications.models.** { *; }
-keepattributes Signature
-keepattributes *Annotation*

# home_widget's own recommended rules for its RemoteViews/XML resource
# inflation path (from the package's example app).
-dontwarn org.xmlpull.v1.**
-dontwarn org.kxml2.io.**
-dontwarn android.content.res.**
-dontwarn org.slf4j.impl.StaticLoggerBinder
-keep class org.xmlpull.** { *; }
-keepclassmembers class org.xmlpull.** { *; }
