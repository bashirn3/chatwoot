<script setup>
import { ref, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useRouter, useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import TemplateBuilder from './components/TemplateBuilder.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const store = useStore();
const router = useRouter();
const route = useRoute();
const { t } = useI18n();

const template = ref(null);
const isLoading = ref(true);

const fetchTemplate = async () => {
  try {
    const templateId = route.params.templateId;
    template.value = await store.dispatch('whatsappTemplates/fetchTemplate', templateId);
  } catch (error) {
    useAlert(t('WHATSAPP_TEMPLATES.FETCH_ERROR'));
    router.push({ name: 'settings_whatsapp_templates' });
  } finally {
    isLoading.value = false;
  }
};

const handleSubmit = async (templateData) => {
  try {
    await store.dispatch('whatsappTemplates/updateTemplate', {
      id: template.value.id,
      ...templateData,
    });
    useAlert(t('WHATSAPP_TEMPLATES.UPDATE_SUCCESS'));
    router.push({ name: 'settings_whatsapp_templates' });
  } catch (error) {
    const errorMessage = error.response?.data?.errors?.join(', ') || error.message;
    useAlert(errorMessage || t('WHATSAPP_TEMPLATES.UPDATE_ERROR'));
  }
};

const handleCancel = () => {
  router.push({ name: 'settings_whatsapp_templates' });
};

onMounted(fetchTemplate);
</script>

<template>
  <div class="flex-1 overflow-auto p-6">
    <woot-loading-state
      v-if="isLoading"
      :message="$t('WHATSAPP_TEMPLATES.LOADING')"
    />
    
    <TemplateBuilder
      v-else-if="template"
      :template="template"
      mode="edit"
      @submit="handleSubmit"
      @cancel="handleCancel"
    />
    
    <div v-else class="flex flex-col items-center justify-center py-16 text-center text-slate-600">
      <p class="mb-4">{{ $t('WHATSAPP_TEMPLATES.NOT_FOUND') }}</p>
      <Button
        :label="$t('WHATSAPP_TEMPLATES.BACK_TO_LIST')"
        @click="handleCancel"
      />
    </div>
  </div>
</template>
