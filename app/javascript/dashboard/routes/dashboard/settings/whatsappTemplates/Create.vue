<script setup>
import { ref } from 'vue';
import { useStore } from 'vuex';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import TemplateBuilder from './components/TemplateBuilder.vue';

const store = useStore();
const router = useRouter();
const { t } = useI18n();

const submitForApprovalImmediately = ref(true);

const handleSubmit = async (templateData) => {
  try {
    const created = await store.dispatch('whatsappTemplates/createTemplate', templateData);
    if (submitForApprovalImmediately.value && created?.id) {
      try {
        await store.dispatch('whatsappTemplates/submitTemplate', created.id);
        useAlert(t('WHATSAPP_TEMPLATES.CREATE_AND_SUBMIT_SUCCESS'));
      } catch (submitError) {
        useAlert(t('WHATSAPP_TEMPLATES.CREATE_SUCCESS'));
        useAlert(submitError.response?.data?.error || submitError.message || t('WHATSAPP_TEMPLATES.SUBMIT_ERROR'));
      }
    } else {
      useAlert(t('WHATSAPP_TEMPLATES.CREATE_SUCCESS'));
    }
    router.push({ name: 'settings_whatsapp_templates' });
  } catch (error) {
    const errorMessage = error.response?.data?.errors?.join(', ') || error.message;
    useAlert(errorMessage || t('WHATSAPP_TEMPLATES.CREATE_ERROR'));
  }
};

const handleCancel = () => {
  router.push({ name: 'settings_whatsapp_templates' });
};
</script>

<template>
  <div class="flex-1 overflow-auto p-6">
    <div class="mb-4 p-4 bg-woot-50 border border-woot-200 rounded-xl">
      <label class="flex items-center gap-2 cursor-pointer">
        <input
          v-model="submitForApprovalImmediately"
          type="checkbox"
          class="rounded border-slate-300 text-woot-600 focus:ring-woot-500"
        />
        <span class="text-sm font-medium text-slate-700">{{ $t('WHATSAPP_TEMPLATES.SUBMIT_FOR_APPROVAL_AFTER_CREATE') }}</span>
      </label>
      <p class="text-xs text-slate-500 mt-1 ml-6">{{ $t('WHATSAPP_TEMPLATES.SUBMIT_FOR_APPROVAL_AFTER_CREATE_HELP') }}</p>
    </div>
    <TemplateBuilder
      mode="create"
      @submit="handleSubmit"
      @cancel="handleCancel"
    />
  </div>
</template>
