<script setup>
import { ref, computed, onMounted, defineAsyncComponent, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import TypebotsAPI from 'dashboard/api/typebots';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const BaseSettingsHeader = defineAsyncComponent(
  () => import('../components/BaseSettingsHeader.vue')
);
const SettingsLayout = defineAsyncComponent(
  () => import('../SettingsLayout.vue')
);

const { t } = useI18n();
const store = useStore();

const typebots = ref([]);
const isLoading = ref(false);
const isCreating = ref(false);
const configError = ref(false);

const createDialogRef = ref(null);
const createInputRef = ref(null);
const newBotName = ref('');

const assignDialogRef = ref(null);
const assignBotId = ref(null);
const selectedInboxId = ref('');

const deleteDialogRef = ref(null);
const botPendingDelete = ref(null);
const isDeleting = ref(false);

const inboxes = computed(() => store.getters['inboxes/getInboxes'] || []);

const builderBaseUrl = () =>
  (window.chatwootConfig?.typebotBuilderUrl || '').replace(/\/$/, '');

const getBotStatus = bot => (bot.publishedTypebotId ? 'published' : 'draft');

async function fetchBots() {
  isLoading.value = true;
  try {
    const { data } = await TypebotsAPI.getAll();
    typebots.value = data.typebots || [];
    if (data.error) useAlert(data.error);
  } catch (e) {
    if (e?.response?.status === 503) configError.value = true;
    const msg = e?.response?.data?.error;
    if (msg) useAlert(msg);
  } finally {
    isLoading.value = false;
  }
}

function openCreateDialog() {
  newBotName.value = '';
  createDialogRef.value?.open();
  nextTick(() => createInputRef.value?.focus());
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
      if (!opened) useAlert(t('BOTS.POPUP_BLOCKED'));
      return;
    }
  } catch (e) {
    const apiErr = e?.response?.data?.error;
    if (apiErr) useAlert(apiErr);
  }
  if (!base) {
    useAlert(t('BOTS.BUILDER_URL_MISSING'));
    return;
  }
  const opened = window.open(
    `${base}/typebots/${bot.id}/edit`,
    '_blank',
    'noopener,noreferrer'
  );
  if (!opened) useAlert(t('BOTS.POPUP_BLOCKED'));
}

async function createBot() {
  const name = newBotName.value.trim();
  if (!name || isCreating.value) return;
  isCreating.value = true;
  try {
    const { data } = await TypebotsAPI.create(name);
    if (!data.typebot?.id) {
      useAlert(data.error || t('BOTS.CREATE_ERROR'));
      return;
    }
    useAlert(t('BOTS.CREATE_SUCCESS'));
    createDialogRef.value?.close();
    await fetchBots();
    await editBot({ id: data.typebot.id });
  } catch (e) {
    useAlert(e?.response?.data?.error || t('BOTS.CREATE_ERROR'));
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

function confirmDelete(bot) {
  botPendingDelete.value = bot;
  deleteDialogRef.value?.open();
}

async function deleteBot() {
  const bot = botPendingDelete.value;
  if (!bot || isDeleting.value) return;
  isDeleting.value = true;
  try {
    await TypebotsAPI.destroy(bot.id);
    useAlert(t('BOTS.DELETE_SUCCESS'));
    deleteDialogRef.value?.close();
    botPendingDelete.value = null;
    await fetchBots();
  } catch {
    useAlert(t('BOTS.DELETE_ERROR'));
  } finally {
    isDeleting.value = false;
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
      >
        <template #actions>
          <Button
            v-if="!configError"
            icon="i-lucide-plus"
            :label="t('BOTS.CREATE')"
            size="sm"
            @click="openCreateDialog"
          />
        </template>
      </BaseSettingsHeader>
    </template>
    <template #body>
      <div
        v-if="configError"
        class="flex flex-col items-center justify-center gap-3 py-16 px-6 text-center"
      >
        <div
          class="size-12 rounded-full flex items-center justify-center bg-n-alpha-2 text-n-slate-11"
        >
          <span class="i-lucide-workflow size-5" aria-hidden="true" />
        </div>
        <h3 class="text-sm font-medium text-n-slate-12 text-balance">
          {{ t('BOTS.NOT_CONFIGURED') }}
        </h3>
        <p class="max-w-sm text-xs text-n-slate-11 text-pretty">
          {{ t('BOTS.NOT_CONFIGURED_HELP') }}
        </p>
      </div>

      <div
        v-else-if="!typebots.length && !isLoading"
        class="flex flex-col items-center justify-center gap-4 py-16 px-6 text-center"
      >
        <div
          class="size-12 rounded-full flex items-center justify-center bg-n-alpha-2 text-n-slate-11"
        >
          <span class="i-lucide-workflow size-5" aria-hidden="true" />
        </div>
        <div class="space-y-1.5 max-w-sm">
          <h3 class="text-base font-medium text-n-slate-12 text-balance">
            {{ t('BOTS.EMPTY_TITLE') }}
          </h3>
          <p class="text-sm text-n-slate-11 text-pretty">
            {{ t('BOTS.EMPTY_SUBTITLE') }}
          </p>
        </div>
        <Button
          icon="i-lucide-plus"
          :label="t('BOTS.CREATE_CTA')"
          size="sm"
          @click="openCreateDialog"
        />
      </div>

      <div
        v-else
        class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4 max-w-5xl"
      >
        <div
          v-for="bot in typebots"
          :key="bot.id"
          class="group relative flex flex-col gap-4 rounded-2xl border border-n-weak bg-n-solid-1 p-5 transition-colors duration-150 ease-out hover:bg-n-alpha-1"
        >
          <div class="flex items-start justify-between gap-3">
            <div
              class="size-10 rounded-full flex items-center justify-center bg-n-alpha-2 text-n-slate-11"
            >
              <span class="i-lucide-workflow size-5" aria-hidden="true" />
            </div>
            <span
              class="inline-flex items-center gap-1.5 rounded-full px-2 py-0.5 text-[11px] font-medium tabular-nums"
              :class="
                getBotStatus(bot) === 'published'
                  ? 'bg-emerald-500/10 text-emerald-600 dark:text-emerald-400'
                  : 'bg-n-alpha-2 text-n-slate-11'
              "
            >
              <span
                class="size-1.5 rounded-full"
                :class="
                  getBotStatus(bot) === 'published'
                    ? 'bg-emerald-500'
                    : 'bg-n-slate-9'
                "
                aria-hidden="true"
              />
              {{
                getBotStatus(bot) === 'published'
                  ? t('BOTS.STATUS.PUBLISHED')
                  : t('BOTS.STATUS.DRAFT')
              }}
            </span>
          </div>
          <div class="flex-1 min-w-0 space-y-1">
            <h3
              class="text-sm font-medium text-n-slate-12 truncate text-balance"
            >
              {{ bot.name }}
            </h3>
            <p class="text-xs text-n-slate-11 text-pretty line-clamp-2">
              {{
                getBotStatus(bot) === 'published'
                  ? t('BOTS.CARD.PUBLISHED_DESC')
                  : t('BOTS.CARD.DRAFT_DESC')
              }}
            </p>
          </div>
          <div class="flex items-center gap-1.5 pt-3 border-t border-n-weak">
            <button
              type="button"
              :aria-label="t('BOTS.EDIT_ARIA')"
              class="flex-1 inline-flex items-center justify-center gap-1.5 h-8 rounded-lg text-xs font-medium text-white bg-[#ff5924] hover:bg-[#e64d1a] cursor-pointer transition-colors duration-150 ease-out"
              @click="editBot(bot)"
            >
              <span class="i-lucide-pencil size-3.5" aria-hidden="true" />
              {{ t('BOTS.EDIT') }}
            </button>
            <button
              v-if="getBotStatus(bot) === 'draft'"
              type="button"
              :aria-label="t('BOTS.PUBLISH_ARIA')"
              class="inline-flex items-center justify-center gap-1.5 h-8 px-3 rounded-lg text-xs font-medium text-n-slate-12 bg-n-alpha-2 hover:bg-n-alpha-3 cursor-pointer transition-colors duration-150 ease-out"
              @click="publishBot(bot)"
            >
              <span class="i-lucide-upload size-3.5" aria-hidden="true" />
              {{ t('BOTS.PUBLISH') }}
            </button>
            <button
              v-else
              type="button"
              :aria-label="t('BOTS.ASSIGN_ARIA')"
              class="inline-flex items-center justify-center gap-1.5 h-8 px-3 rounded-lg text-xs font-medium text-n-slate-12 bg-n-alpha-2 hover:bg-n-alpha-3 cursor-pointer transition-colors duration-150 ease-out"
              @click="openAssignDialog(bot)"
            >
              <span class="i-lucide-inbox size-3.5" aria-hidden="true" />
              {{ t('BOTS.ASSIGN') }}
            </button>
            <button
              type="button"
              :aria-label="t('BOTS.DELETE_ARIA')"
              class="inline-flex items-center justify-center size-8 rounded-lg text-n-slate-11 hover:text-ruby-600 hover:bg-ruby-500/10 cursor-pointer transition-colors duration-150 ease-out"
              @click="confirmDelete(bot)"
            >
              <span class="i-lucide-trash-2 size-3.5" aria-hidden="true" />
            </button>
          </div>
        </div>
      </div>

      <Dialog
        ref="createDialogRef"
        :title="t('BOTS.CREATE_DIALOG_TITLE')"
        :description="t('BOTS.CREATE_DIALOG_DESCRIPTION')"
        :confirm-button-label="t('BOTS.CREATE_CTA')"
        :is-loading="isCreating"
        :disable-confirm-button="!newBotName.trim()"
        width="md"
        @confirm="createBot"
      >
        <div class="flex flex-col gap-2 pt-1">
          <label for="new-bot-name" class="text-xs font-medium text-n-slate-11">
            {{ t('BOTS.CREATE_PLACEHOLDER') }}
          </label>
          <input
            id="new-bot-name"
            ref="createInputRef"
            v-model="newBotName"
            type="text"
            :placeholder="t('BOTS.CREATE_PLACEHOLDER')"
            class="h-9 rounded-lg border border-n-weak bg-n-alpha-black2 px-3 text-sm text-n-slate-12 placeholder:text-n-slate-10 focus:border-transparent focus:outline-none focus:ring-2 focus:ring-[#ff5924] transition-colors duration-150 ease-out"
            @keyup.enter="createBot"
          />
        </div>
      </Dialog>

      <Dialog
        ref="deleteDialogRef"
        type="alert"
        :title="t('BOTS.DELETE_TITLE')"
        :description="t('BOTS.DELETE_CONFIRM')"
        :confirm-button-label="t('BOTS.DELETE_CONFIRM_BUTTON')"
        :is-loading="isDeleting"
        @confirm="deleteBot"
      />

      <Dialog
        ref="assignDialogRef"
        :title="t('BOTS.ASSIGN')"
        :confirm-button-label="t('BOTS.ASSIGN')"
        :disable-confirm-button="!selectedInboxId"
        width="md"
        @confirm="assignBot"
      >
        <div class="flex flex-col gap-2 pt-1">
          <label for="assign-inbox" class="text-xs font-medium text-n-slate-11">
            {{ t('BOTS.SELECT_INBOX') }}
          </label>
          <select
            id="assign-inbox"
            v-model="selectedInboxId"
            class="h-9 rounded-lg border border-n-weak bg-n-alpha-black2 px-3 text-sm text-n-slate-12 focus:border-transparent focus:outline-none focus:ring-2 focus:ring-[#ff5924] transition-colors duration-150 ease-out"
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
