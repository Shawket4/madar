// iOS 27 refuses to launch an app that has not adopted the scene life cycle
// (it traps in UIApplicationEvaluateRuntimeIssueForNoSceneLifecycleAdoption).
// Expo ships the scene delegate (EXExpoAppSceneDelegate) but SDK 57's template
// does not use it yet, so this plugin wires it in on every prebuild: the
// Info.plist names it, and the app delegate hands React Native to it instead of
// starting it into a window of its own.
// ponytail: drop this file once the bare template adopts scenes itself.
const { withAppDelegate, withInfoPlist } = require("expo/config-plugins");

module.exports = function withSceneLifecycle(config) {
  config = withInfoPlist(config, (c) => {
    c.modResults.UIApplicationSceneManifest = {
      UIApplicationSupportsMultipleScenes: false,
      UISceneConfigurations: {
        UIWindowSceneSessionRoleApplication: [
          { UISceneConfigurationName: "Default Configuration", UISceneDelegateClassName: "EXExpoAppSceneDelegate" },
        ],
      },
    };
    return c;
  });
  return withAppDelegate(config, (c) => {
    let src = c.modResults.contents;
    src = src.replace(
      "class AppDelegate: ExpoAppDelegate {",
      "class AppDelegate: ExpoAppDelegate, ExpoReactNativeFactoryProvider {",
    );
    // The scene delegate creates the window and starts React Native.
    src = src.replace(/\n#if os\(iOS\) \|\| os\(tvOS\)\n\s*window = UIWindow[\s\S]*?#endif\n/, "\n");
    if (!src.includes("ExpoReactNativeFactoryProvider {") || src.includes("factory.startReactNative(")) {
      throw new Error("with-scene-lifecycle: AppDelegate.swift no longer matches the expected template");
    }
    c.modResults.contents = src;
    return c;
  });
};
