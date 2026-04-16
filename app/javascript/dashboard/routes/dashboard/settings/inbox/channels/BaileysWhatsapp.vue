<script setup>
import { ref, computed, onUnmounted } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import WhatsAppBridgeAPI from 'dashboard/api/whatsappBridge';
import NextButton from 'dashboard/components-next/button/Button.vue';
import PhoneNumberInput from 'dashboard/components-next/phonenumberinput/PhoneNumberInput.vue';

const router = useRouter();
const { t } = useI18n();

const inboxName = ref('');
const connectionMethod = ref('qr');
const phoneNumber = ref('');
const isCreating = ref(false);
const isConnecting = ref(false);
const qrCodeData = ref(null);
const pairingCode = ref(null);
const connectionStatus = ref(null);
const createdInstanceName = ref(null);
const createdInboxId = ref(null);
const pollingTimer = ref(null);
const bridgeError = ref(null);

const usePairingCode = computed(() => connectionMethod.value === 'pairing');

const isConnected = computed(() => connectionStatus.value === 'open');

function stopPolling() {
  if (pollingTimer.value) {
    clearInterval(pollingTimer.value);
    pollingTimer.value = null;
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
      useAlert(t('INBOX_MGMT.ADD.WHATSAPP.BAILEYS.CONNECTED'));
      return;
    }
    if (data.qrCode) qrCodeData.value = data.qrCode;
    if (data.pairingCode) pairingCode.value = data.pairingCode;
  } catch {
    // Silently retry
  }
}

function startPolling(instanceName) {
  stopPolling();
  pollingTimer.value = setInterval(() => pollQrAndStatus(instanceName), 4000);
}

async function createAndConnect() {
  if (!inboxName.value.trim()) return;
  isCreating.value = true;
  bridgeError.value = null;

  try {
    const { data } = await WhatsAppBridgeAPI.createInstance(
      inboxName.value.trim()
    );

    if (data.error || data.instance?.error) {
      bridgeError.value = data.error || data.instance?.error;
      return;
    }

    const inst = data.instance || {};
    const instanceId =
      inst.id || inst.instance?.id || inst.instance?.instanceName || inst.name;

    if (!instanceId) {
      bridgeError.value = t('INBOX_MGMT.ADD.WHATSAPP.BAILEYS.ERROR');
      return;
    }

    createdInstanceName.value = instanceId;
    createdInboxId.value = data.inbox_id;

    isConnecting.value = true;
    const pairingPhone = usePairingCode.value
      ? phoneNumber.value.replace(/\D/g, '')
      : null;
    const connectResp = await WhatsAppBridgeAPI.connect(
      instanceId,
      pairingPhone
    );
    if (connectResp.data.pairingCode) {
      pairingCode.value = connectResp.data.pairingCode;
    }

    const qrResp = await WhatsAppBridgeAPI.qrCode(instanceId);
    if (qrResp.data.qrCode) qrCodeData.value = qrResp.data.qrCode;
    if (qrResp.data.status === 'connected' || qrResp.data.status === 'open') {
      connectionStatus.value = 'open';
    } else {
      startPolling(instanceId);
    }
  } catch (error) {
    bridgeError.value =
      error?.response?.data?.error ||
      error.message ||
      t('INBOX_MGMT.ADD.WHATSAPP.BAILEYS.ERROR');
  } finally {
    isCreating.value = false;
    isConnecting.value = false;
  }
}

function proceedToAgents() {
  if (!createdInboxId.value) return;
  router.replace({
    name: 'settings_inboxes_add_agents',
    params: { page: 'new', inbox_id: createdInboxId.value },
  });
}

onUnmounted(stopPolling);
</script>

<template>
  <div class="flex flex-col gap-6">
    <!-- Step 1: Name + Create -->
    <div v-if="!createdInstanceName">
      <div class="mb-4">
        <h3 class="text-sm font-medium text-n-slate-12">
          {{ t('INBOX_MGMT.ADD.WHATSAPP.BAILEYS.TITLE') }}
        </h3>
        <p class="mt-1 text-sm text-n-slate-11">
          {{ t('INBOX_MGMT.ADD.WHATSAPP.BAILEYS.DESCRIPTION') }}
        </p>
      </div>

      <div
        v-if="bridgeError"
        class="mb-4 rounded-lg bg-red-50 dark:bg-red-900/20 p-3"
      >
        <p class="text-sm text-red-800 dark:text-red-200">
          {{ bridgeError }}
        </p>
      </div>

      <form class="flex flex-col gap-4" @submit.prevent="createAndConnect">
        <label>
          {{ t('INBOX_MGMT.ADD.WHATSAPP.BAILEYS.INBOX_NAME.LABEL') }}
          <input
            v-model="inboxName"
            type="text"
            :placeholder="
              t('INBOX_MGMT.ADD.WHATSAPP.BAILEYS.INBOX_NAME.PLACEHOLDER')
            "
          />
        </label>

        <div class="flex flex-col gap-1">
          <span class="text-xs font-medium text-n-slate-11">
            {{ t('INBOX_MGMT.ADD.WHATSAPP.BAILEYS.CONNECTION_METHOD') }}
          </span>
          <div class="flex gap-2">
            <button
              type="button"
              class="flex-1 rounded-lg border px-3 py-2 text-xs font-medium transition-colors"
              :class="
                connectionMethod === 'qr'
                  ? 'border-woot-500 bg-woot-500/10 text-woot-600 dark:text-woot-400'
                  : 'border-n-weak bg-n-solid-2 text-n-slate-11 hover:text-n-slate-12'
              "
              @click="connectionMethod = 'qr'"
            >
              {{ t('INBOX_MGMT.ADD.WHATSAPP.BAILEYS.METHOD_QR') }}
            </button>
            <button
              type="button"
              class="flex-1 rounded-lg border px-3 py-2 text-xs font-medium transition-colors"
              :class="
                connectionMethod === 'pairing'
                  ? 'border-woot-500 bg-woot-500/10 text-woot-600 dark:text-woot-400'
                  : 'border-n-weak bg-n-solid-2 text-n-slate-11 hover:text-n-slate-12'
              "
              @click="connectionMethod = 'pairing'"
            >
              {{ t('INBOX_MGMT.ADD.WHATSAPP.BAILEYS.METHOD_PAIRING') }}
            </button>
          </div>
        </div>

        <div v-if="usePairingCode" class="flex flex-col gap-1">
          <label class="text-xs font-medium text-n-slate-11">
            {{ t('INBOX_MGMT.ADD.WHATSAPP.BAILEYS.PHONE_NUMBER.LABEL') }}
          </label>
          <PhoneNumberInput
            v-model="phoneNumber"
            :placeholder="
              t('INBOX_MGMT.ADD.WHATSAPP.BAILEYS.PHONE_NUMBER.PLACEHOLDER')
            "
          />
        </div>

        <div>
          <NextButton
            :is-loading="isCreating"
            type="submit"
            solid
            blue
            :disabled="
              !inboxName.trim() || (usePairingCode && !phoneNumber.trim())
            "
            :label="t('INBOX_MGMT.ADD.WHATSAPP.BAILEYS.CREATE_BUTTON')"
          />
        </div>
      </form>
    </div>

    <!-- Step 2: QR Code / Pairing -->
    <div v-else-if="!isConnected" class="flex flex-col items-center gap-4">
      <div class="flex items-center gap-2">
        <span
          :class="usePairingCode ? 'i-lucide-smartphone' : 'i-lucide-scan'"
          class="size-5 text-woot-500"
        />
        <h3 class="text-sm font-medium text-n-slate-12">
          {{
            usePairingCode
              ? t('INBOX_MGMT.ADD.WHATSAPP.BAILEYS.PAIRING_TITLE')
              : t('INBOX_MGMT.ADD.WHATSAPP.BAILEYS.QR_TITLE')
          }}
        </h3>
      </div>
      <p class="text-center text-xs text-n-slate-11">
        {{
          usePairingCode
            ? t('INBOX_MGMT.ADD.WHATSAPP.BAILEYS.PAIRING_INSTRUCTIONS')
            : t('INBOX_MGMT.ADD.WHATSAPP.BAILEYS.QR_INSTRUCTIONS')
        }}
      </p>

      <div v-if="qrCodeData && !usePairingCode" class="rounded-xl bg-white p-4">
        <img
          :src="qrCodeData"
          :alt="t('INBOX_MGMT.ADD.WHATSAPP.BAILEYS.QR_ALT')"
          class="size-64"
        />
      </div>

      <div
        v-if="pairingCode"
        class="flex flex-col items-center gap-2 rounded-lg bg-n-alpha-black2 px-6 py-3"
      >
        <span class="text-xs text-n-slate-10">
          {{ t('INBOX_MGMT.ADD.WHATSAPP.BAILEYS.PAIRING_CODE') }}
        </span>
        <span
          class="font-mono text-2xl font-bold tracking-widest text-n-slate-12"
        >
          {{ pairingCode }}
        </span>
      </div>

      <div class="flex items-center gap-2 text-xs text-n-slate-10">
        <span class="i-lucide-loader-2 size-3 animate-spin" />
        {{ t('INBOX_MGMT.ADD.WHATSAPP.BAILEYS.QR_WAITING') }}
      </div>
    </div>

    <!-- Step 3: Connected → proceed to agents -->
    <div v-else class="flex flex-col items-center gap-6 py-8">
      <div class="connected-ring relative flex items-center justify-center">
        <svg
          class="connected-check size-16"
          viewBox="0 0 64 64"
          fill="none"
        >
          <circle
            class="connected-circle"
            cx="32"
            cy="32"
            r="28"
            stroke="rgb(var(--teal-9))"
            stroke-width="3"
            fill="none"
            stroke-linecap="round"
          />
          <path
            class="connected-tick"
            d="M20 33 L28 41 L44 25"
            stroke="rgb(var(--teal-9))"
            stroke-width="3"
            fill="none"
            stroke-linecap="round"
            stroke-linejoin="round"
          />
        </svg>
      </div>

      <div class="flex flex-col items-center gap-1 text-center">
        <h3 class="text-base font-semibold text-n-slate-12">
          {{ t('INBOX_MGMT.ADD.WHATSAPP.BAILEYS.CONNECTED') }}
        </h3>
        <p class="text-sm text-n-slate-11">
          {{ inboxName }}
        </p>
      </div>

      <div
        class="flex items-center gap-2.5 rounded-xl border border-n-teal-7/30 bg-n-teal-9/5 px-5 py-3"
      >
        <span class="i-lucide-check-circle size-4 text-n-teal-9" />
        <span class="text-sm font-medium text-n-teal-11">
          {{ t('INBOX_MGMT.ADD.WHATSAPP.BAILEYS.CONNECTED') }}
        </span>
      </div>

      <NextButton
        solid
        blue
        sm
        :label="t('INBOX_MGMT.ADD.WHATSAPP.BAILEYS.CONTINUE')"
        @click="proceedToAgents"
      />
    </div>
  </div>
</template>

<style scoped>
@keyframes draw-circle {
  from { stroke-dashoffset: 176; }
  to { stroke-dashoffset: 0; }
}
@keyframes draw-tick {
  from { stroke-dashoffset: 40; }
  to { stroke-dashoffset: 0; }
}
@keyframes ring-pulse {
  0% { box-shadow: 0 0 0 0 rgba(var(--teal-9), 0.3); }
  70% { box-shadow: 0 0 0 18px rgba(var(--teal-9), 0); }
  100% { box-shadow: 0 0 0 0 rgba(var(--teal-9), 0); }
}
.connected-ring {
  border-radius: 9999px;
  animation: ring-pulse 1.5s ease-out 0.6s;
}
.connected-circle {
  stroke-dasharray: 176;
  stroke-dashoffset: 176;
  animation: draw-circle 0.6s ease-out 0.1s forwards;
}
.connected-tick {
  stroke-dasharray: 40;
  stroke-dashoffset: 40;
  animation: draw-tick 0.35s ease-out 0.55s forwards;
}
</style>
