const admin = require('firebase-admin');

// Load service account (Firebase Admin requires this for sending pushes)
const serviceAccount = require('./firebase-admin.json');

if (!admin.apps.length) {
    admin.initializeApp({
        credential: admin.credential.cert(serviceAccount)
    });
}

const token = "dV4DrSkxQFK1erHHuywHBA:APA91bH_S7GEjVY07dOOHt9R2y83Z9bNIE4t5bp8iTqjIZz9UmPaY4gbRYY4EpgnV5r0KE53nmxVZmk6Q2Yp38Wi2sLvDofcRiA4xqBTsUTV34uAkwJveuE";

const payload = {
    token: token,
    notification: {
        title: "Test Android Push",
        body: "Bu bir FCM Android test bildirimdir."
    },
    android: {
        priority: 'high',
        notification: {
            channelId: 'teqlif_channel',
            sound: 'default'
        }
    }
};

async function testPush() {
    console.log("Sending push to:", token);
    try {
        const response = await admin.messaging().send(payload);
        console.log("Successfully sent message:", response);
    } catch (error) {
        console.error("Error sending message:", error);
    }
}

testPush();
