// React Native Firebase on iOS, the two things its own plugin can't do here:
//
// 1. Static frameworks (expo-build-properties `useFrameworks: "static"`) make
//    its Swift Package copies of firebase-ios-sdk collide at link time. Its own
//    fix is CocoaPods instead: `$RNFirebaseDisableSPM = true` atop the Podfile.
// 2. It puts `FirebaseApp.configure()` above `factory.startReactNative(`, which
//    with-scene-lifecycle removes (the scene delegate starts React Native now),
//    so the app launched with no Firebase app ("No Firebase App '[DEFAULT]'").
//    The call goes just before `return super.application(...)` instead, which
//    nothing removes, whichever order the plugins run in.
const { withAppDelegate, withPodfile } = require("expo/config-plugins");

const SPM_OFF = "$RNFirebaseDisableSPM = true";
const CONFIGURE = "FirebaseApp.configure()";
const RETURN = "    return super.application(application, didFinishLaunchingWithOptions: launchOptions)";

module.exports = function withFirebaseIos(config) {
  config = withPodfile(config, (c) => {
    if (!c.modResults.contents.includes(SPM_OFF)) c.modResults.contents = `${SPM_OFF}\n${c.modResults.contents}`;
    return c;
  });
  return withAppDelegate(config, (c) => {
    let src = c.modResults.contents;
    if (!/^\s*import FirebaseCore\s*$/m.test(src)) src = src.replace(/^(internal import Expo\s*)$/m, "$1\nimport FirebaseCore");
    // Drop a call left where React Native used to start (it may be removed anyway).
    src = src.replace(/^\s*\/\/ @generated begin @react-native-firebase\/app-didFinishLaunchingWithOptions[\s\S]*?\/\/ @generated end @react-native-firebase\/app-didFinishLaunchingWithOptions\n/m, "");
    if (!src.includes(CONFIGURE)) {
      if (!src.includes(RETURN)) throw new Error("with-firebase-pods: AppDelegate.swift no longer matches the expected template");
      src = src.replace(RETURN, `    ${CONFIGURE}\n\n${RETURN}`);
    }
    c.modResults.contents = src;
    return c;
  });
};
