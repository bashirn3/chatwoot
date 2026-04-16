<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import WhatsAppBridgeAPI from 'dashboard/api/whatsappBridge';
import PhoneNumberInput from 'dashboard/components-next/phonenumberinput/PhoneNumberInput.vue';
import SettingsSection from 'dashboard/components/SettingsSection.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import { defineAsyncComponent } from 'vue';

const props = defineProps({
  embedded: { type: Boolean, default: false },
});

const BaseSettingsHeader = defineAsyncComponent(
  () => import('../components/BaseSettingsHeader.vue')
);
const SettingsLayout = defineAsyncComponent(
  () => import('../SettingsLayout.vue')
);
const InstanceSettingsDialog = defineAsyncComponent(
  () => import('./InstanceSettingsDialog.vue')
);

const { t } = useI18n();

const instances = ref([]);
const orphanedInboxes = ref([]);
const qrCodeData = ref(null);
const pairingCode = ref(null);
const activeInstance = ref(null);
const connectionStatus = ref(null);
const isLoading = ref(false);
const isCreating = ref(false);
const isConnecting = ref(false);
const newInstanceName = ref('');
const connectMethod = ref('qr');
const connectPhone = ref('');
const pollingTimer = ref(null);
const configError = ref(false);
const settingsDialogRef = ref(null);
const settingsInstanceName = ref('');

const isConnected = computed(() => connectionStatus.value === 'open');

function openSettings(instanceName) {
  settingsInstanceName.value = instanceName;
  settingsDialogRef.value?.open();
}

function stopPolling() {
  if (pollingTimer.value) {
    clearInterval(pollingTimer.value);
    pollingTimer.value = null;
  }
}

async function fetchInstances() {
  isLoading.value = true;
  try {
    const { data } = await WhatsAppBridgeAPI.getInstances();
    if (data.error) {
      if (data.error.includes('not configured')) {
        configError.value = true;
      }
      return;
    }
    instances.value = data.instances || [];
    orphanedInboxes.value = data.orphaned_inboxes || [];
  } catch {
    configError.value = true;
  } finally {
    isLoading.value = false;
  }
}

async function pollQrAndStatus(instanceName) {
  try {
    const { data } = await WhatsAppBridgeAPI.qrCode(instanceName);
    if (data.status === 'connected' || data.status === 'open') {
      connectionStatus.value = 'open';
      stopPolling();
      qrCodeData.value = null;
      pairingCode.value = null;
      useAlert(t('WHATSAPP_CONNECTION.CONNECTED'));
      await fetchInstances();
      return;
    }
    if (data.qrCode) {
      qrCodeData.value = data.qrCode;
    }
    if (data.pairingCode) {
      pairingCode.value = data.pairingCode;
    }
  } catch {
    // Silently retry
  }
}

function startPolling(instanceName) {
  stopPolling();
  pollingTimer.value = setInterval(() => pollQrAndStatus(instanceName), 4000);
}

async function createInstance() {
  if (!newInstanceName.value.trim()) return;
  isCreating.value = true;
  try {
    const { data } = await WhatsAppBridgeAPI.createInstance(
      newInstanceName.value.trim()
    );
    if (data.error) {
      useAlert(data.error);
      return;
    }

    const inst = data.instance || {};
    const instanceId =
      inst.id || inst.instance?.id || inst.instance?.instanceName || inst.name;
    if (instanceId) {
      activeInstance.value = instanceId;
      connectionStatus.value = null;
      qrCodeData.value = null;
      pairingCode.value = null;
    }

    useAlert(t('WHATSAPP_CONNECTION.CREATE_SUCCESS'));
    newInstanceName.value = '';
    await fetchInstances();
  } catch {
    useAlert(t('WHATSAPP_CONNECTION.CREATE_ERROR'));
  } finally {
    isCreating.value = false;
  }
}

async function connectInstance(instanceName, pairingPhone = null) {
  isConnecting.value = true;
  activeInstance.value = instanceName;
  qrCodeData.value = null;
  pairingCode.value = null;
  connectionStatus.value = null;

  try {
    const phone = pairingPhone?.replace(/\D/g, '') || null;
    const { data } = await WhatsAppBridgeAPI.connect(instanceName, phone);

    if (data.pairingCode) {
      pairingCode.value = data.pairingCode;
    }

    const qrResp = await WhatsAppBridgeAPI.qrCode(instanceName);
    if (qrResp.data.qrCode) {
      qrCodeData.value = qrResp.data.qrCode;
    }

    if (qrResp.data.status === 'connected' || qrResp.data.status === 'open') {
      connectionStatus.value = 'open';
      useAlert(t('WHATSAPP_CONNECTION.ALREADY_CONNECTED'));
    } else {
      startPolling(instanceName);
    }
  } catch {
    useAlert(t('WHATSAPP_CONNECTION.CONNECT_ERROR'));
  } finally {
    isConnecting.value = false;
    connectPhone.value = '';
  }
}

async function disconnectInstance(instanceName) {
  try {
    await WhatsAppBridgeAPI.disconnect(instanceName);
    useAlert(t('WHATSAPP_CONNECTION.LOGOUT_SUCCESS'));
    connectionStatus.value = null;
    if (activeInstance.value === instanceName) {
      activeInstance.value = null;
      qrCodeData.value = null;
      pairingCode.value = null;
      stopPolling();
    }
    await fetchInstances();
  } catch {
    useAlert(t('WHATSAPP_CONNECTION.LOGOUT_ERROR'));
  }
}

async function removeInstance(instanceName) {
  try {
    await WhatsAppBridgeAPI.deleteInstance(instanceName);
    useAlert(t('WHATSAPP_CONNECTION.DELETE_SUCCESS'));
    if (activeInstance.value === instanceName) {
      activeInstance.value = null;
      qrCodeData.value = null;
      pairingCode.value = null;
      connectionStatus.value = null;
      stopPolling();
    }
    await fetchInstances();
  } catch {
    useAlert(t('WHATSAPP_CONNECTION.DELETE_ERROR'));
  }
}

async function removeOrphanedInbox(inboxId) {
  try {
    await WhatsAppBridgeAPI.deleteInbox(inboxId);
    useAlert(t('WHATSAPP_CONNECTION.DELETE_SUCCESS'));
    await fetchInstances();
  } catch {
    useAlert(t('WHATSAPP_CONNECTION.DELETE_ERROR'));
  }
}

async function removeAllOrphaned() {
  try {
    await Promise.all(
      orphanedInboxes.value.map(o => WhatsAppBridgeAPI.deleteInbox(o.inbox_id))
    );
    useAlert(t('WHATSAPP_CONNECTION.ORPHANED.CLEAR_ALL_SUCCESS'));
    await fetchInstances();
  } catch {
    useAlert(t('WHATSAPP_CONNECTION.DELETE_ERROR'));
  }
}

async function relinkInstance(instanceName) {
  try {
    await WhatsAppBridgeAPI.relinkInstance(instanceName);
    useAlert(t('WHATSAPP_CONNECTION.RELINK_SUCCESS'));
    await fetchInstances();
  } catch {
    useAlert(t('WHATSAPP_CONNECTION.RELINK_ERROR'));
  }
}

function getInstanceStatus(inst) {
  return inst.status || inst.state || inst.instance?.state || 'unknown';
}

function getInstanceName(inst) {
  return inst.id || inst.name || inst.instance?.instanceName || 'Unknown';
}

function getInstancePhone(inst) {
  return inst.phone || inst.instance?.phone || '';
}

function displayName(fullId) {
  return fullId.replace(/^acct-\d+-/, '');
}

onMounted(fetchInstances);
onUnmounted(stopPolling);
</script>

<template>
  <SettingsLayout v-if="!embedded" :is-loading="isLoading">
    <template #header>
      <BaseSettingsHeader
        :title="t('WHATSAPP_CONNECTION.TITLE')"
        :description="t('WHATSAPP_CONNECTION.DESCRIPTION')"
        feature-name="whatsapp_connection"
      />
    </template>
    <template #body>
      <!-- Config error -->
      <div
        v-if="configError"
        class="flex flex-col items-center justify-center gap-4 py-16 text-n-slate-11"
      >
        <span class="i-lucide-server-off size-12 text-n-slate-10" />
        <p class="text-sm">
          {{ t('WHATSAPP_CONNECTION.NOT_CONFIGURED') }}
        </p>
        <p class="max-w-md text-center text-xs text-n-slate-10">
          {{ t('WHATSAPP_CONNECTION.NOT_CONFIGURED_HELP') }}
        </p>
      </div>

      <div v-else class="flex flex-col gap-6">
        <!-- Create new instance -->
        <div
          class="flex flex-col gap-3 rounded-xl border border-n-weak bg-n-solid-2 p-4"
        >
          <h3 class="text-sm font-medium text-n-slate-12">
            {{ t('WHATSAPP_CONNECTION.NEW_INSTANCE.TITLE') }}
          </h3>
          <div class="flex gap-2">
            <input
              v-model="newInstanceName"
              type="text"
              class="flex-1 rounded-lg border border-n-weak bg-n-alpha-black2 px-3 py-2 text-sm text-n-slate-12 placeholder:text-n-slate-10 focus:border-transparent focus:outline-none focus:ring-2 focus:ring-woot-500"
              :placeholder="
                t('WHATSAPP_CONNECTION.NEW_INSTANCE.NAME_PLACEHOLDER')
              "
              @keyup.enter="createInstance"
            />
            <button
              class="inline-flex items-center gap-2 rounded-lg bg-woot-500 px-4 py-2 text-sm font-medium text-white transition-colors hover:bg-woot-600 disabled:opacity-50"
              :disabled="isCreating || !newInstanceName.trim()"
              @click="createInstance"
            >
              <span
                v-if="isCreating"
                class="i-lucide-loader-2 size-4 animate-spin"
              />
              <span v-else class="i-lucide-plus size-4" />
              {{ t('WHATSAPP_CONNECTION.NEW_INSTANCE.CREATE') }}
            </button>
          </div>
        </div>

        <!-- QR Code display -->
        <div
          v-if="(qrCodeData || pairingCode) && activeInstance && !isConnected"
          class="flex flex-col items-center gap-4 rounded-xl border border-n-weak bg-n-solid-2 p-6"
        >
          <div class="flex items-center gap-2">
            <span class="i-lucide-scan size-5 text-woot-500" />
            <h3 class="text-sm font-medium text-n-slate-12">
              {{ t('WHATSAPP_CONNECTION.QR.TITLE') }}
            </h3>
          </div>
          <p class="text-center text-xs text-n-slate-11">
            {{ t('WHATSAPP_CONNECTION.QR.INSTRUCTIONS') }}
          </p>

          <!-- QR Image -->
          <div v-if="qrCodeData" class="rounded-xl bg-white p-4">
            <img
              :src="qrCodeData"
              :alt="t('WHATSAPP_CONNECTION.QR.ALT')"
              class="size-64"
            />
          </div>

          <!-- Pairing code -->
          <div
            v-if="pairingCode"
            class="flex flex-col items-center gap-2 rounded-lg bg-n-alpha-black2 px-6 py-3"
          >
            <span class="text-xs text-n-slate-10">
              {{ t('WHATSAPP_CONNECTION.QR.PAIRING_CODE') }}
            </span>
            <span
              class="font-mono text-2xl font-bold tracking-widest text-n-slate-12"
            >
              {{ pairingCode }}
            </span>
          </div>

          <div class="flex items-center gap-2 text-xs text-n-slate-10">
            <span class="i-lucide-loader-2 size-3 animate-spin" />
            {{ t('WHATSAPP_CONNECTION.QR.WAITING') }}
          </div>
        </div>

        <!-- Connected success -->
        <div
          v-if="isConnected && activeInstance"
          class="flex items-center gap-3 rounded-xl border border-green-200 bg-green-50 p-4 dark:border-green-800 dark:bg-green-900/20"
        >
          <span
            class="i-lucide-check-circle size-5 text-green-600 dark:text-green-400"
          />
          <div>
            <p class="text-sm font-medium text-green-800 dark:text-green-200">
              {{ t('WHATSAPP_CONNECTION.CONNECTED') }}
            </p>
            <p class="text-xs text-green-600 dark:text-green-400">
              {{ displayName(activeInstance) }}
            </p>
          </div>
        </div>

        <!-- Instances list -->
        <div v-if="instances.length" class="flex flex-col gap-2">
          <h3 class="text-sm font-medium text-n-slate-12">
            {{ t('WHATSAPP_CONNECTION.INSTANCES.TITLE') }}
          </h3>
          <div
            v-for="inst in instances"
            :key="getInstanceName(inst)"
            class="flex items-center justify-between rounded-xl border border-n-weak bg-n-solid-2 p-4"
          >
            <div class="flex items-center gap-3">
              <div
                class="flex size-10 items-center justify-center rounded-full"
                :class="
                  getInstanceStatus(inst) === 'connected'
                    ? 'bg-green-100 dark:bg-green-900/30'
                    : 'bg-n-alpha-black2'
                "
              >
                <span
                  class="i-lucide-smartphone size-5"
                  :class="
                    getInstanceStatus(inst) === 'connected'
                      ? 'text-green-600 dark:text-green-400'
                      : 'text-n-slate-11'
                  "
                />
              </div>
              <div>
                <p class="text-sm font-medium text-n-slate-12">
                  {{ displayName(getInstanceName(inst)) }}
                </p>
                <div class="flex items-center gap-2">
                  <span
                    class="inline-block size-2 rounded-full"
                    :class="
                      getInstanceStatus(inst) === 'connected'
                        ? 'bg-green-500'
                        : 'bg-n-slate-9'
                    "
                  />
                  <span class="text-xs text-n-slate-10">
                    {{
                      getInstancePhone(inst)
                        ? `${getInstanceStatus(inst)} \u00B7 ${getInstancePhone(inst)}`
                        : getInstanceStatus(inst)
                    }}
                  </span>
                </div>
                <div
                  v-if="inst.has_inbox === false"
                  class="mt-1 flex items-center gap-1 text-xs text-amber-600 dark:text-amber-400"
                >
                  <span class="i-lucide-alert-triangle size-3" />
                  {{ t('WHATSAPP_CONNECTION.INSTANCES.NO_INBOX') }}
                </div>
              </div>
            </div>
            <div class="flex items-center gap-2">
              <button
                v-if="inst.has_inbox === false"
                class="inline-flex items-center gap-1 rounded-lg bg-woot-500 px-3 py-1.5 text-xs font-medium text-white transition-colors hover:bg-woot-600"
                @click="relinkInstance(getInstanceName(inst))"
              >
                <span class="i-lucide-link size-3" />
                {{ t('WHATSAPP_CONNECTION.INSTANCES.RELINK') }}
              </button>
              <template v-if="getInstanceStatus(inst) !== 'connected'">
                <PhoneNumberInput
                  v-model="connectPhone"
                  class="w-52"
                  :placeholder="
                    t('WHATSAPP_CONNECTION.INSTANCES.PAIRING_PHONE_PLACEHOLDER')
                  "
                />
                <button
                  class="inline-flex items-center gap-1 rounded-lg bg-woot-500 px-3 py-1.5 text-xs font-medium text-white transition-colors hover:bg-woot-600"
                  :disabled="isConnecting"
                  @click="
                    connectInstance(getInstanceName(inst), connectPhone || null)
                  "
                >
                  <span
                    :class="
                      connectPhone ? 'i-lucide-smartphone' : 'i-lucide-qr-code'
                    "
                    class="size-3"
                  />
                  {{
                    connectPhone
                      ? t('WHATSAPP_CONNECTION.INSTANCES.CONNECT_PAIRING')
                      : t('WHATSAPP_CONNECTION.INSTANCES.CONNECT_QR')
                  }}
                </button>
              </template>
              <button
                v-if="getInstanceStatus(inst) === 'connected'"
                class="inline-flex items-center gap-1 rounded-lg bg-n-alpha-black2 px-3 py-1.5 text-xs font-medium text-n-slate-12 transition-colors hover:bg-n-alpha-3"
                @click="openSettings(getInstanceName(inst))"
              >
                <span class="i-lucide-settings size-3" />
                {{ t('WHATSAPP_CONNECTION.INSTANCES.SETTINGS') }}
              </button>
              <button
                v-if="getInstanceStatus(inst) === 'connected'"
                class="inline-flex items-center gap-1 rounded-lg bg-n-alpha-black2 px-3 py-1.5 text-xs font-medium text-n-slate-12 transition-colors hover:bg-n-alpha-3"
                @click="disconnectInstance(getInstanceName(inst))"
              >
                <span class="i-lucide-log-out size-3" />
                {{ t('WHATSAPP_CONNECTION.INSTANCES.LOGOUT') }}
              </button>
              <button
                class="inline-flex items-center gap-1 rounded-lg bg-n-alpha-black2 px-3 py-1.5 text-xs font-medium text-ruby-800 transition-colors hover:bg-ruby-100 dark:text-ruby-300 dark:hover:bg-ruby-900/30"
                @click="removeInstance(getInstanceName(inst))"
              >
                <span class="i-lucide-trash-2 size-3" />
                {{ t('WHATSAPP_CONNECTION.INSTANCES.DELETE') }}
              </button>
            </div>
          </div>
        </div>

        <!-- Orphaned inboxes -->
        <div v-if="orphanedInboxes.length" class="flex flex-col gap-2">
          <div class="flex items-center justify-between">
            <h3 class="text-sm font-medium text-n-slate-12">
              {{ t('WHATSAPP_CONNECTION.ORPHANED.TITLE') }}
            </h3>
            <button
              class="inline-flex items-center gap-1 rounded-md px-2 py-1 text-xs font-medium text-red-600 transition-colors hover:bg-red-50 dark:text-red-400 dark:hover:bg-red-900/20"
              @click="removeAllOrphaned"
            >
              <span class="i-lucide-trash-2 size-3" />
              {{ t('WHATSAPP_CONNECTION.ORPHANED.DELETE_ALL') }}
            </button>
          </div>
          <p class="text-xs text-n-slate-10">
            {{ t('WHATSAPP_CONNECTION.ORPHANED.DESCRIPTION') }}
          </p>
          <div
            v-for="orphan in orphanedInboxes"
            :key="orphan.inbox_id"
            class="flex items-center justify-between rounded-xl border border-dashed border-n-weak bg-n-solid-2 p-4"
          >
            <div class="flex items-center gap-3">
              <div
                class="flex size-10 items-center justify-center rounded-full bg-red-50 dark:bg-red-900/20"
              >
                <span
                  class="i-lucide-unplug size-5 text-red-500 dark:text-red-400"
                />
              </div>
              <div>
                <p class="text-sm font-medium text-n-slate-12">
                  {{ orphan.name }}
                </p>
                <span class="text-xs text-n-slate-10">
                  {{ t('WHATSAPP_CONNECTION.ORPHANED.STATUS') }}
                  <template v-if="orphan.conversations_count > 0">
                    &middot;
                    {{
                      t('WHATSAPP_CONNECTION.ORPHANED.CONVERSATIONS', {
                        count: orphan.conversations_count,
                      })
                    }}
                  </template>
                </span>
              </div>
            </div>
            <button
              class="inline-flex items-center gap-1 rounded-lg bg-n-alpha-black2 px-3 py-1.5 text-xs font-medium text-red-700 transition-colors hover:bg-red-100 dark:text-red-300 dark:hover:bg-red-900/30"
              @click="removeOrphanedInbox(orphan.inbox_id)"
            >
              <span class="i-lucide-trash-2 size-3" />
              {{ t('WHATSAPP_CONNECTION.INSTANCES.DELETE') }}
            </button>
          </div>
        </div>

        <!-- Empty state -->
        <div
          v-if="
            !instances.length &&
            !orphanedInboxes.length &&
            !isLoading &&
            !configError
          "
          class="flex flex-col items-center justify-center gap-3 py-12 text-n-slate-11"
        >
          <span class="i-lucide-smartphone size-10 text-n-slate-10" />
          <p class="text-sm">
            {{ t('WHATSAPP_CONNECTION.EMPTY') }}
          </p>
        </div>
      </div>

      <InstanceSettingsDialog
        ref="settingsDialogRef"
        :instance-name="settingsInstanceName"
        @close="settingsInstanceName = ''"
      />
    </template>
  </SettingsLayout>
  <!-- Embedded mode (used as inbox settings tab) -->
  <div v-else class="mx-8">
    <SettingsSection
      :title="t('WHATSAPP_CONNECTION.INSTANCES.TITLE')"
      :sub-title="t('WHATSAPP_CONNECTION.DESCRIPTION')"
    >
      <div v-if="configError" class="flex flex-col gap-2 py-4">
        <p class="text-sm text-n-slate-11">
          {{ t('WHATSAPP_CONNECTION.NOT_CONFIGURED') }}
        </p>
      </div>
      <div
        v-else-if="isLoading"
        class="flex items-center justify-center py-8"
      >
        <span class="i-lucide-loader-2 size-5 animate-spin text-n-slate-10" />
      </div>
      <div v-else class="flex flex-col gap-4">
        <div
          v-for="inst in instances"
          :key="getInstanceName(inst)"
          class="flex items-center justify-between gap-4"
        >
          <div class="flex items-center gap-3 min-w-0">
            <span
              class="inline-block size-2 shrink-0 rounded-full"
              :class="
                getInstanceStatus(inst) === 'connected'
                  ? 'bg-green-500'
                  : 'bg-n-slate-9'
              "
            />
            <div class="min-w-0">
              <p class="text-sm font-medium text-n-slate-12 truncate">
                {{ displayName(getInstanceName(inst)) }}
              </p>
              <p class="text-xs text-n-slate-10">
                {{
                  getInstancePhone(inst)
                    ? `${getInstanceStatus(inst)} · ${getInstancePhone(inst)}`
                    : getInstanceStatus(inst)
                }}
              </p>
            </div>
          </div>
          <div class="flex items-center gap-2 shrink-0">
            <NextButton
              v-if="getInstanceStatus(inst) === 'connected'"
              size="xs"
              faded
              slate
              icon="i-lucide-settings"
              :label="t('WHATSAPP_CONNECTION.INSTANCES.SETTINGS')"
              @click="openSettings(getInstanceName(inst))"
            />
            <NextButton
              v-if="getInstanceStatus(inst) === 'connected'"
              size="xs"
              faded
              slate
              icon="i-lucide-log-out"
              :label="t('WHATSAPP_CONNECTION.INSTANCES.LOGOUT')"
              @click="disconnectInstance(getInstanceName(inst))"
            />
            <template v-if="getInstanceStatus(inst) !== 'connected'">
              <NextButton
                size="xs"
                icon="i-lucide-qr-code"
                :label="t('WHATSAPP_CONNECTION.INSTANCES.CONNECT_QR')"
                :is-loading="isConnecting"
                @click="connectInstance(getInstanceName(inst))"
              />
            </template>
          </div>
        </div>

        <div
          v-if="!instances.length && !configError"
          class="py-4 text-sm text-n-slate-10"
        >
          {{ t('WHATSAPP_CONNECTION.EMPTY') }}
        </div>

        <!-- QR / pairing display -->
        <div
          v-if="(qrCodeData || pairingCode) && activeInstance && !isConnected"
          class="flex flex-col items-center gap-4 rounded-xl border border-n-weak p-6"
        >
          <p class="text-center text-xs text-n-slate-11">
            {{ t('WHATSAPP_CONNECTION.QR.INSTRUCTIONS') }}
          </p>
          <div v-if="qrCodeData" class="rounded-xl bg-white p-4">
            <img
              :src="qrCodeData"
              :alt="t('WHATSAPP_CONNECTION.QR.ALT')"
              class="size-48"
            />
          </div>
          <div
            v-if="pairingCode"
            class="flex flex-col items-center gap-1 rounded-lg bg-n-alpha-black2 px-6 py-3"
          >
            <span class="text-xs text-n-slate-10">
              {{ t('WHATSAPP_CONNECTION.QR.PAIRING_CODE') }}
            </span>
            <span
              class="font-mono text-xl font-bold tracking-widest text-n-slate-12"
            >
              {{ pairingCode }}
            </span>
          </div>
          <div class="flex items-center gap-2 text-xs text-n-slate-10">
            <span class="i-lucide-loader-2 size-3 animate-spin" />
            {{ t('WHATSAPP_CONNECTION.QR.WAITING') }}
          </div>
        </div>

        <!-- Connected success -->
        <div
          v-if="isConnected && activeInstance"
          class="flex items-center gap-3 rounded-xl border border-green-200 p-4 dark:border-green-800 dark:bg-green-900/20"
        >
          <span
            class="i-lucide-check-circle size-5 text-green-600 dark:text-green-400"
          />
          <p class="text-sm font-medium text-green-800 dark:text-green-200">
            {{ t('WHATSAPP_CONNECTION.CONNECTED') }}
            — {{ displayName(activeInstance) }}
          </p>
        </div>
      </div>
    </SettingsSection>

    <InstanceSettingsDialog
      ref="settingsDialogRef"
      :instance-name="settingsInstanceName"
      @close="settingsInstanceName = ''"
    />
  </div>
</template>
