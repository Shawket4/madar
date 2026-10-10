import { registerRootComponent } from 'expo';

import App from './src/app';
import { useMock } from './src/data/backend';

// Firebase wants its background handler before the app renders (native only).
if (!useMock) require('./src/lib/push').registerBackgroundPush();

// registerRootComponent calls AppRegistry.registerComponent('main', () => App);
// It also ensures that whether you load the app in Expo Go or in a native build,
// the environment is set up appropriately
registerRootComponent(App);
