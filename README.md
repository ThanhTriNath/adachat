# AdaChat - MVP

Aperçu : AdaChat est une application de messagerie (search friends, stories, messages, appels WebRTC).

Prérequis :
- Node 18+
- PostgreSQL
- AWS S3 (ou compatible)
- yarn / npm

Développement rapide :
1. Copier .env.example -> .env et remplir
2. yarn install (backend et frontend)
3. Exécuter migrations Prisma : npx prisma migrate dev
4. Lancer le backend : yarn dev:backend
5. Lancer le frontend : yarn dev:frontend

Notes :
- Ce repo contient un backend minimal avec Express + Socket.IO et un frontend React sample.
- Pour production, utiliser Docker et un hébergement managé pour la DB et le stockage média.
