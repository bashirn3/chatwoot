<script setup>
import { ref, inject, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import campaignLauncherAPI from 'dashboard/api/campaignLauncher';

const emit = defineEmits(['next', 'back']);

const { t } = useI18n();

const selectedInbox = inject('selectedInbox');
const selectedTemplate = inject('selectedTemplate');

const inboxes = ref([]);
const isLoading = ref(false);
const error = ref('');

onMounted(async () => {
  isLoading.value = true;
  try {
    const { data } = await campaignLauncherAPI.getWhatsAppInboxes();
    inboxes.value = data.inboxes;

    if (selectedInbox.value) {
      const inbox = inboxes.value.find(i => i.id === selectedInbox.value.id);
      if (inbox) selectedInbox.value = inbox;
    }
  } catch (err) {
    error.value =
      err.response?.data?.error || t('CAMPAIGN.LAUNCHER.TEMPLATE.FETCH_ERROR');
  } finally {
    isLoading.value = false;
  }
});

const selectInbox = inbox => {
  selectedInbox.value = inbox;
  selectedTemplate.value = null;
};

const selectTemplate = tpl => {
  selectedTemplate.value = tpl;
};

const filteredTemplates = computed(() => {
  if (!selectedInbox.value) return [];
  return selectedInbox.value.templates || [];
});

const isValid = computed(() => selectedInbox.value && selectedTemplate.value);

const templatePreview = computed(() => {
  if (!selectedTemplate.value) return '';
  return selectedTemplate.value.body_text || '';
});

const templateVariableDisplay = variable => {
  return `{{${variable}}}`;
};
</script>

<template>
  <div class="flex flex-col gap-6">
    <div class="flex flex-col gap-2">
      <h2 class="text-lg font-medium text-n-slate-12">
        {{ t('CAMPAIGN.LAUNCHER.TEMPLATE.TITLE') }}
      </h2>
      <p class="text-sm text-n-slate-11">
        {{ t('CAMPAIGN.LAUNCHER.TEMPLATE.DESCRIPTION') }}
      </p>
    </div>

    <!-- Loading -->
    <div v-if="isLoading" class="flex items-center gap-2 py-8 justify-center">
      <Spinner :size="20" />
      <span class="text-sm text-n-slate-11">
        {{ t('CAMPAIGN.LAUNCHER.TEMPLATE.LOADING') }}
      </span>
    </div>

    <!-- Error -->
    <p v-if="error" class="text-sm text-n-ruby-11">
      {{ error }}
    </p>

    <template v-if="!isLoading && !error">
      <!-- Empty state -->
      <div
        v-if="inboxes.length === 0"
        class="flex flex-col items-center gap-3 py-10"
      >
        <span class="i-lucide-inbox w-10 h-10 text-n-slate-10" />
        <p class="text-sm text-n-slate-11">
          {{ t('CAMPAIGN.LAUNCHER.TEMPLATE.NO_INBOXES') }}
        </p>
      </div>

      <!-- Inbox selection -->
      <div v-else class="flex flex-col gap-4">
        <div class="flex flex-col gap-1.5">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('CAMPAIGN.LAUNCHER.TEMPLATE.SELECT_INBOX') }}
          </label>
          <div class="flex flex-wrap gap-2">
            <button
              v-for="inbox in inboxes"
              :key="inbox.id"
              class="px-4 py-2 text-sm rounded-lg border transition-colors"
              :class="{
                'border-n-brand bg-n-brand/10 text-n-blue-11':
                  selectedInbox?.id === inbox.id,
                'border-n-container bg-n-alpha-1 text-n-slate-12 hover:border-n-alpha-4':
                  selectedInbox?.id !== inbox.id,
              }"
              @click="selectInbox(inbox)"
            >
              {{ inbox.name }}
              <span class="text-xs text-n-slate-10 ml-1">
                ({{ inbox.templates.length }}
                {{ t('CAMPAIGN.LAUNCHER.TEMPLATE.TEMPLATES_COUNT') }})
              </span>
            </button>
          </div>
        </div>

        <!-- Template list -->
        <div
          v-if="selectedInbox && filteredTemplates.length > 0"
          class="flex flex-col gap-1.5"
        >
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('CAMPAIGN.LAUNCHER.TEMPLATE.SELECT_TEMPLATE') }}
          </label>
          <div class="flex flex-col gap-2 max-h-[300px] overflow-y-auto">
            <button
              v-for="tpl in filteredTemplates"
              :key="tpl.name + tpl.language"
              class="flex flex-col gap-1 p-3 text-left rounded-lg border transition-colors"
              :class="{
                'border-n-brand bg-n-brand/5':
                  selectedTemplate?.name === tpl.name &&
                  selectedTemplate?.language === tpl.language,
                'border-n-container bg-n-alpha-1 hover:border-n-alpha-4': !(
                  selectedTemplate?.name === tpl.name &&
                  selectedTemplate?.language === tpl.language
                ),
              }"
              @click="selectTemplate(tpl)"
            >
              <div class="flex items-center gap-2">
                <span class="text-sm font-medium text-n-slate-12">
                  {{ tpl.name }}
                </span>
                <span
                  class="px-1.5 py-0.5 text-[10px] rounded bg-n-alpha-2 text-n-slate-10"
                >
                  {{ tpl.language }}
                </span>
                <span
                  v-if="tpl.category"
                  class="px-1.5 py-0.5 text-[10px] rounded bg-n-alpha-2 text-n-slate-10"
                >
                  {{ tpl.category }}
                </span>
              </div>
              <p
                v-if="tpl.body_text"
                class="text-xs text-n-slate-11 line-clamp-2"
              >
                {{ tpl.body_text }}
              </p>
            </button>
          </div>
        </div>

        <!-- Template preview -->
        <div
          v-if="selectedTemplate"
          class="p-4 rounded-lg border border-n-container bg-n-alpha-1"
        >
          <label class="text-xs font-medium text-n-slate-10 mb-2 block">
            {{ t('CAMPAIGN.LAUNCHER.TEMPLATE.PREVIEW') }}
          </label>
          <p class="text-sm text-n-slate-12 whitespace-pre-wrap">
            {{ templatePreview }}
          </p>
          <div
            v-if="selectedTemplate.body_variables?.length > 0"
            class="mt-3 flex flex-wrap gap-1.5"
          >
            <span
              v-for="v in selectedTemplate.body_variables"
              :key="v"
              class="px-2 py-0.5 text-xs rounded-full bg-n-brand/10 text-n-blue-11"
            >
              {{ templateVariableDisplay(v) }}
            </span>
          </div>
        </div>
      </div>
    </template>

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
        :disabled="!isValid"
        @click="emit('next')"
      />
    </div>
  </div>
</template>
