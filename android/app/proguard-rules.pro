# FLAME: protect the native fields/methods JNA and Vosk rely on.
#
# Background: JNA's native initIDs uses GetFieldID(cls, "peer", "J") at load
# time. R8 full-mode obfuscation renames com.sun.jna.Pointer.peer (observed in
# the 2026 release APK as "T"), so the lookup fails with
# "Can't obtain peer field ID for class com.sun.jna.Pointer", which crashes the
# process from org.vosk.LibVosk.<clinit>. Keep the JNA + Vosk Java classes
# intact and keep any JNI entry points used by libvosk.so/libjnidispatch.so.
-keep class com.sun.jna.** { *; }
-keepclassmembers class com.sun.jna.** { *; }

-keep class org.vosk.** { *; }
-keepclassmembers class org.vosk.** { native <methods>; }

# App-side wiring into the native models.
-keep class com.flame.flame.VoskAsrSession { *; }