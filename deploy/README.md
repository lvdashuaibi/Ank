# Ank Production Deploy

This compose file runs the Go API + embedded PC web console with a persistent
Postgres volume.

Create `/opt/ank/.env` on the server:

```env
POSTGRES_PASSWORD=replace-with-a-strong-password
JWT_SECRET=replace-with-a-long-random-secret
AI_BASE_URL=https://api.deepseek.com
AI_MODEL=deepseek-v4-pro
AI_API_KEY=replace-with-provider-key
```

Then run:

```bash
docker compose --env-file .env -f docker-compose.yml up -d --build
```
