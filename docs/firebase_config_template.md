# Firebase Configuration Template

This document describes the required Firebase configuration. **Do not store actual values here.**

## Setup

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project (Spark / free tier)
3. Create a **Realtime Database** (not Firestore) in `europe-west1` (or your preferred region)
4. Go to Project Settings → General → Web API Key

## Required Config Values

Create a file at `user://firebase.cfg` (Godot user directory) with the following structure:

```json
{
  "project_id": "YOUR_PROJECT_ID",
  "api_key": "YOUR_WEB_API_KEY",
  "rtdb_url": "https://YOUR_PROJECT_ID-default-rtdb.REGION.firebasedatabase.app/"
}
```

The game reads this file at runtime. If the file is missing, cloud sync is silently disabled and the game runs fully offline.

## Realtime Database Security Rules

Set these rules in Firebase Console → Realtime Database → Rules:

```json
{
  "rules": {
    "users": {
      "$uid": {
        ".read": true,
        ".write": true
      }
    },
    "leaderboards": {
      ".read": true,
      "$entry": {
        ".write": true
      }
    }
  }
}
```

For the prototype, you may use fully open rules for testing:
```json
{
  "rules": {
    ".read": true,
    ".write": true
  }
}
```

## REST API Usage

Realtime Database uses a simple REST API with plain JSON — no field-wrapping needed.

### Read: `GET {rtdb_url}/users/{userId}.json?key={api_key}`
### Write: `PUT {rtdb_url}/users/{userId}.json?key={api_key}`

## Data Structure

### `/users/{userId}`
```json
{
  "current_xp": 1500,
  "current_level": 3,
  "unlocked_skills": ["intro_combo", "bridge_combo"],
  "last_mission_summary": {...},
  "last_updated": "2026-07-04T12:00:00Z"
}
```

### `/leaderboards/{entryId}`
```json
{
  "user_id": "abc123",
  "xp": 1500,
  "combos_completed": 8,
  "mission_id": "prototype_arena",
  "timestamp": "2026-07-04T12:00:00Z"
}
```
