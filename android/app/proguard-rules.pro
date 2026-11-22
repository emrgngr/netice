# Yazı tanıma eklentisi Çince, Japonca, Korece ve Devanagari tanıyıcılarına
# da başvurur; uygulama yalnız Latin alfabesini kullandığı için bunlar pakete
# eklenmez. R8'in eksik sınıf hatası vermemesi için:
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
