<script setup>
import { ref, inject } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import campaignLauncherAPI from 'dashboard/api/campaignLauncher';

const emit = defineEmits(['next']);

const { t } = useI18n();

const csvData = inject('csvData');
const phoneColumn = inject('phoneColumn');
const nameColumn = inject('nameColumn');

const isDragging = ref(false);
const isUploading = ref(false);
const fileName = ref('');
const error = ref('');

const PHONE_CANDIDATES = [
  'phone',
  'phone_number',
  'phonenumber',
  'mobile',
  'whatsapp',
  'wa_number',
];
const NAME_CANDIDATES = [
  'name',
  'full_name',
  'fullname',
  'contact_name',
  'first_name',
];

const handleFile = async file => {
  if (!file) return;
  if (!file.name.endsWith('.csv')) {
    error.value = t('CAMPAIGN.LAUNCHER.CSV.INVALID_FILE');
    return;
  }
  error.value = '';
  fileName.value = file.name;
  isUploading.value = true;

  try {
    const { data } = await campaignLauncherAPI.uploadCsv(file);
    csvData.value = {
      headers: data.headers,
      rowCount: data.row_count,
      preview: data.preview,
    };

    const lowerHeaders = data.headers.map(h => h.toLowerCase());

    const phoneMatch = PHONE_CANDIDATES.find(c => lowerHeaders.includes(c));
    if (phoneMatch) {
      phoneColumn.value = data.headers[lowerHeaders.indexOf(phoneMatch)];
    }

    const nameMatch = NAME_CANDIDATES.find(c => lowerHeaders.includes(c));
    if (nameMatch) {
      nameColumn.value = data.headers[lowerHeaders.indexOf(nameMatch)];
    }
  } catch (err) {
    error.value =
      err.response?.data?.error || t('CAMPAIGN.LAUNCHER.CSV.UPLOAD_ERROR');
  } finally {
    isUploading.value = false;
  }
};

const onFileInput = event => {
  handleFile(event.target.files[0]);
};

const onDrop = event => {
  isDragging.value = false;
  const file = event.dataTransfer.files[0];
  handleFile(file);
};

const onDragOver = () => {
  isDragging.value = true;
};

const onDragLeave = () => {
  isDragging.value = false;
};

const isValid = () => csvData.value.rowCount > 0 && phoneColumn.value;

const handleNext = () => {
  if (!phoneColumn.value) {
    error.value = t('CAMPAIGN.LAUNCHER.CSV.PHONE_REQUIRED');
    return;
  }
  emit('next');
};
</script>

<template>
  <div class="flex flex-col gap-6">
    <div class="flex flex-col gap-2">
      <h2 class="text-lg font-medium text-n-slate-12">
        {{ t('CAMPAIGN.LAUNCHER.CSV.TITLE') }}
      </h2>
      <p class="text-sm text-n-slate-11">
        {{ t('CAMPAIGN.LAUNCHER.CSV.DESCRIPTION') }}
      </p>
    </div>

    <!-- Drop zone -->
    <label
      class="flex flex-col items-center justify-center gap-3 p-10 border-2 border-dashed rounded-xl cursor-pointer transition-colors"
      :class="{
        'border-n-brand bg-n-brand/5': isDragging,
        'border-n-alpha-3 hover:border-n-alpha-4 bg-n-alpha-1': !isDragging,
      }"
      @dragover.prevent="onDragOver"
      @dragleave="onDragLeave"
      @drop.prevent="onDrop"
    >
      <span class="i-lucide-upload-cloud w-10 h-10 text-n-slate-10" />
      <div class="text-center">
        <span class="text-sm font-medium text-n-blue-11">
          {{ t('CAMPAIGN.LAUNCHER.CSV.DROP_LABEL') }}
        </span>
        <p class="text-xs text-n-slate-10 mt-1">
          {{ t('CAMPAIGN.LAUNCHER.CSV.FORMAT_HINT') }}
        </p>
      </div>
      <input type="file" accept=".csv" class="hidden" @change="onFileInput" />
    </label>

    <!-- Loading -->
    <div
      v-if="isUploading"
      class="flex items-center gap-2 text-sm text-n-slate-11"
    >
      <Spinner :size="16" />
      <span>{{ t('CAMPAIGN.LAUNCHER.CSV.UPLOADING') }}</span>
    </div>

    <!-- Error -->
    <p v-if="error" class="text-sm text-n-ruby-11">
      {{ error }}
    </p>

    <!-- Upload success -->
    <div
      v-if="csvData.rowCount > 0 && !isUploading"
      class="flex flex-col gap-4"
    >
      <div
        class="flex items-center gap-3 p-4 rounded-lg bg-n-brand/5 border border-n-brand/20"
      >
        <span class="i-lucide-file-check w-5 h-5 text-n-blue-11" />
        <div class="flex-1 min-w-0">
          <p class="text-sm font-medium text-n-slate-12 truncate">
            {{ fileName }}
          </p>
          <p class="text-xs text-n-slate-11">
            {{ csvData.rowCount }}
            {{ t('CAMPAIGN.LAUNCHER.CSV.ROWS_FOUND') }}
            &middot; {{ csvData.headers.length }}
            {{ t('CAMPAIGN.LAUNCHER.CSV.COLUMNS') }}
          </p>
        </div>
      </div>

      <!-- Column mapping -->
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <div class="flex flex-col gap-1.5">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('CAMPAIGN.LAUNCHER.CSV.PHONE_COLUMN') }}
          </label>
          <select
            v-model="phoneColumn"
            class="h-10 px-3 text-sm rounded-lg border border-n-strong bg-n-alpha-1 text-n-slate-12 outline-none focus:border-n-brand"
          >
            <option value="" disabled>
              {{ t('CAMPAIGN.LAUNCHER.CSV.SELECT_COLUMN') }}
            </option>
            <option
              v-for="header in csvData.headers"
              :key="header"
              :value="header"
            >
              {{ header }}
            </option>
          </select>
        </div>
        <div class="flex flex-col gap-1.5">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('CAMPAIGN.LAUNCHER.CSV.NAME_COLUMN') }}
          </label>
          <select
            v-model="nameColumn"
            class="h-10 px-3 text-sm rounded-lg border border-n-strong bg-n-alpha-1 text-n-slate-12 outline-none focus:border-n-brand"
          >
            <option value="">
              {{ t('CAMPAIGN.LAUNCHER.CSV.NONE') }}
            </option>
            <option
              v-for="header in csvData.headers"
              :key="header"
              :value="header"
            >
              {{ header }}
            </option>
          </select>
        </div>
      </div>

      <!-- Preview table -->
      <div class="overflow-x-auto rounded-lg border border-n-container">
        <table class="w-full text-sm">
          <thead>
            <tr class="bg-n-alpha-1">
              <th
                v-for="header in csvData.headers"
                :key="header"
                class="px-3 py-2 text-left text-xs font-medium text-n-slate-11 whitespace-nowrap"
              >
                {{ header }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="(row, idx) in csvData.preview"
              :key="idx"
              class="border-t border-n-container"
            >
              <td
                v-for="header in csvData.headers"
                :key="header"
                class="px-3 py-2 text-n-slate-12 whitespace-nowrap max-w-[200px] truncate"
              >
                {{ row[header] }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <!-- Actions -->
    <div class="flex justify-end pt-2">
      <Button
        :label="t('CAMPAIGN.LAUNCHER.NEXT')"
        icon="i-lucide-arrow-right"
        trailing-icon
        :disabled="!isValid()"
        @click="handleNext"
      />
    </div>
  </div>
</template>
