Here is a cleaner, more straightforward version. It drops the marketing fluff and reads like it was written by a developer explaining exactly what problem they solved and how they built it.

---

# ViGo

A campus transit and carpooling network for VIT Vellore.

Getting from Katpadi Railway Station or Chennai Airport back to the VIT Main Gate is expensive if you are traveling alone. ViGo is a web application built to connect students who are heading the same way so they can share rides and split the fare.

Live deployment: [vigovit.web.app](https://www.google.com/search?q=https://vigovit.web.app)

## Key Features

* **Verified Campus Network:** Access is restricted to users authenticated via their VIT Google accounts.
* **Live Seat Synchronization:** Seat counts update in real-time across the platform. The backend calculates the difference between total capacity and accepted passengers, automatically locking out new requests when a vehicle is full to prevent double-booking.
* **Direct WhatsApp Routing:** Built with a custom deep-linking setup that bypasses aggressive mobile browser pop-up blockers, allowing users to jump straight from a ride card into a chat with the host.
* **Automated Database Cleanup:** A background routine actively sweeps the Firestore database to purge expired ride listings, ensuring the main feed only shows active options.
* **Request Management Hub:** A dedicated dashboard where users can track their sent join requests, approve or decline incoming passengers, and clear out old history.

## Under the Hood

**Stack:** Flutter Web, Firebase Auth, Cloud Firestore

Building a stable real-time database connection for a web browser required working around several framework limitations. Standard Firestore transactions compiled from Dart to JavaScript can frequently shatter on mobile browsers (throwing "converted Future" errors) if network throttling drops the promise lock.

To guarantee data safety and prevent race conditions when multiple students try to join a ride at the same time, ViGo abandons volatile transaction locks in favor of a sequential fetch-and-update architecture. It utilizes strict type-safe data casting to handle unpredictable JavaScript number mutations, ensuring the mathematical logic for seating capacity never breaks the application.

## Run it locally

1. Clone the repository: `git clone https://github.com/YOUR_USERNAME/vigo.git`
2. Install dependencies: `flutter pub get`
3. Run the development server: `flutter run -d chrome`

## Contributing

Pull requests are welcome. If you want to add a feature (like UPI payment integration) or fix a bug, feel free to fork the repository and submit a PR.
