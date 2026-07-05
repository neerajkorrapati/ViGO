const functions = require('firebase-functions');
const admin = require('firebase-admin');
const express = require('express');
const cors = require('cors');
const twilio = require('twilio');

admin.initializeApp();

const app = express();
app.use(cors({ origin: true }));
app.use(express.json());

app.post('/sendWhatsApp', async (req, res) => {
  try {
    const { toPhone, message } = req.body;
    if (!toPhone || !message) return res.status(400).json({ error: 'toPhone and message required' });

    const accountSid = process.env.TWILIO_ACCOUNT_SID;
    const authToken = process.env.TWILIO_AUTH_TOKEN;
    const fromWhatsApp = process.env.TWILIO_WHATSAPP_FROM; // e.g. +1415XXXX

    if (!accountSid || !authToken || !fromWhatsApp) {
      return res.status(500).json({ error: 'Twilio configuration missing on server' });
    }

    const client = twilio(accountSid, authToken);
    const from = `whatsapp:${fromWhatsApp}`;
    const to = `whatsapp:${toPhone}`;

    const msg = await client.messages.create({ from, to, body: message });
    return res.json({ sid: msg.sid });
  } catch (err) {
    console.error('sendWhatsApp error', err.message || err);
    return res.status(500).json({ error: err.message || String(err) });
  }
});

exports.api = functions.https.onRequest(app);

// Aggregate stats increment/decrement triggers
exports.incrementUserCount = functions.firestore
  .document('users/{userId}')
  .onCreate(async (snap, context) => {
    const statsRef = admin.firestore().doc('stats/global');
    await statsRef.set({
      usersCount: admin.firestore.FieldValue.increment(1)
    }, { merge: true });
  });

exports.decrementUserCount = functions.firestore
  .document('users/{userId}')
  .onDelete(async (snap, context) => {
    const statsRef = admin.firestore().doc('stats/global');
    await statsRef.set({
      usersCount: admin.firestore.FieldValue.increment(-1)
    }, { merge: true });
  });

exports.incrementRideCount = functions.firestore
  .document('rides/{rideId}')
  .onCreate(async (snap, context) => {
    const statsRef = admin.firestore().doc('stats/global');
    await statsRef.set({
      activeRidesCount: admin.firestore.FieldValue.increment(1)
    }, { merge: true });
  });

exports.decrementRideCount = functions.firestore
  .document('rides/{rideId}')
  .onDelete(async (snap, context) => {
    const statsRef = admin.firestore().doc('stats/global');
    await statsRef.set({
      activeRidesCount: admin.firestore.FieldValue.increment(-1)
    }, { merge: true });
  });

// Scheduled function to update active rides count by cleaning up expired rides (departureTime < now)
exports.updateActiveRidesCount = functions.pubsub
  .schedule('every 15 minutes')
  .onRun(async (context) => {
    const db = admin.firestore();
    const now = admin.firestore.Timestamp.now();

    try {
      const activeRidesSnap = await db.collection('rides')
        .where('departureTime', '>=', now)
        .count()
        .get();

      const count = activeRidesSnap.data().count;

      await db.doc('stats/global').set({
        activeRidesCount: count
      }, { merge: true });

      console.log(`Successfully updated activeRidesCount to ${count} at ${now.toDate()}`);
    } catch (error) {
      console.error("Error updating scheduled activeRidesCount:", error);
    }
  });
