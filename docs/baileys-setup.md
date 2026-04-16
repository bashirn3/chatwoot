# Baileys / Evolution API Bridge Setup

Connect WhatsApp accounts to Chatwoot via the unofficial WhatsApp Web API (Baileys) using Evolution API as a bridge service.

> **Warning**: This uses an unofficial WhatsApp API. It is not endorsed by Meta/WhatsApp and may result in account suspension. Use at your own risk and only for development, testing, or personal accounts.

## Architecture

```
WhatsApp Servers <--> Baileys (WebSocket) <--> Evolution API <--> Chatwoot API Channel
```

Evolution API runs as a separate Docker service, connects to WhatsApp via Baileys, and bridges messages to Chatwoot through the existing API Channel inbox type.

## Prerequisites

- Chatwoot running (Docker or native)
- Docker and Docker Compose installed
- A WhatsApp account to connect (phone with WhatsApp installed)

## Quick Start

### 1. Set Environment Variables

Add these to your `.env` file:

```bash
# Evolution API authentication key (generate a strong random string)
EVOLUTION_API_KEY=your-secure-api-key-here

# Chatwoot connection details
CHATWOOT_ACCOUNT_ID=1
CHATWOOT_BOT_TOKEN=your-chatwoot-bot-access-token
CHATWOOT_URL=http://rails:3000
```

To get the `CHATWOOT_BOT_TOKEN`, create an Agent Bot in Chatwoot:
1. Go to **Super Admin > Agent Bots** (or use the API)
2. Create a new agent bot
3. Copy the access token

### 2. Start Evolution API

Run alongside your existing Chatwoot Docker setup:

```bash
docker compose -f docker-compose.yaml -f docker-compose.evolution.yaml up -d
```

### 3. Create a WhatsApp Instance

Use the Evolution API to create a new WhatsApp instance:

```bash
curl -X POST http://localhost:8080/instance/create \
  -H "apikey: your-secure-api-key-here" \
  -H "Content-Type: application/json" \
  -d '{
    "instanceName": "chatwoot-whatsapp",
    "integration": "WHATSAPP-BAILEYS",
    "qrcode": true,
    "chatwoot_account_id": 1,
    "chatwoot_token": "your-chatwoot-bot-access-token",
    "chatwoot_url": "http://rails:3000",
    "chatwoot_sign_msg": false,
    "chatwoot_reopen_conversation": true,
    "chatwoot_conversation_pending": true
  }'
```

### 4. Scan QR Code

The response will include a QR code (base64 image). Scan it with your WhatsApp mobile app:

1. Open WhatsApp on your phone
2. Go to **Settings > Linked Devices > Link a Device**
3. Scan the QR code from the API response

Alternatively, access the Evolution API management panel at `http://localhost:8080/manager` to scan the QR code visually.

### 5. Verify Connection

Once connected, Evolution API automatically creates an API Channel inbox in Chatwoot. Check your Chatwoot dashboard for the new inbox.

Test by sending a WhatsApp message to the connected number -- it should appear in Chatwoot.

## Message Flow

### Inbound (WhatsApp to Chatwoot)
1. User sends a message on WhatsApp
2. Baileys receives it via WebSocket
3. Evolution API processes and formats the message
4. Evolution API sends it to Chatwoot via the API Channel endpoint
5. Message appears in the Chatwoot conversation

### Outbound (Chatwoot to WhatsApp)
1. Agent replies in Chatwoot
2. Chatwoot fires a webhook to Evolution API
3. Evolution API sends the message via Baileys
4. Message delivered to the WhatsApp user

## Configuration Options

| Variable | Description | Default |
|----------|-------------|---------|
| `EVOLUTION_API_KEY` | API authentication key | (required) |
| `CHATWOOT_ACCOUNT_ID` | Chatwoot account ID | `1` |
| `CHATWOOT_BOT_TOKEN` | Chatwoot bot access token | (required) |
| `CHATWOOT_URL` | Chatwoot base URL | `http://rails:3000` |
| `CHATWOOT_SIGN_MSG` | Sign messages with bot name | `false` |
| `CHATWOOT_REOPEN_CONVERSATION` | Reopen resolved conversations | `true` |
| `CHATWOOT_CONVERSATION_PENDING` | Create conversations as pending | `true` |
| `QRCODE_LIMIT` | QR code generation timeout (seconds) | `30` |

## Connecting Typebot

When both Typebot and Evolution API are configured, you get an end-to-end automated WhatsApp bot:

1. WhatsApp message arrives via Evolution API -> Chatwoot
2. Chatwoot's Typebot integration hook processes the message
3. Typebot executes the conversation flow
4. Bot responses are sent back through Evolution API -> WhatsApp
5. When Typebot triggers a handoff, a human agent takes over in Chatwoot

To set this up:
1. Complete the Evolution API setup above
2. Configure the Typebot integration in Chatwoot (Settings > Integrations > Typebot)
3. Assign the Typebot hook to the Evolution API inbox

## Troubleshooting

### QR Code Expired
Fetch a new QR code:
```bash
curl -X GET http://localhost:8080/instance/connect/chatwoot-whatsapp \
  -H "apikey: your-secure-api-key-here"
```

### Connection Lost
Check instance status:
```bash
curl -X GET http://localhost:8080/instance/connectionState/chatwoot-whatsapp \
  -H "apikey: your-secure-api-key-here"
```

### View Logs
```bash
docker compose -f docker-compose.yaml -f docker-compose.evolution.yaml logs -f evolution-api
```

### Reset Instance
```bash
curl -X DELETE http://localhost:8080/instance/delete/chatwoot-whatsapp \
  -H "apikey: your-secure-api-key-here"
```
Then recreate with step 3.
