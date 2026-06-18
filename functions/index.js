const functions = require('firebase-functions');
const express = require('express');
const cors = require('cors');
const twilio = require('twilio');

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
