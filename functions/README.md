Twilio Firebase Function

Setup:

1. Install dependencies:

```bash
cd functions
npm install
```

2. Set environment variables (recommended via `firebase functions:config:set` or using Cloud Console):

- `TWILIO_ACCOUNT_SID`
- `TWILIO_AUTH_TOKEN`
- `TWILIO_WHATSAPP_FROM` (phone number in E.164, e.g. +1415XXXX)

3. Deploy:

```bash
firebase deploy --only functions:api
```

Endpoint:

After deploy the endpoint is `https://<region>-<project>.cloudfunctions.net/api/sendWhatsApp`.
