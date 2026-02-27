import * as admin from 'firebase-admin';
import path from 'path';
import fs from 'fs';

// Check if Firebase Admin is already initialized to prevent errors during hot reloads
if (!admin.apps.length) {
    try {
        // We will try to load the credentials from the firebase-admin.json file in the root
        // or fall back to an environment variable FIREBASE_SERVICE_ACCOUNT_KEY

        let credential;

        try {
            // First attempt: try loading from a local file
            const serviceAccountPath = path.resolve(process.cwd(), 'firebase-admin.json');
            if (fs.existsSync(serviceAccountPath)) {
                const serviceAccount = JSON.parse(fs.readFileSync(serviceAccountPath, 'utf8'));
                credential = admin.credential.cert(serviceAccount);
                console.log('Firebase Admin initialized from firebase-admin.json');
            } else {
                throw new Error('firebase-admin.json not found locally');
            }
        } catch (fileError) {
            // Second attempt: try loading from environment variable
            if (process.env.FIREBASE_SERVICE_ACCOUNT_KEY) {
                try {
                    const parsedKey = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_KEY);
                    credential = admin.credential.cert(parsedKey);
                    console.log('Firebase Admin initialized from environment variable');
                } catch (envParseError) {
                    console.error('Failed to parse FIREBASE_SERVICE_ACCOUNT_KEY environment variable');
                }
            } else {
                console.warn('Firebase Admin NOT initialized. Please add firebase-admin.json to the project root or set FIREBASE_SERVICE_ACCOUNT_KEY in .env');
            }
        }

        if (credential) {
            admin.initializeApp({
                credential: credential,
            });
        }
    } catch (error) {
        console.error('Firebase Admin initialization error', error);
    }
}

/**
 * Calculates the total unread count for a user (messages + notifications)
 */
export async function getUnreadCount(userId: string): Promise<number> {
    const { prisma } = await import('./prisma');

    console.log(`[BADGE_SYNC] Calculating unread count for user: ${userId}`);

    const [unreadMessages, unreadNotifications] = await Promise.all([
        prisma.message.count({
            where: {
                conversation: {
                    OR: [
                        { user1Id: userId },
                        { user2Id: userId }
                    ]
                },
                senderId: { not: userId },
                isRead: false
            }
        }),
        prisma.notification.count({
            where: {
                userId: userId,
                isRead: false
            }
        })
    ]);

    const total = unreadMessages + unreadNotifications;
    console.log(`[BADGE_SYNC] Result for ${userId} -> Messages: ${unreadMessages}, Notifications: ${unreadNotifications}, Total: ${total}`);

    return total;
}

/**
 * Sends a push notification to a specific FCM token
 */
export async function sendPushNotification(
    token: string,
    title: string,
    body: string,
    data?: { [key: string]: string },
    badge?: number
): Promise<boolean> {
    if (!admin.apps.length) {
        console.warn('Cannot send push notification: Firebase Admin is not initialized.');
        return false;
    }

    if (!token) {
        console.warn('Cannot send push notification: Missing FCM token.');
        return false;
    }

    try {
        console.log(`[FCM] Sending push to token: ${token.substring(0, 10)}... with badge: ${badge}`);

        const payload: admin.messaging.Message = {
            token,
            notification: {
                title,
                body,
            },
            data: data || {},
            android: {
                priority: 'high',
                notification: {
                    channelId: 'teqlif_channel', // Match this with your Flutter channel ID
                    sound: 'default',
                },
            },
            apns: {
                payload: {
                    aps: {
                        sound: 'default',
                        badge: (badge !== undefined && badge !== null) ? badge : 1,
                    },
                },
            },
        };

        const response = await admin.messaging().send(payload);
        console.log('[FCM] Successfully sent message:', response);
        return true;
    } catch (error) {
        console.error('[FCM] Error sending message:', error);
        return false;
    }
}
