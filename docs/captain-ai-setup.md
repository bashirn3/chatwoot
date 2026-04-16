# Captain AI Co-pilot Setup

Chatwoot includes a built-in AI system called **Captain** that provides agent assistance, reply suggestions, conversation summaries, and more.

## Architecture Overview

Captain operates at two levels:

- **OSS (Community Edition)**: Task services for summarize, rewrite, reply suggestions, label suggestions, and follow-up actions. Available to all self-hosted installations.
- **Enterprise Edition**: Full co-pilot chat panel with threaded conversations, tool usage, automated inbox assistants, knowledge base, FAQ generation, and document embedding.

## Quick Setup (OSS)

### 1. Set the OpenAI API Key

Captain uses OpenAI-compatible APIs. Configure the key via Chatwoot's Super Admin panel:

1. Go to **Super Admin > Installation Configs**
2. Add or update `CAPTAIN_OPEN_AI_API_KEY` with your OpenAI API key

Alternatively, set it via Rails console:

```ruby
InstallationConfig.where(name: 'CAPTAIN_OPEN_AI_API_KEY').first_or_create(value: 'sk-your-key-here')
```

### 2. (Optional) Custom API Endpoint

To use an OpenAI-compatible API (e.g., Azure OpenAI, local LLM server):

```ruby
InstallationConfig.where(name: 'CAPTAIN_OPEN_AI_ENDPOINT').first_or_create(value: 'https://your-api-endpoint.com/')
```

### 3. Enable Captain Tasks Feature Flag

Enable the `captain_tasks` feature flag on your account:

```ruby
account = Account.find(1)  # your account ID
account.enable_features('captain_tasks')
account.save!
```

### 4. (Optional) Per-Account API Key

Instead of a system-wide key, you can configure per-account API keys via the OpenAI integration:

1. Go to **Settings > Integrations > OpenAI**
2. Add your API key
3. This key takes priority over the system-wide key for that account

## Available Features (OSS)

Once configured, agents get access to these features in the reply composer:

| Feature | Description | Triggered By |
|---------|-------------|--------------|
| **Rewrite** | Improves and polishes draft replies | Reply box copilot menu |
| **Summarize** | Generates a conversation summary | Reply box copilot menu |
| **Reply Suggestion** | Suggests a reply based on conversation context | Reply box copilot menu |
| **Label Suggestion** | Suggests labels for conversations | Automatic (if enabled) |
| **Follow Up** | Suggests follow-up actions | Reply box copilot menu |

## Enterprise Features

With Enterprise Edition and the `captain_integration` feature flag:

### Co-pilot Side Panel
A full AI chat interface in the conversation sidebar where agents can:
- Ask questions about the current conversation
- Get context-aware suggestions
- Use built-in tools (search documentation, look up contacts, etc.)

### Inbox Assistant
Automated AI responses for customer-facing inboxes:
1. Go to **Settings > Captain > Assistants**
2. Create an assistant with instructions and knowledge base
3. Link the assistant to an inbox
4. The assistant automatically responds to incoming messages

### Knowledge Base
Upload documents and crawl websites to give Captain context:
1. Go to **Settings > Captain > Documents**
2. Upload PDFs, text files, or add website URLs
3. Captain uses embeddings to search the knowledge base when responding

## Model Configuration

Captain supports multiple LLM models configured in `config/llm.yml`:

| Model | Provider | Best For |
|-------|----------|----------|
| `gpt-4.1-mini` (default) | OpenAI | General tasks, cost-effective |
| `gpt-4.1` | OpenAI | Complex reasoning |
| `gpt-5.1` | OpenAI | Advanced tasks |

Per-account model preferences can be configured via the Captain Preferences API:

```ruby
account = Account.find(1)
account.update(captain_models: { 'copilot' => 'gpt-4.1', 'editor' => 'gpt-4.1-mini' })
account.update(captain_features: { 'copilot' => true, 'editor' => true })
```

## Integration with Typebot and Evolution API

Captain works seamlessly with the Typebot and Evolution API integrations:

### Typebot + Captain Flow
1. Customer messages arrive (via WhatsApp/Evolution API or any channel)
2. Typebot handles the automated conversation flow
3. When Typebot hands off to a human agent, Captain assists:
   - **Summarize** the bot conversation so the agent has context
   - **Suggest replies** based on the conversation history
   - **Rewrite** agent drafts for clarity and tone

### No Additional Configuration Needed
Captain operates on conversation messages regardless of their source channel. Once enabled, it automatically works with:
- WhatsApp messages (via official API or Evolution API/Baileys)
- Typebot-handled conversations after handoff
- All other Chatwoot channels

## Environment Variables Reference

| Variable | Description | Default |
|----------|-------------|---------|
| `CAPTAIN_OPEN_AI_API_KEY` | OpenAI API key (via InstallationConfig) | (none) |
| `CAPTAIN_OPEN_AI_ENDPOINT` | Custom OpenAI-compatible endpoint | `https://api.openai.com/` |
| `CAPTAIN_OPEN_AI_MODEL` | Default model override | `gpt-4.1-mini` |
| `CAPTAIN_EMBEDDING_MODEL` | Model for document embeddings (Enterprise) | (default) |
| `CAPTAIN_FIRECRAWL_API_KEY` | Firecrawl API key for web crawling (Enterprise) | (none) |

## Feature Flags Reference

| Flag | Scope | Description |
|------|-------|-------------|
| `captain_tasks` | Account | Enables OSS task services (summarize, rewrite, etc.) |
| `captain_integration` | Account (Enterprise) | Enables full Captain integration (copilot, assistants) |

## Troubleshooting

### "Captain is disabled"
Enable the `captain_tasks` feature flag on the account.

### "API key missing"
Set `CAPTAIN_OPEN_AI_API_KEY` in Installation Configs or add an OpenAI integration hook.

### Copilot panel not visible
The copilot side panel requires Enterprise Edition with `captain_integration` enabled and the `CAPTAIN` frontend feature flag.

### Model not available
Check `config/llm.yml` to see available models. Some models may be marked `coming_soon: true`.
