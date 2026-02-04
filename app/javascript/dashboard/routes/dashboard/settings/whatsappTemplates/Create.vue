<script setup>
import { useStore } from 'vuex';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import TemplateBuilder from './components/TemplateBuilder.vue';

const store = useStore();
const router = useRouter();
const { t } = useI18n();

const handleSubmit = async (templateData) => {
  try {
    await store.dispatch('whatsappTemplates/createTemplate', templateData);
    useAlert(t('WHATSAPP_TEMPLATES.CREATE_SUCCESS'));
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
    <TemplateBuilder
      mode="create"
      @submit="handleSubmit"
      @cancel="handleCancel"
    />
  </div>
</template>
