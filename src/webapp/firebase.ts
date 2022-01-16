/** @format */

import { SWAY_CACHING_OKAY_COOKIE } from "src/constants";
import { getStorage } from "src/utils";
import firebase from "firebase/app";
import "firebase/auth";
import "firebase/firestore";
import "firebase/functions";
// import "firebase/messaging";

const IS_DEVELOPMENT = process.env.NODE_ENV === "development";

const emulate =
    process.env.NODE_ENV === "test" || !!process.env.REACT_APP_EMULATE;
const cachingCookie: string | null = getStorage(SWAY_CACHING_OKAY_COOKIE);

IS_DEVELOPMENT && console.log("(dev) EMULATING?", emulate);

const firebaseConfig = {
    apiKey: emulate ? "an_api_key" : process.env.REACT_APP_API_KEY,
    authDomain: emulate ? "an_auth_domain" : process.env.REACT_APP_AUTH_DOMAIN,
    databaseURL: emulate
        ? "a_database_url"
        : process.env.REACT_APP_DATABASE_URL,
    projectId: emulate ? "sway-dev-3187f" : process.env.REACT_APP_PROJECT_ID,
    storageBucket: emulate
        ? "a_storage_bucket"
        : process.env.REACT_APP_STORAGE_BUCKET,
    messagingSenderId: emulate
        ? "a_message_sender_id"
        : process.env.REACT_APP_MESSAGING_SENDER_ID,
    appId: emulate ? "an_app_id" : process.env.REACT_APP_APP_ID,
};

firebase.initializeApp(firebaseConfig);

const FieldValue = firebase.firestore.FieldValue;
const firestoreConstructor = firebase.firestore;
const authConstructor = firebase.auth;
const auth = authConstructor();
const functions = firebase.functions();
const firestore = firestoreConstructor();

// let messaging: firebase.messaging.Messaging | null = null;
// if (firebase.messaging.isSupported()) {
//     messaging = firebase.messaging();
// }

if (emulate) {
    auth.useEmulator("http://localhost:9099");
    functions.useEmulator("localhost", 5001);
    firestore.settings({
        host: "localhost:8080",
        ssl: false,
        experimentalForceLongPolling: true,
    });
} else if (cachingCookie === "1") {
    firestore
        .enablePersistence({ synchronizeTabs: true })
        .then(() => {
            if (IS_DEVELOPMENT) console.log("(dev) persistence enabled");
        })
        .catch((err) => {
            if (IS_DEVELOPMENT) {
                console.log("(dev) error enabling firestore persistence");
            }
            console.error(err);
            if (err.code === "failed-precondition") {
                if (IS_DEVELOPMENT) {
                    console.log(
                        "(dev) cannot enable persistence in multiple tabs",
                    );
                }
            } else if (err.code === "unimplemented") {
                if (IS_DEVELOPMENT) {
                    console.log("(dev) browser does not support persistence");
                }
            }
        });
}

export {
    FieldValue,
    auth,
    authConstructor,
    functions,
    firestoreConstructor,
    firestore,
    // messaging,
};
