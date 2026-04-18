<script setup>
import { computed, ref } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Icon from 'next/icon/Icon.vue';
import ChannelIcon from 'next/icon/ChannelIcon.vue';
import WhatsAppBridgeAPI from 'dashboard/api/whatsappBridge';

const props = defineProps({
  label: {
    type: String,
    required: true,
  },
  // eslint-disable-next-line vue/no-unused-properties
  active: {
    type: Boolean,
    default: false,
  },
  inbox: {
    type: Object,
    required: true,
  },
});

const store = useStore();
const { t } = useI18n();

const reauthorizationRequired = computed(() => {
  return props.inbox.reauthorization_required;
});

// Baileys-backed WhatsApp inbox detection: Channel::Api with a persisted
// whatsapp_bridge_instance_id in its additional_attributes.
const bridgeAttrs = computed(() => props.inbox?.additional_attributes || {});
const isBridgeWhatsapp = computed(
  () =>
    props.inbox?.channel_type === 'Channel::Api' &&
    !!bridgeAttrs.value.whatsapp_bridge_instance_id
);

const bridgeStatus = computed(() => {
  const raw = String(
    bridgeAttrs.value.whatsapp_bridge_connection_status || ''
  ).toLowerCase();
  if (['open', 'connected'].includes(raw)) return 'connected';
  if (['connecting', 'qr'].includes(raw)) return 'connecting';
  if (
    ['close', 'closed', 'logged_out', 'logged-out', 'disconnected'].includes(
      raw
    )
  )
    return 'disconnected';
  return 'unknown';
});

const statusClass = computed(() => {
  switch (bridgeStatus.value) {
    case 'connected':
      return 'bg-emerald-500';
    case 'connecting':
      return 'bg-amber-500 animate-pulse';
    case 'disconnected':
      return 'bg-n-ruby-9';
    default:
      return 'bg-n-slate-7';
  }
});

const statusTooltip = computed(() => {
  const key = `SIDEBAR.WHATSAPP_STATUS.${bridgeStatus.value.toUpperCase()}`;
  return t(key);
});

const isDeleting = ref(false);
const showConfirm = ref(false);

const openConfirm = event => {
  event.preventDefault();
  event.stopPropagation();
  showConfirm.value = true;
};

const cancelDelete = event => {
  event?.preventDefault?.();
  event?.stopPropagation?.();
  showConfirm.value = false;
};

const confirmDelete = async event => {
  event?.preventDefault?.();
  event?.stopPropagation?.();
  if (isDeleting.value) return;
  const instanceId = bridgeAttrs.value.whatsapp_bridge_instance_id;
  if (!instanceId) return;
  isDeleting.value = true;
  try {
    await WhatsAppBridgeAPI.deleteInstance(instanceId);
    // Refresh sidebar inbox list so the entry disappears without a reload.
    await store.dispatch('inboxes/get');
    useAlert(t('SIDEBAR.WHATSAPP_DELETE.SUCCESS', { name: props.label }));
  } catch (err) {
    useAlert(
      err?.response?.data?.error ||
        t('SIDEBAR.WHATSAPP_DELETE.ERROR', { name: props.label })
    );
  } finally {
    isDeleting.value = false;
    showConfirm.value = false;
  }
};
</script>

<template>
  <span
    class="relative size-5 grid place-content-center rounded-full bg-n-alpha-2"
  >
    <ChannelIcon :inbox="inbox" class="size-3" />
    <span
      v-if="isBridgeWhatsapp"
      v-tooltip.right="statusTooltip"
      class="absolute -bottom-0.5 -right-0.5 size-2 rounded-full ring-2 ring-n-background transition-colors"
      :class="statusClass"
      aria-hidden="true"
    />
  </span>
  <div class="flex-1 truncate min-w-0">{{ label }}</div>

  <!-- Reauth badge for Facebook/Instagram/Email/legacy WhatsApp (not Baileys) -->
  <div
    v-if="reauthorizationRequired && !isBridgeWhatsapp"
    v-tooltip.top-end="$t('SIDEBAR.REAUTHORIZE')"
    class="grid place-content-center size-5 bg-n-ruby-5/60 rounded-full"
  >
    <Icon icon="i-woot-alert" class="size-3 text-n-ruby-9" />
  </div>

  <!-- Inline delete for Baileys WhatsApp inboxes — hover to reveal -->
  <template v-if="isBridgeWhatsapp">
    <button
      v-if="!showConfirm"
      v-tooltip.top-end="$t('SIDEBAR.WHATSAPP_DELETE.TOOLTIP')"
      type="button"
      class="opacity-0 group-hover:opacity-100 focus-visible:opacity-100 transition-opacity grid place-content-center size-5 rounded-md hover:bg-n-ruby-5/70 hover:text-n-ruby-9 focus:outline-none focus-visible:ring-2 focus-visible:ring-n-ruby-8/40"
      @click="openConfirm"
      @keydown.enter.stop="openConfirm"
    >
      <Icon icon="i-lucide-trash-2" class="size-3" />
    </button>
    <span v-else class="inline-flex items-center gap-0.5" @click.stop>
      <button
        v-tooltip.top-end="$t('SIDEBAR.WHATSAPP_DELETE.CONFIRM')"
        type="button"
        :disabled="isDeleting"
        class="grid place-content-center size-5 rounded-md bg-n-ruby-9 text-white hover:bg-n-ruby-10 disabled:opacity-50"
        @click="confirmDelete"
      >
        <Icon
          :icon="isDeleting ? 'i-lucide-loader-2' : 'i-lucide-check'"
          class="size-3"
          :class="{ 'animate-spin': isDeleting }"
        />
      </button>
      <button
        v-tooltip.top-end="$t('SIDEBAR.WHATSAPP_DELETE.CANCEL')"
        type="button"
        :disabled="isDeleting"
        class="grid place-content-center size-5 rounded-md bg-n-alpha-2 hover:bg-n-alpha-3 text-n-slate-11"
        @click="cancelDelete"
      >
        <Icon icon="i-lucide-x" class="size-3" />
      </button>
    </span>
  </template>
</template>
