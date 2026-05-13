Vi Go: The VIT Carpool Fix

Most of us spend way too much time scrolling through WhatsApp groups asking "anyone for Katpadi at 4pm?" **Vi Go** is a simple web-tool to stop the spam. It’s a live dashboard where you can find or start a travel party without the 100+ unread messages.
(also saves you from getting scammed by the auto-drivers , who charge you 300 bucks for 4km) :.

## Why build this?
The current way we coordinate rides at VIT is broken. WhatsApp is great for chatting, but terrible for organizing data. You can't see who’s already left, you can't easily see how many seats are left, and the messages get buried in minutes. 
(also prevents you from getting seenzoned and ignored).

Vi Go handles the logic (like auto-setting seat limits for autos vs cabs) so you just have to pick a time and show up at the gate.

## The Essentials
* **Auto-Allocation:** If you pick an Auto, it’s 3 spots. If you pick a Cab, it’s 4. No manual counting needed.
* **Self-Cleaning Feed:** Once a departure time passes, the ride disappears. No ghost rides or old info.
* **WhatsApp Bridge:** One button to generate a "Join my party" link to drop into your groups. 
* **VIT Only:** Restricted to @vitstudent.ac.in emails to keep things safe.

## The Tech
* **Frontend:** Flutter (Builds for Web first, App later).
* **Backend:** Firebase (For the live seat counts).
* **Automation:** Cloud Functions (To clear out the expired rides).

## How it works
1. **Browse:** Check the feed. If someone is already going at your time, just hit 'Join'.
2. **Create:** If not, start a new one. Choose your vehicle, your time, and your destination.
3. **Share:** Hit share to get a link you can post on WhatsApp.
4. **Coordinate:** Use the 'Chat with Host' button to settle on a meeting spot (Main Gate, GDN, etc).

---

### License
MIT. Use the code, don't sue me, help your friends get to the station.
