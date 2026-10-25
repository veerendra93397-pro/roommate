# RoomMate – push notifications + release APK

## A. Push notifications

1. Upgrade Firebase to the Blaze plan (Console > bottom-left "Upgrade").
   Cloud Functions need it. It has a free monthly allowance; a small app costs ~nothing.
   Tip: Console > Usage and billing > set a budget alert (e.g. ₹100).
2. In the Flutter project folder run:
       flutter pub add firebase_messaging
3. Add this line inside <manifest> in android/app/src/main/AndroidManifest.xml
   (above <application ...>):
       <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
4. Install the Firebase CLI tools (once):  npm install -g firebase-tools   then   firebase login
5. Copy the functions/ folder and firebase.json from this zip into your project folder
   (next to pubspec.yaml; if you already have a firebase.json, keep yours and just make sure
   it points "functions" at the functions folder). Then run:
       firebase use --add      (choose your RoomMate project)
       cd functions
       npm install
       cd ..
6. Open functions/index.js and set REGION at the top to your Firestore location (Firestore > Data tab shows it).
7. Deploy:  firebase deploy --only functions
   (the first deploy takes a few minutes and may ask to enable Google Cloud APIs: say yes)
8. Copy the new lib/ files over your project, then: flutter pub get, restart the app.
9. Test on a phone (not web): log in on two phones/emulators with Google Play, close the app
   on one, add an expense on the other -> the first gets a notification.

## B. Release APK

1. AndroidManifest.xml: add INTERNET permission (release builds do NOT get it automatically!)
   above <application ...>:
       <uses-permission android:name="android.permission.INTERNET"/>
       <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
   and set  android:label="RoomMate"  on the <application> tag.

2. Create a signing key (keep the file safe, you need it for every future update):
       keytool -genkey -v -keystore C:\Users\YOURNAME\roommate-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias roommate

3. Create android/key.properties  (never share or commit it):
       storePassword=YOUR_STORE_PASSWORD
       keyPassword=YOUR_KEY_PASSWORD
       keyAlias=roommate
       storeFile=C:/Users/YOURNAME/roommate-release.jks

4. Edit android/app/build.gradle.kts:
   a) very top of the file (before "plugins {"):
       import java.util.Properties
       import java.io.FileInputStream

   b) just before "android {":
       val keystoreProperties = Properties()
       val keystorePropertiesFile = rootProject.file("key.properties")
       if (keystorePropertiesFile.exists()) {
           keystoreProperties.load(FileInputStream(keystorePropertiesFile))
       }

   c) inside "android {", above "buildTypes":
       signingConfigs {
           create("release") {
               keyAlias = keystoreProperties["keyAlias"] as String
               keyPassword = keystoreProperties["keyPassword"] as String
               storeFile = file(keystoreProperties["storeFile"] as String)
               storePassword = keystoreProperties["storePassword"] as String
           }
       }

   d) inside buildTypes > release, replace the signingConfig line with:
           signingConfig = signingConfigs.getByName("release")

5. Build:
       flutter clean
       flutter pub get
       flutter build apk --release
   Result: build\app\outputs\flutter-apk\app-release.apk
   Smaller files (one per phone type; arm64-v8a suits most phones):
       flutter build apk --release --split-per-abi

6. Send the APK to phones (WhatsApp/Drive/USB). On the phone allow
   "Install unknown apps" for the app you opened it from, then tap the file.

Notes
- Keep applicationId = com.example.roommate for now: Firebase is set up for that name.
  (To publish on Google Play later you must change it and register the new name in Firebase.)
- Email/password login, Firestore and push do not need SHA keys.
