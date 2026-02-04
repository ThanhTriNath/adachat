#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="AdaChat"
ZIP_NAME="${ROOT_DIR}.zip"

echo "Création du scaffold AdaChat dans ./${ROOT_DIR} ..."

# Clean previous
rm -rf "${ROOT_DIR}" "${ZIP_NAME}"

mkdir -p "${ROOT_DIR}"/{backend/src,frontend/src,prisma,.github/workflows}

# README
cat > "${ROOT_DIR}/README.md" <<'EOF'
# AdaChat - MVP

Aperçu : AdaChat est une application de messagerie (search friends, stories, messages, appels WebRTC).

Prérequis :
- Node 18+
- PostgreSQL
- AWS S3 (ou compatible)
- yarn / npm

Développement rapide :
1. Copier .env.example -> .env et remplir
2. cd backend && yarn install
3. cd ../frontend && yarn install
4. Exécuter migrations Prisma (après configuration DB) : npx prisma migrate dev
5. Lancer le backend : yarn dev (dans backend)
6. Lancer le frontend : yarn dev (dans frontend)

Notes :
- Ce zip contient un backend minimal (Express + Socket.IO) et un frontend React demo (Vite).
- Ne commite jamais tes secrets : utilise .env.example et GitHub Secrets pour CI.
EOF

# .env.example
cat > "${ROOT_DIR}/.env.example" <<'EOF'
# Database
DATABASE_URL=postgresql://user:password@HOST:5432/adachat

# JWT
JWT_SECRET=change_me_long_random_secret
JWT_EXPIRES_IN=15m
REFRESH_TOKEN_SECRET=change_refresh_secret
REFRESH_TOKEN_EXPIRES_IN=7d

# S3
S3_ENDPOINT=
S3_BUCKET=
S3_KEY=
S3_SECRET=
S3_REGION=

# App
PORT=4000
EOF

# LICENSE (MIT)
cat > "${ROOT_DIR}/LICENSE" <<'EOF'
MIT License

Copyright (c) 2026

Permission is hereby granted, free of charge, to any person obtaining a copy
...
(Please replace with your full name and year)
EOF

# .gitignore
cat > "${ROOT_DIR}/.gitignore" <<'EOF'
node_modules
dist
.env
.env.local
.DS_Store
.vscode
*.log
*.zip
EOF

# Prisma schema
cat > "${ROOT_DIR}/prisma/schema.prisma" <<'EOF'
generator client {
  provider = "prisma-client-js"
}

datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

model User {
  id          String    @id @default(uuid())
  username    String    @unique
  email       String    @unique
  password    String
  displayName String?
  avatarUrl   String?
  createdAt   DateTime  @default(now())
  updatedAt   DateTime  @updatedAt
  friendships FriendShip[] @relation("userFriendships")
  messagesSent Message[]   @relation("sentMessages")
  messagesReceived Message[] @relation("receivedMessages")
  stories     Story[]
}

model FriendShip {
  id          String   @id @default(uuid())
  requester   User     @relation("userFriendships", fields: [requesterId], references: [id])
  requesterId String
  addressee   User     @relation(fields: [addresseeId], references: [id])
  addresseeId String
  status      FriendshipStatus @default(PENDING)
  createdAt   DateTime @default(now())
}

enum FriendshipStatus {
  PENDING
  ACCEPTED
  BLOCKED
}

model Message {
  id         String   @id @default(uuid())
  sender     User     @relation("sentMessages", fields: [senderId], references: [id])
  senderId   String
  receiver   User     @relation("receivedMessages", fields: [receiverId], references: [id])
  receiverId String
  content    String?
  mediaUrl   String?
  type       MessageType @default(TEXT)
  delivered  Boolean  @default(false)
  read       Boolean  @default(false)
  createdAt  DateTime @default(now())
}

enum MessageType {
  TEXT
  IMAGE
  STICKER
}

model Story {
  id        String   @id @default(uuid())
  author    User     @relation(fields: [authorId], references: [id])
  authorId  String
  mediaUrl  String
  caption   String?
  expiresAt DateTime
  createdAt DateTime @default(now())
}
EOF

# Backend package.json
cat > "${ROOT_DIR}/backend/package.json" <<'EOF'
{
  "name": "adachat-backend",
  "version": "0.1.0",
  "private": true,
  "scripts": {
    "dev": "ts-node-dev --respawn --transpile-only src/index.ts",
    "build": "tsc -p tsconfig.json",
    "start": "node dist/index.js"
  },
  "dependencies": {
    "cors": "^2.8.5",
    "dotenv": "^16.0.0",
    "express": "^4.18.2",
    "jsonwebtoken": "^9.0.0",
    "socket.io": "^4.7.0"
  },
  "devDependencies": {
    "@types/express": "^4.17.17",
    "@types/jsonwebtoken": "^9.0.2",
    "ts-node-dev": "^2.0.0",
    "typescript": "^5.0.0"
  }
}
EOF

# Backend tsconfig
cat > "${ROOT_DIR}/backend/tsconfig.json" <<'EOF'
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "CommonJS",
    "outDir": "dist",
    "rootDir": "src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true
  }
}
EOF

# Backend src/index.ts
cat > "${ROOT_DIR}/backend/src/index.ts" <<'EOF'
import express from "express";
import http from "http";
import { Server as IOServer } from "socket.io";
import cors from "cors";
import dotenv from "dotenv";
import { initSocketHandlers } from "./socket";

dotenv.config();
const app = express();
app.use(cors());
app.use(express.json());

app.get("/health", (req, res) => res.json({ ok: true }));

const server = http.createServer(app);
const io = new IOServer(server, {
  cors: { origin: "*" },
});

initSocketHandlers(io);

const PORT = process.env.PORT || 4000;
server.listen(PORT, () => {
  console.log(\`AdaChat backend listening on \${PORT}\`);
});
EOF

# Backend socket.ts
cat > "${ROOT_DIR}/backend/src/socket.ts" <<'EOF'
import { Server, Socket } from "socket.io";
import jwt from "jsonwebtoken";
type SocketWithUser = Socket & { userId?: string };

const onlineUsers = new Map<string, string>();

export function initSocketHandlers(io: Server) {
  io.use((socket, next) => {
    const token = socket.handshake.auth?.token;
    if (!token) return next(new Error("Auth token missing"));
    try {
      const payload: any = jwt.verify(token, process.env.JWT_SECRET || "secret");
      (socket as SocketWithUser).userId = payload.userId;
      return next();
    } catch (err) {
      return next(new Error("Auth error"));
    }
  });

  io.on("connection", (socket: SocketWithUser) => {
    const userId = socket.userId!;
    onlineUsers.set(userId, socket.id);
    io.emit("user:online", { userId });

    console.log("[socket] user connected", userId);

    socket.on("message:send", async (payload) => {
      const toSocket = onlineUsers.get(payload.to);
      const message = {
        id: "generated-id",
        from: userId,
        to: payload.to,
        content: payload.content,
        mediaUrl: payload.mediaUrl || null,
        createdAt: new Date().toISOString(),
      };
      if (toSocket) {
        io.to(toSocket).emit("message:receive", message);
      }
      socket.emit("message:sent", { tempId: payload.tempId, serverId: message.id });
    });

    socket.on("call:offer", ({ to, sdp }) => {
      const toSocket = onlineUsers.get(to);
      if (toSocket) io.to(toSocket).emit("call:offer", { from: userId, sdp });
    });
    socket.on("call:answer", ({ to, sdp }) => {
      const toSocket = onlineUsers.get(to);
      if (toSocket) io.to(toSocket).emit("call:answer", { from: userId, sdp });
    });
    socket.on("call:ice", ({ to, candidate }) => {
      const toSocket = onlineUsers.get(to);
      if (toSocket) io.to(toSocket).emit("call:ice", { from: userId, candidate });
    });

    socket.on("disconnect", () => {
      onlineUsers.delete(userId);
      io.emit("user:offline", { userId });
      console.log("[socket] user disconnected", userId);
    });
  });
}
EOF

# Frontend package.json
cat > "${ROOT_DIR}/frontend/package.json" <<'EOF'
{
  "name": "adachat-frontend",
  "version": "0.1.0",
  "private": true,
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview"
  },
  "dependencies": {
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "socket.io-client": "^4.7.0"
  },
  "devDependencies": {
    "vite": "^4.0.0",
    "@types/react": "^18.0.0",
    "@types/react-dom": "^18.0.0",
    "typescript": "^5.0.0"
  }
}
EOF

# Frontend index.html
cat > "${ROOT_DIR}/frontend/index.html" <<'EOF'
<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <title>AdaChat</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.tsx"></script>
  </body>
</html>
EOF

# Frontend main.tsx + App
cat > "${ROOT_DIR}/frontend/src/main.tsx" <<'EOF'
import React from "react";
import { createRoot } from "react-dom/client";
import App from "./App";

createRoot(document.getElementById("root")!).render(<App />);
EOF

cat > "${ROOT_DIR}/frontend/src/App.tsx" <<'EOF'
import React, { useEffect, useRef, useState } from "react";
import { io } from "socket.io-client";

const SOCKET_URL = "http://localhost:4000";

export default function App() {
  const [messages, setMessages] = useState<any[]>([]);
  const socketRef = useRef<any>(null);

  useEffect(() => {
    const token = ""; // mettre le token après login
    const socket = io(SOCKET_URL, { auth: { token } });
    socketRef.current = socket;

    socket.on("connect", () => console.log("connected", socket.id));
    socket.on("message:receive", (msg: any) => {
      setMessages((m) => [...m, msg]);
    });
    socket.on("message:sent", (ack: any) => {
      console.log("server ack", ack);
    });

    return () => socket.disconnect();
  }, []);

  const sendMessage = () => {
    const to = "recipient-user-id";
    socketRef.current.emit("message:send", { to, content: "Salut depuis AdaChat!" });
  };

  return (
    <div style={{ padding: 20 }}>
      <h1>AdaChat (demo)</h1>
      <button onClick={sendMessage}>Envoyer message</button>
      <ul>
        {messages.map((m, i) => (
          <li key={i}>{m.content} — from {m.from}</li>
        ))}
      </ul>
    </div>
  );
}
EOF

# Frontend tsconfig (minimal)
cat > "${ROOT_DIR}/frontend/tsconfig.json" <<'EOF'
{
  "compilerOptions": {
    "jsx": "react-jsx",
    "target": "ES2020",
    "module": "ESNext",
    "strict": true,
    "moduleResolution": "node"
  }
}
EOF

# CI workflow (basic)
cat > "${ROOT_DIR}/.github/workflows/ci.yml" <<'EOF'
name: CI

on: [push, pull_request]

jobs:
  build:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        dir: [backend, frontend]
    steps:
      - uses: actions/checkout@v4
      - name: Use Node.js
        uses: actions/setup-node@v4
        with:
          node-version: 18
      - name: Install deps and build (${{ matrix.dir }})
        working-directory: ${{ matrix.dir }}
        run: |
          npm ci
          npm run build || true
EOF

# Optional NOTICE file
cat > "${ROOT_DIR}/NOTICE.txt" <<'EOF'
Ne commitez PAS les secrets (fichiers .env, clefs, dumps de DB).
Utilisez .env.example et GitHub Secrets pour CI/deploy.
EOF

echo "Écriture des fichiers terminée."

# Create zip
echo "Création de ${ZIP_NAME} ..."
cd "$(dirname "$0")"
zip -r "${ZIP_NAME}" "${ROOT_DIR}" >/dev/null

echo "OK — ${ZIP_NAME} créé dans $(pwd)"
echo "Contenu du zip :"
unzip -l "${ZIP_NAME}" | sed -n '1,24p'

echo ""
echo "Tu peux maintenant télécharger ou pousser AdaChat/ sur GitHub."
EOF