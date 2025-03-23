# Flutter background service
-keep class com.dexterous.** { *; }
-keep class com.tekartik.** { *; }
-keep class com.github.** { *; }
-keep class io.flutter.plugins.** { *; }


# Keep Gson-related classes
-keep class com.google.gson.** { *; }
-keep class * implements com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer

# Keep any classes used for serialization/deserialization
-keepclassmembers class * {
  @com.google.gson.annotations.SerializedName <fields>;
}

# Keep generic signatures and annotations for Gson
-keepattributes Signature
-keepattributes *Annotation*