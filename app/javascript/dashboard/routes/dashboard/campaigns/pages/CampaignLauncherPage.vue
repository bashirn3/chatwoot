<script setup>
import { ref, provide, computed } from 'vue';
import { useI18n } from 'vue-i18n';

import CsvUploadStep from 'dashboard/components-next/Campaigns/Pages/CampaignLauncher/CsvUploadStep.vue';
import TemplateSelectionStep from 'dashboard/components-next/Campaigns/Pages/CampaignLauncher/TemplateSelectionStep.vue';
import VariableMappingStep from 'dashboard/components-next/Campaigns/Pages/CampaignLauncher/VariableMappingStep.vue';
import LaunchStep from 'dashboard/components-next/Campaigns/Pages/CampaignLauncher/LaunchStep.vue';

const { t } = useI18n();

const currentStep = ref(0);

const steps = [
  { key: 'upload', label: 'CAMPAIGN.LAUNCHER.STEPS.UPLOAD' },
  { key: 'template', label: 'CAMPAIGN.LAUNCHER.STEPS.TEMPLATE' },
  { key: 'mapping', label: 'CAMPAIGN.LAUNCHER.STEPS.MAPPING' },
  { key: 'launch', label: 'CAMPAIGN.LAUNCHER.STEPS.LAUNCH' },
];

// Shared state across steps
const csvData = ref({ headers: [], rowCount: 0, preview: [] });
const selectedInbox = ref(null);
const selectedTemplate = ref(null);
const variableMappings = ref([]);
const phoneColumn = ref('');
const nameColumn = ref('');

// Provide shared state to child steps
provide('csvData', csvData);
provide('selectedInbox', selectedInbox);
provide('selectedTemplate', selectedTemplate);
provide('variableMappings', variableMappings);
provide('phoneColumn', phoneColumn);
provide('nameColumn', nameColumn);

const currentStepComponent = computed(() => {
  const components = [
    CsvUploadStep,
    TemplateSelectionStep,
    VariableMappingStep,
    LaunchStep,
  ];
  return components[currentStep.value];
});

const goNext = () => {
  if (currentStep.value < steps.length - 1) {
    currentStep.value += 1;
  }
};

const goBack = () => {
  if (currentStep.value > 0) {
    currentStep.value -= 1;
  }
};

const resetWizard = () => {
  currentStep.value = 0;
  csvData.value = { headers: [], rowCount: 0, preview: [] };
  selectedInbox.value = null;
  selectedTemplate.value = null;
  variableMappings.value = [];
  phoneColumn.value = '';
  nameColumn.value = '';
};
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1">
    <header class="sticky top-0 z-10 px-6 lg:px-0">
      <div class="w-full max-w-[60rem] mx-auto">
        <div class="flex items-center justify-between w-full h-20 gap-2">
          <span class="text-xl font-medium text-n-slate-12">
            {{ t('CAMPAIGN.LAUNCHER.TITLE') }}
          </span>
        </div>
        <!-- Stepper -->
        <div class="flex items-center gap-1 pb-4">
          <template v-for="(step, index) in steps" :key="step.key">
            <div class="flex items-center gap-2">
              <div
                class="flex items-center justify-center w-7 h-7 rounded-full text-xs font-medium transition-colors"
                :class="{
                  'bg-n-brand text-white': index === currentStep,
                  'bg-n-brand/20 text-n-blue-11': index < currentStep,
                  'bg-n-alpha-2 text-n-slate-10': index > currentStep,
                }"
              >
                <span
                  v-if="index < currentStep"
                  class="i-lucide-check w-3.5 h-3.5"
                />
                <span v-else>{{ index + 1 }}</span>
              </div>
              <span
                class="text-sm hidden sm:inline"
                :class="{
                  'text-n-slate-12 font-medium': index === currentStep,
                  'text-n-blue-11': index < currentStep,
                  'text-n-slate-10': index > currentStep,
                }"
              >
                {{ t(step.label) }}
              </span>
            </div>
            <div
              v-if="index < steps.length - 1"
              class="flex-1 h-px mx-2"
              :class="{
                'bg-n-brand/40': index < currentStep,
                'bg-n-alpha-3': index >= currentStep,
              }"
            />
          </template>
        </div>
      </div>
    </header>
    <main class="flex-1 px-6 overflow-y-auto lg:px-0">
      <div class="w-full max-w-[60rem] mx-auto py-4">
        <component
          :is="currentStepComponent"
          @next="goNext"
          @back="goBack"
          @reset="resetWizard"
        />
      </div>
    </main>
  </section>
</template>
