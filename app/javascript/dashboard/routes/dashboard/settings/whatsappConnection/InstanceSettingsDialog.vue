<script setup>
import { ref, watch, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import WhatsAppBridgeAPI from 'dashboard/api/whatsappBridge';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const props = defineProps({
  instanceName: { type: String, default: '' },
});

const emit = defineEmits(['close']);

const { t } = useI18n();

const dialogRef = ref(null);
const isLoading = ref(false);
const isSaving = ref(false);
const activeTab = ref('profile');

const profileName = ref('');
const profileStatus = ref('');
const profilePictureUrl = ref('');
const phone = ref('');

const typingSimulation = ref(false);
const delayEnabled = ref(false);

const antiBanPreset = ref('safe');
const messagesPerHour = ref(100);

const resumeKeywords = ref('');
const resumeMessage = ref('');
const handoffChats = ref([]);
const isTogglingHandoff = ref(false);

const customWebhookUrl = ref('');

const displayInstanceName = computed(() =>
  props.instanceName.replace(/^acct-\d+-/, '')
);

const antiBanPresets = computed(() => [
  {
    value: 'safe',
    label: t('WHATSAPP_CONNECTION.SETTINGS.ANTI_BAN.PRESET_SAFE'),
  },
  {
    value: 'moderate',
    label: t('WHATSAPP_CONNECTION.SETTINGS.ANTI_BAN.PRESET_MODERATE'),
  },
  {
    value: 'aggressive',
    label: t('WHATSAPP_CONNECTION.SETTINGS.ANTI_BAN.PRESET_AGGRESSIVE'),
  },
]);

const tabs = computed(() => [
  {
    key: 'profile',
    label: t('WHATSAPP_CONNECTION.SETTINGS.PROFILE.TITLE'),
    icon: 'i-lucide-user',
  },
  {
    key: 'behavior',
    label: t('WHATSAPP_CONNECTION.SETTINGS.BEHAVIOR.TITLE'),
    icon: 'i-lucide-settings-2',
  },
  {
    key: 'antiBan',
    label: t('WHATSAPP_CONNECTION.SETTINGS.ANTI_BAN.TITLE'),
    icon: 'i-lucide-shield',
  },
  {
    key: 'handoff',
    label: t('WHATSAPP_CONNECTION.SETTINGS.HANDOFF.TITLE'),
    icon: 'i-lucide-arrow-right-left',
  },
  {
    key: 'webhooks',
    label: t('WHATSAPP_CONNECTION.SETTINGS.WEBHOOKS.TITLE'),
    icon: 'i-lucide-webhook',
  },
]);

async function loadSettings() {
  if (!props.instanceName) return;
  isLoading.value = true;
  try {
    const [
      detailResp,
      behaviorResp,
      antiBanResp,
      handoffResp,
      handoffChatsResp,
    ] = await Promise.allSettled([
      WhatsAppBridgeAPI.getInstanceDetail(props.instanceName),
      WhatsAppBridgeAPI.getBehavior(props.instanceName),
      WhatsAppBridgeAPI.getAntiBan(props.instanceName),
      WhatsAppBridgeAPI.getHandoffSettings(props.instanceName),
      WhatsAppBridgeAPI.getHandoff(props.instanceName),
    ]);

    if (detailResp.status === 'fulfilled') {
      const d = detailResp.value.data;
      profileName.value = d.profileName || d.name || '';
      profileStatus.value = d.profileStatus || '';
      profilePictureUrl.value = d.profilePicture || '';
      phone.value = d.phone || d.connectedPhone || '';
      customWebhookUrl.value = d.customWebhookUrl || '';
    }

    if (behaviorResp.status === 'fulfilled') {
      const b = behaviorResp.value.data;
      typingSimulation.value = !!b.typingSimulation;
      delayEnabled.value = !!b.delayEnabled;
    }

    if (antiBanResp.status === 'fulfilled') {
      const a = antiBanResp.value.data;
      antiBanPreset.value = a.preset || 'safe';
      messagesPerHour.value = a.messagesPerHour ?? 100;
    }

    if (handoffResp.status === 'fulfilled') {
      const h = handoffResp.value.data;
      const kw = h.resumeKeywords || [];
      resumeKeywords.value = Array.isArray(kw) ? kw.join(', ') : kw;
      resumeMessage.value = h.resumeMessage || '';
    }

    if (handoffChatsResp.status === 'fulfilled') {
      handoffChats.value = handoffChatsResp.value.data.humanModeChats || [];
    }
  } finally {
    isLoading.value = false;
  }
}

async function saveProfile() {
  isSaving.value = true;
  try {
    const calls = [];
    if (profileName.value) {
      calls.push(
        WhatsAppBridgeAPI.updateProfileName(
          props.instanceName,
          profileName.value
        )
      );
    }
    if (profileStatus.value) {
      calls.push(
        WhatsAppBridgeAPI.updateProfileStatus(
          props.instanceName,
          profileStatus.value
        )
      );
    }
    if (profilePictureUrl.value) {
      calls.push(
        WhatsAppBridgeAPI.updateProfilePicture(
          props.instanceName,
          profilePictureUrl.value
        )
      );
    }
    await Promise.all(calls);
    useAlert(t('WHATSAPP_CONNECTION.SETTINGS.SAVED'));
  } catch {
    useAlert(t('WHATSAPP_CONNECTION.SETTINGS.SAVE_ERROR'));
  } finally {
    isSaving.value = false;
  }
}

async function saveBehavior() {
  isSaving.value = true;
  try {
    await WhatsAppBridgeAPI.updateBehavior(props.instanceName, {
      typingSimulation: typingSimulation.value,
      delayEnabled: delayEnabled.value,
    });
    useAlert(t('WHATSAPP_CONNECTION.SETTINGS.SAVED'));
  } catch {
    useAlert(t('WHATSAPP_CONNECTION.SETTINGS.SAVE_ERROR'));
  } finally {
    isSaving.value = false;
  }
}

async function saveAntiBan() {
  isSaving.value = true;
  try {
    await WhatsAppBridgeAPI.updateAntiBan(props.instanceName, {
      preset: antiBanPreset.value,
      messagesPerHour: Number(messagesPerHour.value),
    });
    useAlert(t('WHATSAPP_CONNECTION.SETTINGS.SAVED'));
  } catch {
    useAlert(t('WHATSAPP_CONNECTION.SETTINGS.SAVE_ERROR'));
  } finally {
    isSaving.value = false;
  }
}

async function saveHandoff() {
  isSaving.value = true;
  try {
    const keywords = resumeKeywords.value
      .split(',')
      .map(k => k.trim())
      .filter(Boolean);
    await WhatsAppBridgeAPI.updateHandoffSettings(props.instanceName, {
      resumeKeywords: keywords,
      resumeMessage: resumeMessage.value,
    });
    useAlert(t('WHATSAPP_CONNECTION.SETTINGS.SAVED'));
  } catch {
    useAlert(t('WHATSAPP_CONNECTION.SETTINGS.SAVE_ERROR'));
  } finally {
    isSaving.value = false;
  }
}

async function resumeBotForChat(chatPhone) {
  isTogglingHandoff.value = true;
  try {
    await WhatsAppBridgeAPI.updateHandoff(props.instanceName, {
      phone: chatPhone,
      active: false,
    });
    handoffChats.value = handoffChats.value.filter(c => c.phone !== chatPhone);
    useAlert(t('WHATSAPP_CONNECTION.SETTINGS.HANDOFF.CLEAR_SUCCESS'));
  } catch {
    useAlert(t('WHATSAPP_CONNECTION.SETTINGS.HANDOFF.CLEAR_ERROR'));
  } finally {
    isTogglingHandoff.value = false;
  }
}

async function resumeBotForAll() {
  isTogglingHandoff.value = true;
  try {
    await Promise.all(
      handoffChats.value.map(c =>
        WhatsAppBridgeAPI.updateHandoff(props.instanceName, {
          phone: c.phone,
          active: false,
        })
      )
    );
    handoffChats.value = [];
    useAlert(t('WHATSAPP_CONNECTION.SETTINGS.HANDOFF.CLEAR_ALL_SUCCESS'));
  } catch {
    useAlert(t('WHATSAPP_CONNECTION.SETTINGS.HANDOFF.CLEAR_ERROR'));
  } finally {
    isTogglingHandoff.value = false;
  }
}

function formatDate(isoString) {
  if (!isoString) return '';
  return new Date(isoString).toLocaleString();
}

async function saveWebhooks() {
  isSaving.value = true;
  try {
    await WhatsAppBridgeAPI.updateInstance(props.instanceName, {
      customWebhookUrl: customWebhookUrl.value,
    });
    useAlert(t('WHATSAPP_CONNECTION.SETTINGS.SAVED'));
  } catch {
    useAlert(t('WHATSAPP_CONNECTION.SETTINGS.SAVE_ERROR'));
  } finally {
    isSaving.value = false;
  }
}

function handleSave() {
  const handlers = {
    profile: saveProfile,
    behavior: saveBehavior,
    antiBan: saveAntiBan,
    handoff: saveHandoff,
    webhooks: saveWebhooks,
  };
  handlers[activeTab.value]?.();
}

function open() {
  dialogRef.value?.open();
  loadSettings();
}

function close() {
  emit('close');
}

watch(
  () => props.instanceName,
  val => {
    if (val) loadSettings();
  }
);

defineExpose({ open, close });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="`${t('WHATSAPP_CONNECTION.SETTINGS.TITLE')} — ${displayInstanceName}`"
    :confirm-button-label="t('WHATSAPP_CONNECTION.SETTINGS.SAVE')"
    :is-loading="isSaving"
    width="2xl"
    @confirm="handleSave"
    @close="close"
  >
    <!-- Loading state -->
    <div
      v-if="isLoading"
      class="flex items-center justify-center gap-2 py-8 text-n-slate-11"
    >
      <span class="i-lucide-loader-2 size-4 animate-spin" />
      <span class="text-sm">
        {{ t('WHATSAPP_CONNECTION.SETTINGS.LOADING') }}
      </span>
    </div>

    <div v-else class="flex flex-col gap-4">
      <!-- Tabs -->
      <div class="flex gap-1 rounded-lg bg-n-alpha-black2 p-1">
        <button
          v-for="tab in tabs"
          :key="tab.key"
          type="button"
          class="flex flex-1 items-center justify-center gap-1.5 rounded-md px-3 py-2 text-xs font-medium transition-colors"
          :class="
            activeTab === tab.key
              ? 'bg-n-solid-2 text-n-slate-12 shadow-sm'
              : 'text-n-slate-10 hover:text-n-slate-12'
          "
          @click="activeTab = tab.key"
        >
          <span :class="tab.icon" class="size-3.5" />
          {{ tab.label }}
        </button>
      </div>

      <!-- Profile Tab -->
      <div v-if="activeTab === 'profile'" class="flex flex-col gap-4">
        <div v-if="phone" class="flex flex-col gap-1">
          <label class="text-xs font-medium text-n-slate-11">
            {{ t('WHATSAPP_CONNECTION.SETTINGS.PROFILE.PHONE') }}
          </label>
          <p class="text-sm text-n-slate-12">
            {{ phone }}
          </p>
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-xs font-medium text-n-slate-11">
            {{ t('WHATSAPP_CONNECTION.SETTINGS.PROFILE.NAME') }}
          </label>
          <input
            v-model="profileName"
            type="text"
            class="rounded-lg border border-n-weak bg-n-alpha-black2 px-3 py-2 text-sm text-n-slate-12 placeholder:text-n-slate-10 focus:border-transparent focus:outline-none focus:ring-2 focus:ring-woot-500"
            :placeholder="
              t('WHATSAPP_CONNECTION.SETTINGS.PROFILE.NAME_PLACEHOLDER')
            "
          />
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-xs font-medium text-n-slate-11">
            {{ t('WHATSAPP_CONNECTION.SETTINGS.PROFILE.STATUS') }}
          </label>
          <input
            v-model="profileStatus"
            type="text"
            class="rounded-lg border border-n-weak bg-n-alpha-black2 px-3 py-2 text-sm text-n-slate-12 placeholder:text-n-slate-10 focus:border-transparent focus:outline-none focus:ring-2 focus:ring-woot-500"
            :placeholder="
              t('WHATSAPP_CONNECTION.SETTINGS.PROFILE.STATUS_PLACEHOLDER')
            "
          />
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-xs font-medium text-n-slate-11">
            {{ t('WHATSAPP_CONNECTION.SETTINGS.PROFILE.PICTURE_URL') }}
          </label>
          <input
            v-model="profilePictureUrl"
            type="text"
            class="rounded-lg border border-n-weak bg-n-alpha-black2 px-3 py-2 text-sm text-n-slate-12 placeholder:text-n-slate-10 focus:border-transparent focus:outline-none focus:ring-2 focus:ring-woot-500"
            :placeholder="
              t('WHATSAPP_CONNECTION.SETTINGS.PROFILE.PICTURE_URL_PLACEHOLDER')
            "
          />
        </div>
      </div>

      <!-- Behavior Tab -->
      <div v-if="activeTab === 'behavior'" class="flex flex-col gap-4">
        <label
          class="flex cursor-pointer items-center justify-between rounded-lg border border-n-weak bg-n-solid-2 p-4"
        >
          <div class="flex flex-col gap-0.5">
            <span class="text-sm font-medium text-n-slate-12">
              {{ t('WHATSAPP_CONNECTION.SETTINGS.BEHAVIOR.TYPING_SIMULATION') }}
            </span>
            <span class="text-xs text-n-slate-10">
              {{
                t(
                  'WHATSAPP_CONNECTION.SETTINGS.BEHAVIOR.TYPING_SIMULATION_HELP'
                )
              }}
            </span>
          </div>
          <input
            v-model="typingSimulation"
            type="checkbox"
            class="size-4 rounded border-n-weak text-woot-500 focus:ring-woot-500"
          />
        </label>
        <label
          class="flex cursor-pointer items-center justify-between rounded-lg border border-n-weak bg-n-solid-2 p-4"
        >
          <div class="flex flex-col gap-0.5">
            <span class="text-sm font-medium text-n-slate-12">
              {{ t('WHATSAPP_CONNECTION.SETTINGS.BEHAVIOR.DELAY_ENABLED') }}
            </span>
            <span class="text-xs text-n-slate-10">
              {{
                t('WHATSAPP_CONNECTION.SETTINGS.BEHAVIOR.DELAY_ENABLED_HELP')
              }}
            </span>
          </div>
          <input
            v-model="delayEnabled"
            type="checkbox"
            class="size-4 rounded border-n-weak text-woot-500 focus:ring-woot-500"
          />
        </label>
      </div>

      <!-- Anti-Ban Tab -->
      <div v-if="activeTab === 'antiBan'" class="flex flex-col gap-4">
        <div class="flex flex-col gap-1">
          <label class="text-xs font-medium text-n-slate-11">
            {{ t('WHATSAPP_CONNECTION.SETTINGS.ANTI_BAN.PRESET') }}
          </label>
          <div class="flex gap-2">
            <button
              v-for="preset in antiBanPresets"
              :key="preset.value"
              type="button"
              class="flex-1 rounded-lg border px-3 py-2 text-xs font-medium transition-colors"
              :class="
                antiBanPreset === preset.value
                  ? 'border-woot-500 bg-woot-500/10 text-woot-600 dark:text-woot-400'
                  : 'border-n-weak bg-n-solid-2 text-n-slate-11 hover:text-n-slate-12'
              "
              @click="antiBanPreset = preset.value"
            >
              {{ preset.label }}
            </button>
          </div>
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-xs font-medium text-n-slate-11">
            {{ t('WHATSAPP_CONNECTION.SETTINGS.ANTI_BAN.MESSAGES_PER_HOUR') }}
          </label>
          <span class="text-xs text-n-slate-10">
            {{
              t('WHATSAPP_CONNECTION.SETTINGS.ANTI_BAN.MESSAGES_PER_HOUR_HELP')
            }}
          </span>
          <input
            v-model.number="messagesPerHour"
            type="number"
            min="1"
            max="1000"
            class="rounded-lg border border-n-weak bg-n-alpha-black2 px-3 py-2 text-sm text-n-slate-12 focus:border-transparent focus:outline-none focus:ring-2 focus:ring-woot-500"
          />
        </div>
      </div>

      <!-- Handoff Tab -->
      <div v-if="activeTab === 'handoff'" class="flex flex-col gap-4">
        <!-- Active handoff chats -->
        <div class="flex flex-col gap-2">
          <div class="flex items-center justify-between">
            <label class="text-xs font-medium text-n-slate-11">
              {{ t('WHATSAPP_CONNECTION.SETTINGS.HANDOFF.ACTIVE_CHATS') }}
            </label>
            <button
              v-if="handoffChats.length"
              type="button"
              class="inline-flex items-center gap-1 rounded-md px-2 py-1 text-xs font-medium text-woot-600 transition-colors hover:bg-woot-500/10 dark:text-woot-400"
              :disabled="isTogglingHandoff"
              @click="resumeBotForAll"
            >
              <span class="i-lucide-bot size-3" />
              {{ t('WHATSAPP_CONNECTION.SETTINGS.HANDOFF.RESUME_ALL') }}
            </button>
          </div>
          <span class="text-xs text-n-slate-10">
            {{ t('WHATSAPP_CONNECTION.SETTINGS.HANDOFF.ACTIVE_CHATS_HELP') }}
          </span>

          <div
            v-if="handoffChats.length"
            class="flex flex-col gap-1 rounded-lg border border-n-weak"
          >
            <div
              v-for="chat in handoffChats"
              :key="chat.jid || chat.phone"
              class="flex items-center justify-between border-b border-n-weak px-3 py-2.5 last:border-b-0"
            >
              <div class="flex flex-col gap-0.5">
                <span class="text-sm font-medium text-n-slate-12">
                  +{{ chat.phone }}
                </span>
                <span class="text-xs text-n-slate-10">
                  {{ t('WHATSAPP_CONNECTION.SETTINGS.HANDOFF.TAGGED_AT') }}
                  {{ formatDate(chat.taggedAt) }}
                </span>
              </div>
              <button
                type="button"
                class="inline-flex items-center gap-1 rounded-md bg-n-alpha-black2 px-2 py-1 text-xs font-medium text-n-slate-12 transition-colors hover:bg-n-alpha-3"
                :disabled="isTogglingHandoff"
                @click="resumeBotForChat(chat.phone)"
              >
                <span class="i-lucide-bot size-3" />
                {{ t('WHATSAPP_CONNECTION.SETTINGS.HANDOFF.RESUME_BOT') }}
              </button>
            </div>
          </div>

          <div
            v-else
            class="rounded-lg border border-dashed border-n-weak p-4 text-center text-xs text-n-slate-10"
          >
            {{ t('WHATSAPP_CONNECTION.SETTINGS.HANDOFF.NO_ACTIVE_CHATS') }}
          </div>
        </div>

        <!-- Handoff settings -->
        <div class="flex flex-col gap-1">
          <label class="text-xs font-medium text-n-slate-11">
            {{ t('WHATSAPP_CONNECTION.SETTINGS.HANDOFF.RESUME_KEYWORDS') }}
          </label>
          <span class="text-xs text-n-slate-10">
            {{ t('WHATSAPP_CONNECTION.SETTINGS.HANDOFF.RESUME_KEYWORDS_HELP') }}
          </span>
          <input
            v-model="resumeKeywords"
            type="text"
            class="rounded-lg border border-n-weak bg-n-alpha-black2 px-3 py-2 text-sm text-n-slate-12 placeholder:text-n-slate-10 focus:border-transparent focus:outline-none focus:ring-2 focus:ring-woot-500"
            :placeholder="
              t(
                'WHATSAPP_CONNECTION.SETTINGS.HANDOFF.RESUME_KEYWORDS_PLACEHOLDER'
              )
            "
          />
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-xs font-medium text-n-slate-11">
            {{ t('WHATSAPP_CONNECTION.SETTINGS.HANDOFF.RESUME_MESSAGE') }}
          </label>
          <span class="text-xs text-n-slate-10">
            {{ t('WHATSAPP_CONNECTION.SETTINGS.HANDOFF.RESUME_MESSAGE_HELP') }}
          </span>
          <input
            v-model="resumeMessage"
            type="text"
            class="rounded-lg border border-n-weak bg-n-alpha-black2 px-3 py-2 text-sm text-n-slate-12 placeholder:text-n-slate-10 focus:border-transparent focus:outline-none focus:ring-2 focus:ring-woot-500"
            :placeholder="
              t(
                'WHATSAPP_CONNECTION.SETTINGS.HANDOFF.RESUME_MESSAGE_PLACEHOLDER'
              )
            "
          />
        </div>
      </div>

      <!-- Webhooks Tab -->
      <div v-if="activeTab === 'webhooks'" class="flex flex-col gap-4">
        <div
          class="rounded-lg border border-n-weak bg-n-alpha-black2 p-3 text-xs text-n-slate-11"
        >
          {{ t('WHATSAPP_CONNECTION.SETTINGS.WEBHOOKS.DESCRIPTION') }}
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-xs font-medium text-n-slate-11">
            {{ t('WHATSAPP_CONNECTION.SETTINGS.WEBHOOKS.CUSTOM_URL') }}
          </label>
          <span class="text-xs text-n-slate-10">
            {{ t('WHATSAPP_CONNECTION.SETTINGS.WEBHOOKS.CUSTOM_URL_HELP') }}
          </span>
          <input
            v-model="customWebhookUrl"
            type="url"
            class="rounded-lg border border-n-weak bg-n-alpha-black2 px-3 py-2 text-sm text-n-slate-12 placeholder:text-n-slate-10 focus:border-transparent focus:outline-none focus:ring-2 focus:ring-woot-500"
            :placeholder="
              t('WHATSAPP_CONNECTION.SETTINGS.WEBHOOKS.CUSTOM_URL_PLACEHOLDER')
            "
          />
        </div>
      </div>
    </div>
  </Dialog>
</template>
