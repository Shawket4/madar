# madar

A new Flutter project.

## Push notifications (Firebase)

The till gets push from Firebase Cloud Messaging: the app registers its token
with the server (`PUT /push/token`, app `pos`), and a tapped notification opens
the Queue. What gets pushed, to whom and in what words is the server's job.

The Firebase config is **not in git** — this repo is public and the config
carries the project's API key and app ids. The app builds and runs without it
(push is simply off). To turn push on, on any machine:

    cd apps/madar
    flutterfire configure --project=dawam-by-madar --platforms=android,ios \
      --ios-bundle-id=com.madar.cashier --android-package-name=com.madar.pos

That writes `lib/firebase_options.dart`, `android/app/google-services.json`,
`ios/Runner/GoogleService-Info.plist` and `firebase.json`, all git-ignored. On
iOS a build step copies the plist into the app only when it exists, and on
Android the Google Services plugin applies only when its JSON is there.

iOS push also needs the APNs key (`.p8`) in the Firebase console: Project
settings > Cloud Messaging > Apple app configuration, under the
`com.madar.cashier` app. The same key file the staff app uses works — an APNs
key belongs to the Apple team, not to one app — but Firebase wants it uploaded
under each iOS app separately.
