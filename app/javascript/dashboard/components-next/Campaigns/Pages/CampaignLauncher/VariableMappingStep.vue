<script setup>
import { inject, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

const emit = defineEmits(['next', 'back']);

const { t } = useI18n();

const csvData = inject('csvData');
const selectedTemplate = inject('selectedTemplate');
const variableMappings = inject('variableMappings');

const bodyVariables = computed(
  () => selectedTemplate.value?.body_variables || []
);

const bodyText = computed(() => selectedTemplate.value?.body_text || '');

onMounted(() => {
  if (variableMappings.value.length === 0 && bodyVariables.value.length > 0) {
    variableMappings.value = bodyVariables.value.map((v, idx) => ({
      variable: v,
      variable_index: String(idx + 1),
      csv_column: '',
    }));
  }
});

const variableDisplay = variable => {
  return `{{${variable}}}`;
};

const previewText = computed(() => {
  let text = bodyText.value;
  if (!csvData.value.preview?.length) return text;

  const sampleRow = csvData.value.preview[0];
  variableMappings.value.forEach(mapping => {
    if (mapping.csv_column && sampleRow[mapping.csv_column]) {
      text = text.replace(
        `{{${mapping.variable}}}`,
        sampleRow[mapping.csv_column]
      );
    }
  });
  return text;
});

const allMapped = computed(() => {
  if (bodyVariables.value.length === 0) return true;
  return variableMappings.value.every(m => m.csv_column);
});
</script>

<template>
  <div class="flex flex-col gap-6">
    <div class="flex flex-col gap-2">
      <h2 class="text-lg font-medium text-n-slate-12">
        {{ t('CAMPAIGN.LAUNCHER.MAPPING.TITLE') }}
      </h2>
      <p class="text-sm text-n-slate-11">
        {{ t('CAMPAIGN.LAUNCHER.MAPPING.DESCRIPTION') }}
      </p>
    </div>

    <!-- No variables -->
    <div
      v-if="bodyVariables.length === 0"
      class="flex flex-col items-center gap-3 py-8 text-center"
    >
      <span class="i-lucide-check-circle w-10 h-10 text-n-teal-11" />
      <p class="text-sm text-n-slate-11">
        {{ t('CAMPAIGN.LAUNCHER.MAPPING.NO_VARIABLES') }}
      </p>
    </div>

    <!-- Variable mapping cards -->
    <div v-else class="flex flex-col gap-3">
      <div
        v-for="mapping in variableMappings"
        :key="mapping.variable"
        class="flex items-center gap-4 p-4 rounded-lg border border-n-container bg-n-alpha-1"
      >
        <div class="flex-1 min-w-0">
          <span
            class="px-2 py-1 text-xs rounded-md bg-n-brand/10 text-n-blue-11 font-mono"
          >
            {{ variableDisplay(mapping.variable) }}
          </span>
        </div>
        <span class="i-lucide-arrow-right w-4 h-4 text-n-slate-10" />
        <div class="flex-1">
          <select
            v-model="mapping.csv_column"
            class="w-full h-9 px-3 text-sm rounded-lg border border-n-strong bg-n-alpha-1 text-n-slate-12 outline-none focus:border-n-brand"
          >
            <option value="" disabled>
              {{ t('CAMPAIGN.LAUNCHER.MAPPING.SELECT_CSV_COLUMN') }}
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
    </div>

    <!-- Live preview -->
    <div
      v-if="bodyText"
      class="p-4 rounded-lg border border-n-container bg-n-alpha-1"
    >
      <label class="text-xs font-medium text-n-slate-10 mb-2 block">
        {{ t('CAMPAIGN.LAUNCHER.MAPPING.PREVIEW_LABEL') }}
      </label>
      <p class="text-sm text-n-slate-12 whitespace-pre-wrap">
        {{ previewText }}
      </p>
    </div>

    <!-- Actions -->
    <div class="flex justify-between pt-2">
      <Button
        :label="t('CAMPAIGN.LAUNCHER.BACK')"
        icon="i-lucide-arrow-left"
        variant="ghost"
        color="slate"
        @click="emit('back')"
      />
      <Button
        :label="t('CAMPAIGN.LAUNCHER.NEXT')"
        icon="i-lucide-arrow-right"
        trailing-icon
        :disabled="!allMapped"
        @click="emit('next')"
      />
    </div>
  </div>
</template>
