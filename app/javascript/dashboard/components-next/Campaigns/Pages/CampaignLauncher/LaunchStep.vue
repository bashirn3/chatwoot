<script setup>
import { ref, inject, computed, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Auth from 'dashboard/api/auth';
import campaignLauncherAPI from 'dashboard/api/campaignLauncher';

const emit = defineEmits(['back', 'reset']);

const { t } = useI18n();

const csvData = inject('csvData');
const selectedInbox = inject('selectedInbox');
const selectedTemplate = inject('selectedTemplate');
const variableMappings = inject('variableMappings');
const phoneColumn = inject('phoneColumn');
const nameColumn = inject('nameColumn');

const isValidating = ref(false);
const isLaunching = ref(false);
const isDone = ref(false);
const validationErrors = ref([]);
const launchLog = ref([]);
const stats = ref({
  sent: 0,
  failed: 0,
  skipped: 0,
  total: 0,
});
const delayMs = ref(1000);

let abortController = null;

const progress = computed(() => {
  if (stats.value.total === 0) return 0;
  const processed = stats.value.sent + stats.value.failed + stats.value.skipped;
  return Math.round((processed / stats.value.total) * 100);
});

const handleValidate = async () => {
  isValidating.value = true;
  validationErrors.value = [];

  try {
    const { data } = await campaignLauncherAPI.validate({
      phone_column: phoneColumn.value,
      variable_mappings: variableMappings.value,
    });

    if (!data.valid) {
      validationErrors.value = data.errors;
    } else {
      stats.value.total = data.total_recipients;
    }
  } catch (err) {
    validationErrors.value = [
      err.response?.data?.error || t('CAMPAIGN.LAUNCHER.LAUNCH.VALIDATE_ERROR'),
    ];
  } finally {
    isValidating.value = false;
  }
};

const handleSSEEvent = event => {
  if (event.type === 'row') {
    launchLog.value.push({
      status: event.status,
      phone: event.phone,
      detail: event.detail,
    });
    stats.value.sent = event.sent;
    stats.value.failed = event.failed;
    stats.value.skipped = event.skipped;
  } else if (event.type === 'done') {
    stats.value.sent = event.sent;
    stats.value.failed = event.failed;
    stats.value.skipped = event.skipped;
  }
};

const processSSEStream = async reader => {
  const decoder = new TextDecoder();
  let buffer = '';
  let reading = true;

  while (reading) {
    // eslint-disable-next-line no-await-in-loop
    const { done, value } = await reader.read();
    if (done) {
      reading = false;
      break;
    }

    buffer += decoder.decode(value, { stream: true });
    const lines = buffer.split('\n');
    buffer = lines.pop();

    lines.forEach(line => {
      if (line.startsWith('data: ')) {
        try {
          const event = JSON.parse(line.slice(6));
          handleSSEEvent(event);
        } catch {
          // Skip invalid JSON
        }
      }
    });
  }
};

const handleLaunch = async () => {
  isLaunching.value = true;
  isDone.value = false;
  launchLog.value = [];
  stats.value = {
    sent: 0,
    failed: 0,
    skipped: 0,
    total: csvData.value.rowCount,
  };

  abortController = new AbortController();

  const payload = {
    inbox_id: selectedInbox.value.id,
    template_name: selectedTemplate.value.name,
    template_category: selectedTemplate.value.category,
    template_language: selectedTemplate.value.language,
    template_body_text: selectedTemplate.value.body_text,
    phone_column: phoneColumn.value,
    name_column: nameColumn.value,
    variable_mappings: variableMappings.value,
    delay_ms: delayMs.value,
  };

  try {
    const launchUrl = campaignLauncherAPI.getLaunchUrl();
    const authData = Auth.getAuthData();

    const response = await fetch(launchUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'access-token': authData['access-token'],
        'token-type': authData['token-type'],
        client: authData.client,
        expiry: authData.expiry,
        uid: authData.uid,
      },
      body: JSON.stringify(payload),
      signal: abortController.signal,
    });

    const reader = response.body.getReader();
    await processSSEStream(reader);
  } catch (err) {
    if (err.name !== 'AbortError') {
      launchLog.value.push({
        status: 'error',
        detail: err.message || t('CAMPAIGN.LAUNCHER.LAUNCH.STREAM_ERROR'),
        phone: '',
      });
    }
  } finally {
    isLaunching.value = false;
    isDone.value = true;
  }
};

const handleAbort = () => {
  if (abortController) {
    abortController.abort();
  }
};

onBeforeUnmount(() => {
  handleAbort();
});

const statusIcon = status => {
  const icons = {
    sent: 'i-lucide-check-circle',
    error: 'i-lucide-x-circle',
    skipped: 'i-lucide-minus-circle',
  };
  return icons[status] || 'i-lucide-circle';
};

const statusColor = status => {
  const colors = {
    sent: 'text-n-teal-11',
    error: 'text-n-ruby-11',
    skipped: 'text-n-amber-11',
  };
  return colors[status] || 'text-n-slate-11';
};
</script>

<template>
  <div class="flex flex-col gap-6">
    <div class="flex flex-col gap-2">
      <h2 class="text-lg font-medium text-n-slate-12">
        {{ t('CAMPAIGN.LAUNCHER.LAUNCH.TITLE') }}
      </h2>
      <p class="text-sm text-n-slate-11">
        {{ t('CAMPAIGN.LAUNCHER.LAUNCH.DESCRIPTION') }}
      </p>
    </div>

    <!-- Summary card -->
    <div
      class="grid grid-cols-2 sm:grid-cols-4 gap-3 p-4 rounded-lg border border-n-container bg-n-alpha-1"
    >
      <div class="flex flex-col gap-1">
        <span class="text-xs text-n-slate-10">
          {{ t('CAMPAIGN.LAUNCHER.LAUNCH.INBOX') }}
        </span>
        <span class="text-sm font-medium text-n-slate-12">
          {{ selectedInbox?.name || '-' }}
        </span>
      </div>
      <div class="flex flex-col gap-1">
        <span class="text-xs text-n-slate-10">
          {{ t('CAMPAIGN.LAUNCHER.LAUNCH.TEMPLATE') }}
        </span>
        <span class="text-sm font-medium text-n-slate-12">
          {{ selectedTemplate?.name || '-' }}
        </span>
      </div>
      <div class="flex flex-col gap-1">
        <span class="text-xs text-n-slate-10">
          {{ t('CAMPAIGN.LAUNCHER.LAUNCH.RECIPIENTS') }}
        </span>
        <span class="text-sm font-medium text-n-slate-12">
          {{ csvData.rowCount }}
        </span>
      </div>
      <div class="flex flex-col gap-1">
        <span class="text-xs text-n-slate-10">
          {{ t('CAMPAIGN.LAUNCHER.LAUNCH.VARIABLES') }}
        </span>
        <span class="text-sm font-medium text-n-slate-12">
          {{ variableMappings.length }}
        </span>
      </div>
    </div>

    <!-- Delay setting -->
    <div v-if="!isLaunching && !isDone" class="flex items-center gap-3">
      <label class="text-sm text-n-slate-12">
        {{ t('CAMPAIGN.LAUNCHER.LAUNCH.DELAY') }}
      </label>
      <input
        v-model.number="delayMs"
        type="number"
        min="200"
        max="10000"
        step="100"
        class="w-24 h-9 px-3 text-sm rounded-lg border border-n-strong bg-n-alpha-1 text-n-slate-12 outline-none focus:border-n-brand"
      />
      <span class="text-xs text-n-slate-10">
        {{ t('CAMPAIGN.LAUNCHER.LAUNCH.MS_UNIT') }}
      </span>
    </div>

    <!-- Validation errors -->
    <div
      v-if="validationErrors.length > 0"
      class="flex flex-col gap-1.5 p-3 rounded-lg bg-n-ruby-9/5 border border-n-ruby-9/20"
    >
      <p
        v-for="(err, idx) in validationErrors"
        :key="idx"
        class="text-sm text-n-ruby-11"
      >
        {{ err }}
      </p>
    </div>

    <!-- Progress bar -->
    <div v-if="isLaunching || isDone" class="flex flex-col gap-2">
      <div class="flex items-center justify-between text-sm">
        <span class="text-n-slate-11">
          {{ t('CAMPAIGN.LAUNCHER.LAUNCH.PROGRESS') }}
        </span>
        <span class="text-n-slate-12 font-medium">{{ progress }}%</span>
      </div>
      <div class="h-2 rounded-full bg-n-alpha-3 overflow-hidden">
        <div
          class="h-full rounded-full bg-n-brand transition-all duration-300"
          :style="{ width: progress + '%' }"
        />
      </div>
      <div class="flex gap-4 text-xs text-n-slate-11">
        <span class="text-n-teal-11">
          {{ t('CAMPAIGN.LAUNCHER.LAUNCH.SENT') }}: {{ stats.sent }}
        </span>
        <span class="text-n-ruby-11">
          {{ t('CAMPAIGN.LAUNCHER.LAUNCH.FAILED') }}: {{ stats.failed }}
        </span>
        <span class="text-n-amber-11">
          {{ t('CAMPAIGN.LAUNCHER.LAUNCH.SKIPPED') }}:
          {{ stats.skipped }}
        </span>
      </div>
    </div>

    <!-- Log -->
    <div
      v-if="launchLog.length > 0"
      class="flex flex-col gap-0.5 max-h-[300px] overflow-y-auto rounded-lg border border-n-container bg-n-alpha-1 p-2"
    >
      <div
        v-for="(entry, idx) in launchLog"
        :key="idx"
        class="flex items-center gap-2 px-2 py-1 text-xs"
      >
        <span
          :class="[statusIcon(entry.status), statusColor(entry.status)]"
          class="w-3.5 h-3.5 flex-shrink-0"
        />
        <span class="text-n-slate-11 font-mono w-32 truncate">
          {{ entry.phone }}
        </span>
        <span class="text-n-slate-10 truncate flex-1">
          {{ entry.detail }}
        </span>
      </div>
    </div>

    <!-- Done summary -->
    <div v-if="isDone" class="flex flex-col items-center gap-3 py-6">
      <span class="i-lucide-check-circle-2 w-12 h-12 text-n-teal-11" />
      <p class="text-base font-medium text-n-slate-12">
        {{ t('CAMPAIGN.LAUNCHER.LAUNCH.COMPLETE') }}
      </p>
      <p class="text-sm text-n-slate-11">
        {{
          t('CAMPAIGN.LAUNCHER.LAUNCH.COMPLETE_SUMMARY', {
            sent: stats.sent,
            failed: stats.failed,
            skipped: stats.skipped,
          })
        }}
      </p>
    </div>

    <!-- Actions -->
    <div class="flex justify-between pt-2">
      <Button
        v-if="!isLaunching && !isDone"
        :label="t('CAMPAIGN.LAUNCHER.BACK')"
        icon="i-lucide-arrow-left"
        variant="ghost"
        color="slate"
        @click="emit('back')"
      />

      <div v-if="isLaunching" class="flex items-center gap-3">
        <Spinner :size="16" />
        <span class="text-sm text-n-slate-11">
          {{ t('CAMPAIGN.LAUNCHER.LAUNCH.SENDING') }}
        </span>
        <Button
          :label="t('CAMPAIGN.LAUNCHER.LAUNCH.ABORT')"
          variant="ghost"
          color="ruby"
          size="sm"
          @click="handleAbort"
        />
      </div>

      <div v-if="!isLaunching && !isDone" class="flex gap-2">
        <Button
          :label="t('CAMPAIGN.LAUNCHER.LAUNCH.VALIDATE_BTN')"
          variant="outline"
          :is-loading="isValidating"
          @click="handleValidate"
        />
        <Button
          :label="t('CAMPAIGN.LAUNCHER.LAUNCH.LAUNCH_BTN')"
          icon="i-lucide-rocket"
          :disabled="validationErrors.length > 0"
          @click="handleLaunch"
        />
      </div>

      <Button
        v-if="isDone"
        :label="t('CAMPAIGN.LAUNCHER.LAUNCH.NEW_CAMPAIGN')"
        icon="i-lucide-plus"
        @click="emit('reset')"
      />
    </div>
  </div>
</template>
