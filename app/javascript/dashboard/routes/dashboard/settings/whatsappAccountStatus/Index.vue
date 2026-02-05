<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';

const store = useStore();
const { t } = useI18n();

// Computed
const channels = computed(() => store.getters['whatsappAccountStatus/getChannels']);
const summary = computed(() => store.getters['whatsappAccountStatus/getSummary']);
const alerts = computed(() => store.getters['whatsappAccountStatus/getAlerts']);
const uiFlags = computed(() => store.getters['whatsappAccountStatus/getUIFlags']);

// Methods
const fetchData = async () => {
  try {
    await Promise.all([
      store.dispatch('whatsappAccountStatus/fetchAll'),
      store.dispatch('whatsappAccountStatus/fetchAlerts'),
    ]);
  } catch (error) {
    console.error('Failed to fetch account status:', error);
  }
};

const syncAll = async () => {
  for (const channel of channels.value) {
    try {
      await store.dispatch('whatsappAccountStatus/syncChannelStatus', channel.inbox_id);
    } catch (error) {
      console.error(`Failed to sync channel ${channel.inbox_id}:`, error);
    }
  }
  useAlert(t('WHATSAPP_ACCOUNT_STATUS.SYNC_SUCCESS'));
  fetchData();
};

const getStatusColor = (status) => {
  const colors = {
    ACTIVE: 'bg-green-100 text-green-800',
    RESTRICTED: 'bg-orange-100 text-orange-800',
    BANNED: 'bg-red-100 text-red-800',
    FLAGGED: 'bg-yellow-100 text-yellow-800',
    PENDING_DELETION: 'bg-red-100 text-red-800',
    DISABLED: 'bg-slate-100 text-slate-800',
  };
  return colors[status] || 'bg-slate-100 text-slate-600';
};

const getQualityColor = (quality) => {
  const colors = {
    GREEN: 'bg-green-100 text-green-800',
    YELLOW: 'bg-yellow-100 text-yellow-800',
    RED: 'bg-red-100 text-red-800',
  };
  return colors[quality] || 'bg-slate-100 text-slate-600';
};

const formatDate = (dateStr) => {
  if (!dateStr) return t('WHATSAPP_ACCOUNT_STATUS.NEVER_SYNCED');
  return new Date(dateStr).toLocaleString();
};

const formatTier = (tier, limitNumber) => {
  if (!tier && !limitNumber) return 'Standard (250/day)';
  
  // If we have the actual number, use it
  if (limitNumber) {
    if (limitNumber >= 100000) return 'Unlimited';
    return `${limitNumber.toLocaleString()}/day`;
  }
  
  // Otherwise use tier mapping
  const tierNames = {
    'TIER_50': '50/day',
    'TIER_250': '250/day',
    'TIER_1K': '1,000/day',
    'TIER_10K': '10,000/day',
    'TIER_100K': '100,000/day',
    'TIER_UNLIMITED': 'Unlimited',
    'UNLIMITED': 'Unlimited',
  };
  return tierNames[tier] || tier || 'Standard (250/day)';
};

const formatMessageCount = (count) => {
  if (count === undefined || count === null) return '0';
  return count.toLocaleString();
};

// Lifecycle
onMounted(fetchData);
</script>

<template>
  <div class="flex-1 overflow-auto p-6">
    <BaseSettingsHeader
      :title="$t('WHATSAPP_ACCOUNT_STATUS.TITLE')"
      :description="$t('WHATSAPP_ACCOUNT_STATUS.DESCRIPTION')"
      feature-name="whatsapp_account_status"
    >
      <template #actions>
        <Button
          icon="i-lucide-refresh-cw"
          label="Sync All"
          slate
          faded
          :is-loading="uiFlags.isSyncing"
          @click="syncAll"
        />
      </template>
    </BaseSettingsHeader>

    <!-- Summary Cards -->
    <div class="grid grid-cols-4 gap-4 mb-6">
      <div class="bg-white rounded-xl border border-slate-200 p-4">
        <p class="text-sm text-slate-500 mb-1">{{ $t('WHATSAPP_ACCOUNT_STATUS.SUMMARY.TOTAL') }}</p>
        <p class="text-2xl font-bold">{{ summary.total }}</p>
      </div>
      <div class="bg-white rounded-xl border border-slate-200 p-4">
        <p class="text-sm text-slate-500 mb-1">{{ $t('WHATSAPP_ACCOUNT_STATUS.SUMMARY.ACTIVE') }}</p>
        <p class="text-2xl font-bold text-green-600">{{ summary.active }}</p>
      </div>
      <div class="bg-white rounded-xl border border-slate-200 p-4">
        <p class="text-sm text-slate-500 mb-1">{{ $t('WHATSAPP_ACCOUNT_STATUS.SUMMARY.WITH_ISSUES') }}</p>
        <p class="text-2xl font-bold text-red-600">{{ summary.with_issues }}</p>
      </div>
      <div class="bg-white rounded-xl border border-slate-200 p-4">
        <p class="text-sm text-slate-500 mb-1">{{ $t('WHATSAPP_ACCOUNT_STATUS.SUMMARY.LOW_QUALITY') }}</p>
        <p class="text-2xl font-bold text-orange-600">{{ summary.low_quality }}</p>
      </div>
    </div>

    <!-- Alerts Banner -->
    <div v-if="alerts.length > 0" class="mb-6">
      <div class="bg-red-50 border border-red-200 rounded-xl p-4">
        <div class="flex items-center gap-2 mb-3">
          <svg class="w-5 h-5 text-red-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"></path>
          </svg>
          <h3 class="font-semibold text-red-800">{{ $t('WHATSAPP_ACCOUNT_STATUS.ALERTS.TITLE') }}</h3>
        </div>
        <div class="space-y-2">
          <div 
            v-for="alert in alerts" 
            :key="alert.inbox_id"
            class="flex items-center justify-between bg-white rounded-lg p-3"
          >
            <div>
              <p class="font-medium">{{ alert.inbox_name }}</p>
              <p class="text-sm text-slate-600">{{ alert.phone_number }}</p>
            </div>
            <div class="flex items-center gap-2">
              <span 
                v-for="issue in alert.issues"
                :key="issue.type"
                :class="[
                  'px-2 py-1 rounded text-xs font-medium',
                  issue.severity === 'critical' ? 'bg-red-100 text-red-800' :
                  issue.severity === 'high' ? 'bg-orange-100 text-orange-800' :
                  'bg-yellow-100 text-yellow-800'
                ]"
              >
                {{ issue.message }}
              </span>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- Loading State -->
    <woot-loading-state
      v-if="uiFlags.isFetching"
      :message="$t('WHATSAPP_ACCOUNT_STATUS.LOADING')"
    />

    <!-- Empty State -->
    <div 
      v-else-if="channels.length === 0" 
      class="flex flex-col items-center justify-center py-16 text-center text-slate-600"
    >
      <svg class="w-12 h-12 mb-4 text-slate-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z"></path>
      </svg>
      <h3 class="text-lg font-medium mb-2">{{ $t('WHATSAPP_ACCOUNT_STATUS.NO_CHANNELS') }}</h3>
      <p>{{ $t('WHATSAPP_ACCOUNT_STATUS.NO_CHANNELS_DESCRIPTION') }}</p>
    </div>

    <!-- Channels List -->
    <div v-else class="space-y-4">
      <div
        v-for="channel in channels"
        :key="channel.inbox_id"
        :class="[
          'bg-white rounded-xl border p-5 transition-all',
          channel.needs_attention ? 'border-red-200 bg-red-50/30' : 'border-slate-200'
        ]"
      >
        <!-- BANNED Banner -->
        <div v-if="channel.account_status === 'BANNED'" class="mb-4 p-4 bg-red-100 border-2 border-red-500 rounded-lg">
          <div class="flex items-center gap-3">
            <svg class="w-8 h-8 text-red-600 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M18.364 18.364A9 9 0 005.636 5.636m12.728 12.728A9 9 0 015.636 5.636m12.728 12.728L5.636 5.636"></path>
            </svg>
            <div>
              <h4 class="font-bold text-red-800 text-lg">Account Banned</h4>
              <p class="text-sm text-red-700">This WhatsApp Business Account has been banned by Meta. Please review Meta's policies and submit an appeal through the Meta Business Help Center.</p>
            </div>
          </div>
        </div>
        
        <!-- RESTRICTED Banner -->
        <div v-else-if="channel.account_status === 'RESTRICTED'" class="mb-4 p-4 bg-orange-100 border-2 border-orange-500 rounded-lg">
          <div class="flex items-center gap-3">
            <svg class="w-8 h-8 text-orange-600 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"></path>
            </svg>
            <div>
              <h4 class="font-bold text-orange-800 text-lg">Account Restricted</h4>
              <p class="text-sm text-orange-700">This account has restrictions applied. Some features may be limited. Check Meta Business Suite for details.</p>
            </div>
          </div>
        </div>
        
        <!-- FLAGGED Banner -->
        <div v-else-if="channel.account_status === 'FLAGGED'" class="mb-4 p-4 bg-yellow-100 border-2 border-yellow-500 rounded-lg">
          <div class="flex items-center gap-3">
            <svg class="w-8 h-8 text-yellow-600 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 21v-4m0 0V5a2 2 0 012-2h6.5l1 1H21l-3 6 3 6h-8.5l-1-1H5a2 2 0 00-2 2zm9-13.5V9"></path>
            </svg>
            <div>
              <h4 class="font-bold text-yellow-800 text-lg">Account Flagged</h4>
              <p class="text-sm text-yellow-700">This account is under review by Meta. Continue following best practices to maintain good standing.</p>
            </div>
          </div>
        </div>

        <div class="flex justify-between items-start mb-4">
          <div>
            <h3 class="font-semibold text-lg">{{ channel.inbox_name }}</h3>
            <p class="text-sm text-slate-500">{{ channel.phone_number }}</p>
          </div>
          <div class="flex gap-2">
            <span :class="['px-3 py-1 rounded-full text-xs font-semibold uppercase', getStatusColor(channel.account_status)]">
              {{ channel.account_status || 'ACTIVE' }}
            </span>
            <span 
              v-if="channel.quality_rating"
              :class="['px-3 py-1 rounded-full text-xs font-semibold', getQualityColor(channel.quality_rating)]"
            >
              Quality: {{ channel.quality_rating }}
            </span>
          </div>
        </div>

        <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-4 mb-4">
          <div>
            <p class="text-xs text-slate-500 uppercase">{{ $t('WHATSAPP_ACCOUNT_STATUS.DETAILS.MESSAGING_LIMIT') }}</p>
            <p class="font-medium">{{ formatTier(channel.messaging_limit_tier, channel.messaging_limit_number) }}</p>
          </div>
          <div>
            <p class="text-xs text-slate-500 uppercase">Messages Sent (24h)</p>
            <p class="font-medium text-lg">{{ formatMessageCount(channel.messages_sent_24h) }}</p>
          </div>
          <div>
            <p class="text-xs text-slate-500 uppercase">Messages Sent (Total)</p>
            <p class="font-medium">{{ formatMessageCount(channel.messages_sent_total) }}</p>
          </div>
          <div>
            <p class="text-xs text-slate-500 uppercase">{{ $t('WHATSAPP_ACCOUNT_STATUS.DETAILS.THROUGHPUT') }}</p>
            <p class="font-medium">{{ channel.current_throughput ? `${channel.current_throughput} mps` : 'Standard' }}</p>
          </div>
          <div>
            <p class="text-xs text-slate-500 uppercase">{{ $t('WHATSAPP_ACCOUNT_STATUS.DETAILS.BUSINESS_VERIFICATION') }}</p>
            <p class="font-medium">{{ channel.business_verification_status || 'Pending' }}</p>
          </div>
          <div>
            <p class="text-xs text-slate-500 uppercase">{{ $t('WHATSAPP_ACCOUNT_STATUS.LAST_SYNCED') }}</p>
            <p class="font-medium text-sm">{{ formatDate(channel.last_synced_at) }}</p>
          </div>
        </div>
        
        <!-- Sync hint -->
        <div v-if="!channel.last_synced_at" class="mb-4 p-3 bg-blue-50 border border-blue-200 rounded-lg">
          <p class="text-sm text-blue-800">
            {{ $t('WHATSAPP_ACCOUNT_STATUS.SYNC_HINT') }}
          </p>
        </div>

        <!-- Violations/Restrictions -->
        <div v-if="channel.violations && Object.keys(channel.violations).length > 0" class="mb-4">
          <p class="text-xs text-red-600 uppercase font-semibold mb-2">{{ $t('WHATSAPP_ACCOUNT_STATUS.DETAILS.VIOLATIONS') }}</p>
          <div class="flex flex-wrap gap-2">
            <span 
              v-for="(violation, type) in channel.violations" 
              :key="type"
              class="px-2 py-1 bg-red-100 text-red-800 rounded text-xs"
            >
              {{ type }}
            </span>
          </div>
        </div>

        <div v-if="channel.restrictions && channel.restrictions.length > 0" class="mb-4">
          <p class="text-xs text-orange-600 uppercase font-semibold mb-2">{{ $t('WHATSAPP_ACCOUNT_STATUS.DETAILS.RESTRICTIONS') }}</p>
          <div class="flex flex-wrap gap-2">
            <span 
              v-for="(restriction, index) in channel.restrictions" 
              :key="index"
              class="px-2 py-1 bg-orange-100 text-orange-800 rounded text-xs"
            >
              {{ restriction.type }}
            </span>
          </div>
        </div>

        <div class="flex justify-end gap-2 pt-3 border-t border-slate-100">
          <Button
            icon="i-lucide-refresh-cw"
            :label="$t('WHATSAPP_ACCOUNT_STATUS.SYNC')"
            xs
            slate
            faded
            @click="store.dispatch('whatsappAccountStatus/syncChannelStatus', channel.inbox_id)"
          />
        </div>
      </div>
    </div>
  </div>
</template>
