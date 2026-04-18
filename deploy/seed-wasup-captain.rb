# Seeds Wasup-branded FAQs + Documents for the Captain assistant on Account 1.
# Run remotely via: bundle exec rails runner deploy/seed-wasup-captain.rb

assistant = Captain::Assistant.find_by(account_id: 1, name: 'asd') || Captain::Assistant.find(5)
abort 'No Captain assistant found on account 1' unless assistant

assistant.update!(
  name: 'Wasup',
  description: 'AI receptionist for Wasup.co — answers on WhatsApp 24/7, qualifies leads, books meetings, and reactivates old customers.',
  config: (assistant.config || {}).merge(
    'product_name' => 'Wasup',
    'feature_faq' => true,
    'feature_memory' => true,
    'feature_citation' => true
  )
)
puts "Assistant updated: ##{assistant.id} #{assistant.name}"

faqs = [
  {
    q: 'What is Wasup?',
    a: "Wasup is a done-for-you WhatsApp AI service. We build and run a 24/7 AI agent that answers leads within seconds, books appointments, qualifies customers, and re-engages old contacts. You only pay if it works — if it doesn't, you pay €0."
  },
  {
    q: "How is Wasup different from WATI, Twilio, ManyChat, or Respond.io?",
    a: "We use Meta infrastructure where it makes sense, but we're not locked into a rigid API-only setup. You can run inbound only, light outbound, or a blended setup — without being forced into a heavy Meta API dependency from day one. We also build the workflow for you."
  },
  {
    q: 'Do you rely entirely on the Meta WhatsApp Business API?',
    a: "No. Most platforms push you into a full Meta API setup with conversation charges, approval pipelines, and template dependencies. Wasup gives you the flexibility to use Meta where it makes sense while keeping things simple when it doesn't, so you can scale gradually."
  },
  {
    q: 'Can I message customers after 24 hours?',
    a: "With strict Meta API setups, once 24 hours passes you need an approved template to re-engage. Because Wasup structures accounts inbound-first with controlled outbound, you're not boxed into constant template usage just to maintain normal conversations."
  },
  {
    q: 'What does "inbound first" mean?',
    a: 'Customers message you, the AI handles the conversation, and you can respond freely without complex template logic. This works well for daily support, bookings, and lead management without running into Meta template limits.'
  },
  {
    q: 'How fast is setup?',
    a: 'Inbound setup takes about 5 minutes with a simple QR scan. API-heavy platforms require Meta Business verification, Business Manager approval, template setup, and phone registration, which can take days.'
  },
  {
    q: 'Are there limits on AI conversations?',
    a: 'No. Wasup offers unlimited inbound and controlled outbound with AI built in — no conversation-based billing and no caps on AI sessions.'
  },
  {
    q: 'Can you integrate with our CRM, even if it has no API?',
    a: "Yes. Wasup can integrate even if your CRM has no public API. Our AI agents interact with systems directly and connect workflows without traditional technical limitations, so we can plug into almost any environment."
  },
  {
    q: 'What is the risk of bans or compliance issues?',
    a: "For inbound-only setups the risk is effectively zero. For light outbound used in GDPR-compliant cases (e.g. re-engagement with prior consent), the risk is extremely low. If a ban happens, we can typically appeal within 24 hours and reinstate within 3 working days. For Meta-API outbound used responsibly the risk profile is similar; reinstatement within 5 working days. If reinstatement isn't possible, we provision a new number and account to maintain continuity."
  },
  {
    q: 'Will we lose WhatsApp calls or the WhatsApp Business app?',
    a: 'With many full API migrations, businesses lose WhatsApp calling and the native Business app. Our inbound-first setup lets you keep that flexibility instead of forcing a full migration.'
  },
  {
    q: 'Can you integrate into our existing workflows?',
    a: 'Yes — we build CRM integrations, email flows, and custom automation logic tailored to your internal processes. We combine technology with execution so we optimise for outcomes, not just software access.'
  },
  {
    q: 'How much does Wasup cost?',
    a: <<~TXT
      Three plans, priced by what you need — not features:

      • AI WhatsApp Agent — €199/mo: 24/7 AI receptionist, FAQ answers, detail capture, booking requests, multi-language, full platform access, setup + support included, unlimited inbound WhatsApp.
      • Lead Gen + Follow-up Agent — €599/mo: everything in the first plan plus automated WhatsApp follow-ups, recall/re-engage campaigns, post-service follow-up, AI explainability, 500 outbound WhatsApp/mo.
      • Full AI Growth System — €999/mo: everything in the previous plan plus missed-call recovery (WhatsApp + Voice AI), 30-second Meta & Google Ads lead follow-up, Instagram / TikTok / Messenger DM automation, 1500 outbound WhatsApp/mo.

      No setup cost. Pay only when it works.
    TXT
  },
  {
    q: 'How does the free trial work?',
    a: "Step 1: book a 1-hour call so we can define your custom inbound agent. Step 2: we give you a 7-day free trial to test your agent's performance over WhatsApp. Step 3: you deploy by scanning a QR code — the agent runs on your live number. Step 4: you launch campaigns to re-engage existing customers."
  },
  {
    q: 'What results do customers typically see?',
    a: '100% of missed calls and messages followed up automatically; 20–50% more bookings from existing leads; faster response times = higher conversion; and roughly 30× cheaper than hiring — monthly cost is less than a daily wage and the agent runs 24h.'
  },
  {
    q: 'How do I book a demo or get started?',
    a: 'Book a free consultation at https://calendly.com/rasmusaraviita/wasup-co-consultation — about 90% of our customers go live after one call.'
  },
  {
    q: 'I need to speak to a human agent.',
    a: "Of course — I'll hand you over to the team now. One moment."
  }
]

faqs.each do |row|
  rec = Captain::AssistantResponse.find_or_initialize_by(
    account_id: assistant.account_id,
    assistant_id: assistant.id,
    question: row[:q]
  )
  rec.answer = row[:a]
  rec.status = :approved if rec.respond_to?(:status=)
  rec.save!
end
puts "FAQs seeded: #{faqs.size}"

documents = [
  {
    name: 'Wasup — Overview',
    url: 'https://wasup.co/',
    content: <<~DOC
      # Wasup — We build your customer workflows. Or you don't pay.

      Wasup is a done-for-you WhatsApp AI service. We build, deploy, and run a 24/7 AI agent on your live WhatsApp number that:

      - Responds to leads in seconds, including nights and weekends.
      - Automatically books appointments, qualifies prospects, and handles follow-ups.
      - Turns missed calls and old contacts back into revenue.
      - Integrates into your CRM/ERP/spreadsheet — even if it has no API.

      ## Try it in your own business. Pay only if it works.
      We build your automation first. You test it with real customers. Only pay when you're satisfied. If it doesn't work, you pay €0.

      ## Why Wasup
      - Always available: instant replies, FAQ, pricing, availability prompts.
      - Reactivate old clients automatically — turn chats into booked appointments with handover, booking link, and deposits.
      - We build the workflow: we map your manual process, automate it end-to-end, and run it for you.
      - Works with your existing system, no matter how messy — CRM, ERP, booking tools, and spreadsheets across multiple systems, API or not.

      ## Typical impact
      - 100% of missed calls and messages followed up automatically.
      - 20–50% more bookings from existing leads.
      - Faster response times → higher conversion.
      - ~30× cheaper than hiring (monthly cost < a daily wage, runs 24h).
    DOC
  },
  {
    name: 'Wasup — Pricing',
    url: 'https://wasup.co/#pricing',
    content: <<~DOC
      # Pricing

      Pricing is based on what you need, not features. No setup cost. Pay only when it works.

      ## €199 / month — AI WhatsApp Agent
      - 24/7 AI receptionist
      - Answers FAQs and captures customer details
      - Helps customers request and confirm bookings
      - Multi-language support
      - Full access to the Wasup dashboard
      - Setup, onboarding and support included
      - Unlimited inbound WhatsApp

      ## €599 / month — WhatsApp Lead Gen + Follow-up Agent
      Everything in €199 plus:
      - Automated WhatsApp follow-ups
      - Recall and re-engage campaigns
      - Follow-up with customers who didn't book
      - Re-engage old and lapsed leads automatically
      - Campaign scheduling inside the Wasup platform
      - Post-service follow-up
      - Unlimited inbound WhatsApp + 500 outbound WhatsApp/month
      - AI explainability / decision bias

      ## €999 / month — Full AI Growth System
      Everything in €599 plus:
      - Missed-call recovery via WhatsApp + Voice AI
      - Instant WhatsApp follow-up for Meta & Google Ads leads (within 30 seconds)
      - Instagram, TikTok, and Messenger DM automation
      - Full multi-channel conversion system
      - Unlimited inbound WhatsApp + 1500 outbound WhatsApp/month
    DOC
  },
  {
    name: 'Wasup — How it works',
    url: 'https://wasup.co/#how-it-works',
    content: <<~DOC
      # Getting started

      Four steps from first call to live agent:

      1. **Book a 1h call** — we define your custom inbound agent together.
      2. **Test the agent** — 7-day free trial on WhatsApp, collect feedback.
      3. **Deploy** — scan a QR code; the agent runs on your live WhatsApp number.
      4. **Launch campaigns** — use the Wasup platform or your CRM to re-engage hundreds of existing customers.

      90% of customers go live after one call. Book a free demo:
      https://calendly.com/rasmusaraviita/wasup-co-consultation
    DOC
  },
  {
    name: 'Wasup — Compliance & risk',
    url: 'https://compliance.wasup.co/',
    content: <<~DOC
      # Compliance and risk posture

      - **Inbound-only setups**: ban and compliance risk is effectively zero.
      - **Light outbound (GDPR-compliant use, e.g. re-engaging customers with prior consent)**: very low risk. In the rare case of a ban, we typically appeal within 24 hours and reinstate within 3 working days.
      - **Meta API outbound used responsibly**: similar risk profile. Typical reinstatement within 5 working days. If reinstatement isn't possible, we provision a new number and account to maintain continuity.
      - **Cold outreach without consent**: significantly increases ban risk — we don't recommend it.

      We document consent and structure accounts inbound-first so you're not forced into constant template usage just to hold normal conversations.
    DOC
  },
  {
    name: 'Wasup — Integrations',
    url: 'https://wasup.co/#integrations',
    content: <<~DOC
      # Integrations

      Wasup integrates with your existing stack — you don't move to a new platform.

      - Active integrations with all major CRMs.
      - Can integrate even when your CRM has no public API — our agents interact with systems directly.
      - Email flows, booking tools, spreadsheets, ERPs — we connect what you already use.
      - No new platform to learn. No dev work required.
    DOC
  }
]

documents.each do |doc|
  rec = Captain::Document.find_or_initialize_by(
    account_id: assistant.account_id,
    assistant_id: assistant.id,
    name: doc[:name]
  )
  rec.external_link = doc[:url]
  rec.content = doc[:content]
  rec.status = :available if rec.respond_to?(:status=)
  rec.save!
end
puts "Documents seeded: #{documents.size}"

puts "Done. Test in Captain Playground as assistant ##{assistant.id} (#{assistant.name})."
