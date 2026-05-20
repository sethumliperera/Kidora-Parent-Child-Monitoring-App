const fs = require("fs");
const path = require("path");
const admin = require("firebase-admin");

if (!admin.apps.length) {
  if (process.env.FIREBASE_SERVICE_ACCOUNT_JSON) {
    const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON);
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
    });
    console.log("Firebase Admin initialized:", serviceAccount.project_id);
  } else {
    const keyPath = path.join(__dirname, "serviceAccountKey.json");
    if (!fs.existsSync(keyPath)) {
      throw new Error(
        "Set FIREBASE_SERVICE_ACCOUNT_JSON on Render or add serviceAccountKey.json locally."
      );
    }
    const serviceAccount = require("./serviceAccountKey.json");
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
    });
    console.log("Firebase Admin initialized:", serviceAccount.project_id);
  }
}

module.exports = admin;
