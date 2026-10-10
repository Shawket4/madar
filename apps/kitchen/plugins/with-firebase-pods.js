// React Native Firebase on iOS needs static frameworks (expo-build-properties
// `useFrameworks: "static"`), and with static linkage its Swift Package
// copies of firebase-ios-sdk collide at link time. Its own fix is to resolve
// Firebase through CocoaPods instead: `$RNFirebaseDisableSPM = true` at the
// top of the Podfile, which prebuild regenerates, hence a plugin.
const { withPodfile } = require("expo/config-plugins");

const LINE = "$RNFirebaseDisableSPM = true";

module.exports = function withFirebasePods(config) {
  return withPodfile(config, (c) => {
    if (!c.modResults.contents.includes(LINE)) {
      c.modResults.contents = `${LINE}\n${c.modResults.contents}`;
    }
    return c;
  });
};
