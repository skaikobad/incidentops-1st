# /AutoReliability — Reliability Command Center

A pure MERN **Incident Management & On-Call Tracker** project for DevOps students.

This is a mini PagerDuty-style system where teams can report incidents, assign engineers, track status, capture investigation updates, and write/export postmortems.

This script turns a fresh Ubuntu server into a fully working web application environment:

Installs Node.js (backend JS runtime).

Installs MongoDB (database).

Sets up configuration files.

Installs all required project packages.

Loads example data into the database.

Tells you how to start the app and where to access it.

It’s designed for students or developers deploying a project on a cloud VM (like DigitalOcean, AWS, or local Ubuntu).

---

## Core Features

- JWT login
- Incident creation
- Severity levels: `low`, `medium`, `high`, `critical`
- Assign engineer
- Status tracking: `open`, `investigating`, `resolved`
- Drag-and-drop Kanban status changes
- Timeline comments with searchable `@mention` pop-up for all users
- Root cause analysis
- Resolution notes
- Postmortem action items
- Browser PDF export using `jsPDF`
- In-app notification simulation
- Dashboard metrics including MTTR
- Admin-only incident deletion
- Local reminder job for stale high-severity incidents

---

## Tech Stack

- MongoDB Community Server
- Express.js
- React.js with Vite
- Node.js
- JWT authentication
- Mongoose
- jsPDF

---

## Project Structure

```txt
reliability-command-center/
├── backend/
│   ├── src/
│   │   ├── config/
│   │   ├── controllers/
│   │   ├── middleware/
│   │   ├── models/
│   │   ├── routes/
│   │   ├── utils/
│   │   └── server.js
│   └── scripts/seed.js
├── frontend/
│   ├── src/
│   │   ├── components/
│   │   ├── context/
│   │   ├── pages/
│   │   ├── services/
│   │   └── styles.css
│   └── public/
├── installer.sh
├── package.json
└── README.md
```

---

# Part 1 — Run Locally on Your Computer

## 1. Install prerequisites

You need:

- Node.js 20+
- npm
- MongoDB Community Server

Check versions:

```bash
node -v
npm -v
mongod --version
```

If you are using Linux and want the installer to install Node.js and MongoDB for you, run:

```bash
chmod +x installer.sh
./installer.sh
```

The installer will:

1. Install Node.js
2. Install MongoDB
3. Start MongoDB
4. Create `.env` files
5. Install project dependencies
6. Seed sample data

After the installer completes, run:

```bash
npm run dev
```

---

## 2. Manual local setup

From the project root:

```bash
cp backend/.env.example backend/.env
cp frontend/.env.example frontend/.env
```

Backend `.env`:

```env
PORT=5001
MONGODB_URI=mongodb://127.0.0.1:27017/reliability_command_center
JWT_SECRET=change_this_secret_for_class
JWT_EXPIRES_IN=7d
CLIENT_URL=http://localhost:5173
REMINDER_INTERVAL_MINUTES=15
```

Frontend `.env`:

```env
VITE_API_URL=http://localhost:5001/api
```

Install dependencies:

```bash
npm install
npm run install:all
```

Start MongoDB:

```bash
sudo systemctl start mongod
sudo systemctl enable mongod
sudo systemctl status mongod
```

Seed sample data:

```bash
npm run seed
```

Run the full app:

```bash
npm run dev
```

Open:

```txt
http://localhost:5173
```

Backend health check:

```txt
http://localhost:5001/api/health
```

---

## Default Login

```txt
Email: admin@auto-reliability.com
Password: hello123
```

Seeded engineer users also use:

```txt
hello123
```

---

## Useful Local Commands

Run backend only:

```bash
npm run dev --prefix backend
```

Run frontend only:

```bash
npm run dev --prefix frontend
```

Reset sample data:

```bash
npm run seed
```

---

# Part 2 — Run on an AWS Ubuntu VM

This section is for students who want to run the MERN app on an AWS EC2 Ubuntu instance before moving to App Runner/ECS.

## 1. Create an EC2 instance

Recommended for class practice:

```txt
AMI: Ubuntu Server LTS
Instance type: t2.micro or t3.micro for practice
Storage: 20 GB+
Open the Ubuntu version dropdown: Choose Ubuntu Server 24.04 LTS (HVM), SSD Volume Type
```

## 2. Configure Security Group inbound rules

For class/demo use, allow:

```txt
22    SSH          Your IP only
5173  React/Vite   Your IP or 0.0.0.0/0 for temporary demo
5001  Express API  Your IP or 0.0.0.0/0 for temporary demo
```

For production, you should not expose development ports directly. Use Nginx, HTTPS, and a process manager.


## 3. Clone the project

```

Clone from GitHub if you pushed it to a repository:

```bash
git clone YOUR_REPOSITORY_URL
cd the-project-folder-name
```

## 4. Run the installer

From the project root:

```bash
chmod +x installer.sh
./installer.sh
```

The installer installs:

- Node.js
- npm
- MongoDB Community Server
- Project dependencies

It also starts MongoDB and runs the seed script.

## 6. Update frontend API URL for the AWS VM

Edit `frontend/.env`:

```bash
nano frontend/.env
```

Replace the local API URL with your VM public IP:

```env
VITE_API_URL=http://YOUR_EC2_PUBLIC_IP:5001/api
```

Edit `backend/.env`:

```bash
nano backend/.env
```

Set:

```env
CLIENT_URL=http://YOUR_EC2_PUBLIC_IP:5173
```

## 7. Run the app on the VM

```bash
npm run dev
```

Open in your browser:

```txt
http://YOUR_EC2_PUBLIC_IP:5173
```

Backend health check:

```txt
http://YOUR_EC2_PUBLIC_IP:5001/api/health
```

Login:

```txt
admin@auto-reliability.com
hello123
```

---

# Installer Script Notes

The `installer.sh` file is designed for Ubuntu-based systems. Run it from the project root:

```bash
chmod +x installer.sh
./installer.sh
```

What it does:

```txt
1. Updates apt packages
2. Installs required Linux packages
3. Installs Node.js 20.x
4. Installs MongoDB Community Server 8.0
5. Enables and starts mongod
6. Copies .env examples if .env files are missing
7. Installs backend and frontend dependencies
8. Seeds the database
```

You can verify services after installation:

```bash
node -v
npm -v
sudo systemctl status mongod
```

If MongoDB is not running:

```bash
sudo systemctl start mongod
```

---

# API Endpoints

## Auth

```txt
POST /api/auth/login
GET  /api/auth/me
GET  /api/auth/users
POST /api/auth/users       admin only
```

## Incidents

```txt
GET    /api/incidents
POST   /api/incidents
GET    /api/incidents/stats
GET    /api/incidents/:id
PATCH  /api/incidents/:id
DELETE /api/incidents/:id  admin only
POST   /api/incidents/:id/comments
```

## Notifications

```txt
GET   /api/notifications
PATCH /api/notifications/:id/read
```

---

# Teaching Flow

1. Explain incident lifecycle: report → assign → investigate → resolve → postmortem.
2. Show MongoDB schemas for User, Incident, and Notification.
3. Explain JWT login and protected routes.
4. Create a critical incident and assign an on-call engineer.
5. Add timeline comments as investigation updates.
6. Resolve the incident and discuss MTTR.
7. Fill root cause and action items.
8. Export the postmortem PDF.
9. Delete a test incident as admin.
10. Discuss how the same app maps to AWS services.

---

# Troubleshooting

## MongoDB connection error

Check MongoDB status:

```bash
sudo systemctl status mongod
```

Start MongoDB:

```bash
sudo systemctl start mongod
```

## Login does not work

Run the seed script again:

```bash
npm run seed
```

Use:

```txt
admin@auto-reliability.com
hello123
```

## Frontend opens but API fails on AWS

Make sure `frontend/.env` has the public VM IP:

```env
VITE_API_URL=http://YOUR_EC2_PUBLIC_IP:5001/api
```

Then restart the app:

```bash
npm run dev
```

## Browser cannot open port 5173 or 5001

Check your EC2 Security Group inbound rules and allow the required ports for class/demo testing.

---

# Notes for Students

This project teaches both product thinking and DevOps thinking. The goal is not only to code CRUD screens, but to understand how real engineering teams handle reliability, incidents, ownership, MTTR, and postmortems.

---
Cheers!


## Latest Enhancements

### Timeline @mentions

Timeline comments now support a searchable `@mention` pop-up for all users, including admins, engineers, on-call engineers, and backup users.

How it works:

1. Open any incident.
2. Go to **Timeline Comments**.
3. Type `@`.
4. A pop-up list of matching users appears.
5. Search by name, email, or team.
6. Select a user with the mouse, or use `Arrow Up`, `Arrow Down`, `Enter`, and `Tab`.

The app inserts the selected user as an email-based mention, for example:

```txt
@ava@auto-reliability.com please check the payment API logs.
```

The mentioned user receives an in-app notification. When the user opens the notification, they can read the notification details and open the related incident directly.

### Admin roster deletion

Admins can delete users from the **On-Call Roster** page. When a user is deleted:

- Their notification records are removed.
- Incidents assigned to them become unassigned.
- The logged-in admin cannot delete their own account.


## Final UI Updates

- `@mention` in Timeline Comments searches all users, not only on-call engineers.
- Delete confirmations use a custom in-app modal instead of the browser confirmation alert.
- Success and error feedback uses toast notifications. Browser alerts are not used for delete actions.
