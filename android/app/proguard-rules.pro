# youtubedl-android leunt volledig op Jackson-databind, dat via reflectie werkt.
# R8 herschrijft en verwijdert die klassen, waarna de statische ObjectMapper in
# YoutubeDL bij het laden klapt. Symptoom in een release-build:
#   NoClassDefFoundError: o3.e
#     <- ExceptionInInitializerError
#     <- RuntimeException: class o3.a is not a concrete class
# De library levert geen consumer-regels mee, dus ze moeten hier staan.
# Flutter voegt dit bestand automatisch toe aan de release-build zodra het
# bestaat (FlutterPlugin.kt zet isMinifyEnabled = true voor release).

-keep class com.yausername.** { *; }
-dontwarn com.yausername.**

-keep class com.fasterxml.jackson.** { *; }
-keepnames class com.fasterxml.jackson.** { *; }
-dontwarn com.fasterxml.jackson.**

# Jackson leest annotaties, generieke types en velden via reflectie; zonder deze
# attributen valt de mapping stil.
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod

-keepclassmembers class * {
    @com.fasterxml.jackson.annotation.* *;
}

# Optionele afhankelijkheden waar Jackson naar verwijst maar die op Android niet
# bestaan. Zonder deze regels faalt R8 op ontbrekende klassen.
-dontwarn java.beans.**
-dontwarn javax.xml.**
-dontwarn org.w3c.dom.**

# commons-io en commons-compress pakken python/ffmpeg uit.
# ExtraFieldUtils registreert in zijn static-init een reeks klassen via
# Class.newInstance(). R8 ziet die constructors nergens aangeroepen worden en
# verwijdert ze, waarna de InstantiationException omslaat in:
#   RuntimeException: class ... is not a concrete class
# Vandaar expliciet ook de constructors bewaren.
-keep class org.apache.commons.io.** { *; }
-keep class org.apache.commons.compress.** { *; }
-keepclassmembers class org.apache.commons.compress.** {
    <init>(...);
}
-dontwarn org.apache.commons.**
