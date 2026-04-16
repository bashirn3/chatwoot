<script setup>
import { ref, computed, onMounted, defineAsyncComponent } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import TypebotsAPI from 'dashboard/api/typebots';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import ChannelSelector from 'dashboard/components/ChannelSelector.vue';

const BaseSettingsHeader = defineAsyncComponent(
  () => import('../components/BaseSettingsHeader.vue')
);
const SettingsLayout = defineAsyncComponent(
  () => import('../SettingsLayout.vue')
);

const { t } = useI18n();
const store = useStore();

const currentView = ref('list');
const typebots = ref([]);
const isLoading = ref(false);
const isCreating = ref(false);
const newBotName = ref('');
const configError = ref(false);
const assignDialogRef = ref(null);
const assignBotId = ref(null);
const selectedInboxId = ref('');

const webhookName = ref('');
const webhookUrl = ref('');

const inboxes = computed(() => store.getters['inboxes/getInboxes'] || []);

async function fetchBots() {
  isLoading.value = true;
  try {
    const { data } = await TypebotsAPI.getAll();
    typebots.value = data.typebots || [];
    if (data.error) {
      useAlert(data.error);
    }
  } catch (e) {
    if (e?.response?.status === 503) {
      configError.value = true;
    }
    const msg = e?.response?.data?.error;
    if (msg) {
      useAlert(msg);
    }
  } finally {
    isLoading.value = false;
  }
}

function showSelector() {
  currentView.value = 'selector';
}

function selectVisualBot() {
  currentView.value = 'create-visual';
}

function selectWebhookBot() {
  currentView.value = 'create-webhook';
}

function backToList() {
  currentView.value = 'list';
}

function builderBaseUrl() {
  return (window.chatwootConfig?.typebotBuilderUrl || '').replace(/\/$/, '');
}

async function editBot(bot) {
  const base = builderBaseUrl();
  try {
    const { data } = await TypebotsAPI.getEditorSession(bot.id);
    const authUrl =
      data.open_url ||
      (data.session_token && base
        ? `${base}/chatwoot-auth?token=${encodeURIComponent(
            data.session_token
          )}&redirect=${encodeURIComponent(`/typebots/${bot.id}/edit`)}`
        : null);
    const targetUrl =
      authUrl || (base ? `${base}/typebots/${bot.id}/edit` : null);
    if (targetUrl) {
      const opened = window.open(targetUrl, '_blank', 'noopener,noreferrer');
      if (!opened) {
        useAlert(t('BOTS.POPUP_BLOCKED'));
      }
      return;
    }
  } catch (e) {
    const apiErr = e?.response?.data?.error;
    if (apiErr) {
      useAlert(apiErr);
    }
  }
  if (base) {
    const opened = window.open(
      `${base}/typebots/${bot.id}/edit`,
      '_blank',
      'noopener,noreferrer'
    );
    if (!opened) {
      useAlert(t('BOTS.POPUP_BLOCKED'));
    }
  } else {
    useAlert(t('BOTS.BUILDER_URL_MISSING'));
  }
}

async function createBot() {
  if (!newBotName.value.trim()) return;
  isCreating.value = true;
  try {
    const { data } = await TypebotsAPI.create(newBotName.value.trim());
    if (!data.typebot?.id) {
      useAlert(data.error || t('BOTS.CREATE_ERROR'));
      return;
    }
    useAlert(t('BOTS.CREATE_SUCCESS'));
    const botId = data.typebot.id;
    newBotName.value = '';
    currentView.value = 'list';
    await fetchBots();
    await editBot({ id: botId });
  } catch (e) {
    const msg = e?.response?.data?.error;
    useAlert(msg || t('BOTS.CREATE_ERROR'));
  } finally {
    isCreating.value = false;
  }
}

async function createWebhookBot() {
  if (!webhookName.value.trim() || !webhookUrl.value.trim()) return;
  isCreating.value = true;
  try {
    await store.dispatch('agentBots/create', {
      name: webhookName.value.trim(),
      outgoing_url: webhookUrl.value.trim(),
    });
    useAlert(t('BOTS.CREATE_SUCCESS'));
    webhookName.value = '';
    webhookUrl.value = '';
    currentView.value = 'list';
    await fetchBots();
  } catch {
    useAlert(t('BOTS.CREATE_ERROR'));
  } finally {
    isCreating.value = false;
  }
}

async function publishBot(bot) {
  try {
    await TypebotsAPI.publish(bot.id);
    useAlert(t('BOTS.PUBLISH_SUCCESS'));
    await fetchBots();
  } catch {
    useAlert(t('BOTS.PUBLISH_ERROR'));
  }
}

async function deleteBot(bot) {
  if (!window.confirm(t('BOTS.DELETE_CONFIRM'))) return;
  try {
    await TypebotsAPI.destroy(bot.id);
    useAlert(t('BOTS.DELETE_SUCCESS'));
    await fetchBots();
  } catch {
    useAlert(t('BOTS.DELETE_ERROR'));
  }
}

function openAssignDialog(bot) {
  assignBotId.value = bot.id;
  selectedInboxId.value = '';
  assignDialogRef.value?.open();
}

async function assignBot() {
  if (!selectedInboxId.value || !assignBotId.value) return;
  try {
    await TypebotsAPI.assign(assignBotId.value, selectedInboxId.value);
    useAlert(t('BOTS.ASSIGN_SUCCESS'));
    assignDialogRef.value?.close();
    await fetchBots();
  } catch {
    useAlert(t('BOTS.ASSIGN_ERROR'));
  }
}

function getBotStatus(bot) {
  return bot.publishedTypebotId ? 'published' : 'draft';
}

onMounted(() => {
  fetchBots();
  store.dispatch('inboxes/get');
});
</script>

<template>
  <SettingsLayout :is-loading="isLoading">
    <template #header>
      <BaseSettingsHeader
        :title="t('BOTS.TITLE')"
        :description="t('BOTS.DESCRIPTION')"
        feature-name="bots"
      />
    </template>
    <template #body>
      <!-- Workflow type selector -->
      <div v-if="currentView === 'selector'" class="flex flex-col gap-6">
        <button
          class="text-sm text-n-slate-11 hover:text-n-slate-12 self-start flex items-center gap-1"
          @click="backToList"
        >
          <span class="i-lucide-arrow-left size-4" />
          {{ t('BOTS.WEBHOOK.BACK') }}
        </button>
        <h3 class="text-base font-medium text-n-slate-12">
          {{ t('BOTS.SELECTOR.TITLE') }}
        </h3>
        <div class="grid grid-cols-1 xs:grid-cols-2 gap-6 max-w-3xl">
          <ChannelSelector
            :title="t('BOTS.SELECTOR.VISUAL_BOT')"
            :description="t('BOTS.SELECTOR.VISUAL_BOT_DESC')"
            icon="i-lucide-workflow"
            @click="selectVisualBot"
          />
          <ChannelSelector
            :title="t('BOTS.SELECTOR.WEBHOOK_BOT')"
            :description="t('BOTS.SELECTOR.WEBHOOK_BOT_DESC')"
            icon="i-lucide-webhook"
            @click="selectWebhookBot"
          />
        </div>
      </div>

      <!-- Visual workflow creation -->
      <div
        v-else-if="currentView === 'create-visual'"
        class="flex flex-col gap-6"
      >
        <button
          class="text-sm text-n-slate-11 hover:text-n-slate-12 self-start flex items-center gap-1"
          @click="showSelector"
        >
          <span class="i-lucide-arrow-left size-4" />
          {{ t('BOTS.WEBHOOK.BACK') }}
        </button>
        <div
          class="flex flex-col gap-3 rounded-xl border border-n-weak bg-n-solid-2 p-4 max-w-lg"
        >
          <h3 class="text-sm font-medium text-n-slate-12">
            {{ t('BOTS.CREATE') }}
          </h3>
          <input
            v-model="newBotName"
            type="text"
            class="rounded-lg border border-n-weak bg-n-alpha-black2 px-3 py-2 text-sm text-n-slate-12 placeholder:text-n-slate-10 focus:border-transparent focus:outline-none focus:ring-2 focus:ring-woot-500"
            :placeholder="t('BOTS.CREATE_PLACEHOLDER')"
            @keyup.enter="createBot"
          />
          <Button
            :is-loading="isCreating"
            :disabled="!newBotName.trim()"
            icon="i-lucide-plus"
            :label="t('BOTS.CREATE')"
            @click="createBot"
          />
        </div>
      </div>

      <!-- Webhook workflow creation -->
      <div
        v-else-if="currentView === 'create-webhook'"
        class="flex flex-col gap-6"
      >
        <button
          class="text-sm text-n-slate-11 hover:text-n-slate-12 self-start flex items-center gap-1"
          @click="showSelector"
        >
          <span class="i-lucide-arrow-left size-4" />
          {{ t('BOTS.WEBHOOK.BACK') }}
        </button>
        <div
          class="flex flex-col gap-4 rounded-xl border border-n-weak bg-n-solid-2 p-4 max-w-lg"
        >
          <h3 class="text-sm font-medium text-n-slate-12">
            {{ t('BOTS.WEBHOOK.TITLE') }}
          </h3>
          <div class="flex flex-col gap-1">
            <label class="text-xs font-medium text-n-slate-11">
              {{ t('BOTS.WEBHOOK.NAME_LABEL') }}
            </label>
            <input
              v-model="webhookName"
              type="text"
              class="rounded-lg border border-n-weak bg-n-alpha-black2 px-3 py-2 text-sm text-n-slate-12 placeholder:text-n-slate-10 focus:border-transparent focus:outline-none focus:ring-2 focus:ring-woot-500"
              :placeholder="t('BOTS.WEBHOOK.NAME_PLACEHOLDER')"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-xs font-medium text-n-slate-11">
              {{ t('BOTS.WEBHOOK.URL_LABEL') }}
            </label>
            <input
              v-model="webhookUrl"
              type="url"
              class="rounded-lg border border-n-weak bg-n-alpha-black2 px-3 py-2 text-sm text-n-slate-12 placeholder:text-n-slate-10 focus:border-transparent focus:outline-none focus:ring-2 focus:ring-woot-500"
              :placeholder="t('BOTS.WEBHOOK.URL_PLACEHOLDER')"
            />
          </div>
          <Button
            :is-loading="isCreating"
            :disabled="!webhookName.trim() || !webhookUrl.trim()"
            icon="i-lucide-plus"
            :label="t('BOTS.WEBHOOK.CREATE')"
            @click="createWebhookBot"
          />
        </div>
      </div>

      <!-- Main list view -->
      <div v-else class="flex flex-col gap-6">
        <!-- Config error -->
        <div
          v-if="configError"
          class="flex flex-col items-center justify-center gap-4 py-16 text-n-slate-11"
        >
          <span class="i-lucide-workflow size-12 text-n-slate-10" />
          <p class="text-sm">{{ t('BOTS.NOT_CONFIGURED') }}</p>
          <p class="max-w-md text-center text-xs text-n-slate-10">
            {{ t('BOTS.NOT_CONFIGURED_HELP') }}
          </p>
        </div>

        <template v-else>
          <div class="flex justify-end">
            <Button
              icon="i-lucide-plus"
              :label="t('BOTS.CREATE')"
              @click="showSelector"
            />
          </div>

          <!-- Workflow cards — same grid as inbox channel connectors -->
          <div
            v-if="typebots.length"
            class="grid max-w-3xl grid-cols-1 xs:grid-cols-2 gap-6 sm:grid-cols-3"
          >
            <div
              v-for="bot in typebots"
              :key="bot.id"
              class="relative bg-n-solid-1 gap-4 rounded-2xl flex flex-col justify-between -m-px py-6 px-5 border border-solid border-n-weak transition-all duration-200 hover:shadow-md"
              style="--typebot-orange: #ff5924"
              @mouseenter="$event.currentTarget.style.borderColor = '#ad4d31'"
              @mouseleave="$event.currentTarget.style.borderColor = ''"
            >
              <div class="flex flex-col gap-5">
                <div class="flex items-start justify-between">
                  <div
                    class="flex size-10 items-center justify-center rounded-full bg-n-alpha-2"
                  >
                    <span class="i-lucide-workflow size-5 text-n-slate-10" />
                  </div>
                  <span
                    class="inline-flex items-center rounded-full px-2.5 py-0.5 text-[11px] font-medium bg-n-alpha-2 text-n-slate-11"
                    :style="
                      getBotStatus(bot) === 'published'
                        ? 'border: 1px solid #ff5924'
                        : ''
                    "
                  >
                    {{
                      getBotStatus(bot) === 'published'
                        ? t('BOTS.STATUS.PUBLISHED')
                        : t('BOTS.STATUS.DRAFT')
                    }}
                  </span>
                </div>
                <div class="flex flex-col items-start gap-1.5">
                  <h3
                    class="text-n-slate-12 text-sm text-start font-medium capitalize truncate w-full"
                  >
                    {{ bot.name }}
                  </h3>
                  <p class="text-n-slate-11 text-start text-sm">
                    {{
                      getBotStatus(bot) === 'published'
                        ? t('BOTS.CARD.PUBLISHED_DESC')
                        : t('BOTS.CARD.DRAFT_DESC')
                    }}
                  </p>
                </div>
              </div>
              <div class="flex flex-wrap items-center gap-1.5 pt-3 border-t border-n-weak">
                <button
                  class="flex-1 inline-flex items-center justify-center gap-1.5 rounded-lg px-2.5 py-1 text-xs font-medium text-white transition-colors"
                  style="background-color: #ff5924"
                  @mouseenter="$event.target.style.backgroundColor = '#e64d1a'"
                  @mouseleave="$event.target.style.backgroundColor = '#ff5924'"
                  @click="editBot(bot)"
                >
                  <span class="i-lucide-pencil size-3.5" />
                  {{ t('BOTS.EDIT') }}
                </button>
                <Button
                  v-if="getBotStatus(bot) === 'draft'"
                  icon="i-lucide-upload"
                  :label="t('BOTS.PUBLISH')"
                  size="xs"
                  slate
                  faded
                  class="flex-1"
                  @click="publishBot(bot)"
                />
                <Button
                  v-if="getBotStatus(bot) === 'published'"
                  icon="i-lucide-inbox"
                  :label="t('BOTS.ASSIGN')"
                  size="xs"
                  slate
                  faded
                  class="flex-1"
                  @click="openAssignDialog(bot)"
                />
                <Button
                  icon="i-lucide-trash-2"
                  size="xs"
                  ruby
                  ghost
                  @click="deleteBot(bot)"
                />
              </div>
            </div>
          </div>

          <!-- Empty state -->
          <div
            v-if="!typebots.length && !isLoading && !configError"
            class="flex flex-col items-center justify-center gap-3 py-12 text-n-slate-11"
          >
            <span class="i-lucide-workflow size-10 text-n-slate-10" />
            <p class="text-sm">{{ t('BOTS.EMPTY') }}</p>
          </div>
        </template>
      </div>

      <!-- Assign dialog -->
      <Dialog
        ref="assignDialogRef"
        :title="t('BOTS.ASSIGN')"
        :confirm-button-label="t('BOTS.ASSIGN')"
        @confirm="assignBot"
      >
        <div class="flex flex-col gap-3 py-2">
          <label class="text-xs font-medium text-n-slate-11">
            {{ t('BOTS.SELECT_INBOX') }}
          </label>
          <select
            v-model="selectedInboxId"
            class="rounded-lg border border-n-weak bg-n-alpha-black2 px-3 py-2 text-sm text-n-slate-12 focus:border-transparent focus:outline-none focus:ring-2 focus:ring-woot-500"
          >
            <option value="" disabled>
              {{ t('BOTS.SELECT_INBOX') }}
            </option>
            <option v-for="inbox in inboxes" :key="inbox.id" :value="inbox.id">
              {{ inbox.name }}
            </option>
          </select>
        </div>
      </Dialog>
    </template>
  </SettingsLayout>
</template>
