# Kidora – Parent Child Monitoring Application

## Overview

Kidora is a smart Parent–Child Monitoring Application developed to improve child digital safety and parental supervision. The application enables parents to monitor app usage, screen time, restrictions, notifications, and child activity through a secure and user-friendly interface.

The system consists of a Flutter mobile application and a Node.js backend server with database integration and real-time communication support.

---

## Team Members

- Sethumli Perera
- Nimasha
- Sinidi
- Navodya
- Vinudi

Supervisor:

Miss Ann Roshine Appuhamy

---

## Features

### Parent Features

- Parent registration and login
- Child account linking
- Real-time activity monitoring
- Screen time tracking
- Application blocking
- Restrictions management
- Reminder scheduling
- Safety alerts
- Push notifications
- Dashboard analytics
- PDF report generation

### Child Features

- Child profile creation
- Screen usage monitoring
- App usage tracking
- Activity synchronization
- Parent restriction implementation

### Security Features

- JWT authentication
- Password encryption using bcrypt
- Secure API endpoints
- Firebase authentication support

---

##  Technologies Used

### Frontend

- Flutter
- Dart

### Backend

- Node.js
- Express.js

### Database

- MySQL

### Cloud Services

- Firebase Authentication
- Firebase Firestore
- Firebase Cloud Messaging

### Communication

- Socket.io

### Development Tools

- Visual Studio Code
- GitHub
- Postman

### Additional Packages

- usage_stats
- installed_apps
- flutter_local_notifications
- shared_preferences
- provider
- pdf
- printing

---

## Project Structure

```bash
kidora_app/

├── lib/
│   ├── providers/
│   ├── screens/
│   ├── services/
│   ├── theme/
│   ├── utils/
│   ├── widgets/
│   └── main.dart
│
├── kidora_backend/
│   ├── routes/
│   │   ├── appUsage.js
│   │   ├── blockApps.js
│   │   ├── child.js
│   │   ├── notifications.js
│   │   ├── reminders.js
│   │   ├── restrictions.js
│   │   ├── safetyAlerts.js
│   │   ├── screenTime.js
│   │   └── users.js
│   │
│   ├── middleware/
│   │   └── authMiddleware.js
│   │
│   ├── uploads/
│   ├── package.json
│   └── server.js
│
├── assets/
├── android/
├── ios/
├── web/
├── windows/
├── linux/
└── pubspec.yaml
```

---

## Installation Guide

### Prerequisites

Install:

- Flutter SDK
- Node.js
- MySQL
- Git
- Android Studio / VS Code

---

## Clone Repository

```bash
git clone https://github.com/yourusername/kidora.git

cd kidora
```

---

## Backend Setup

Move to backend:

```bash
cd kidora_backend
```

Install dependencies:

```bash
npm install
```

Create `.env`

```env
PORT=5000

DB_HOST=localhost
DB_USER=root
DB_PASSWORD=yourpassword
DB_NAME=kidora

JWT_SECRET=your_secret_key

FIREBASE_PROJECT_ID=your_project
FIREBASE_PRIVATE_KEY=your_key
FIREBASE_CLIENT_EMAIL=your_email
```

Run server:

```bash
npm start
```

---

## Frontend Setup

Return to project root:

```bash
cd ..
```

Install Flutter packages:

```bash
flutter pub get
```

Run application:

```bash
flutter run
```

---

## API Routes

### User APIs

| Method | Endpoint |
|----------|----------|
| POST | /users |
| POST | /login |

### Child APIs

| Method | Endpoint |
|----------|----------|
| GET | /child |
| POST | /child |

### Screen Time APIs

| Method | Endpoint |
|----------|----------|
| GET | /screenTime |
| POST | /screenTime |

### Application Monitoring APIs

| Method | Endpoint |
|----------|----------|
| GET | /appUsage |
| POST | /appUsage |

### App Blocking APIs

| Method | Endpoint |
|----------|----------|
| GET | /blockApps |
| POST | /blockApps |

### Notifications APIs

| Method | Endpoint |
|----------|----------|
| GET | /notifications |
| POST | /notifications |

### Restrictions APIs

| Method | Endpoint |
|----------|----------|
| GET | /restrictions |
| POST | /restrictions |

---

## Security Measures

- JWT token authentication
- Password hashing using bcrypt
- Middleware authorization
- Secure database communication
- Firebase authentication support

---

## Functional Workflow

1. Parent creates an account
2. Parent creates child profile
3. Child device is linked
4. Device activity is monitored
5. Usage statistics are collected
6. Restrictions and alerts are generated
7. Notifications are sent
8. Reports are displayed to parents

---

## Testing

Testing performed:

- Unit testing
- Functional testing
- Integration testing
- User acceptance testing

---

##  Future Enhancements

- AI behavior analysis
- GPS location monitoring
- Multi-child support
- Advanced reporting dashboard
- Emergency alerts
- Cloud backup services

---

## License

This project was developed for educational purposes only.

---

## Acknowledgements

Special thanks to:

Miss Ann Roshine Appuhamy for continuous guidance and support throughout the development of Kidora.

Special appreciation to all project team members for their dedication and collaboration.
