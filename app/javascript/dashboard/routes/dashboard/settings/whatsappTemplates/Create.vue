<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import TemplateBuilder from './components/TemplateBuilder.vue';

const store = useStore();
const router = useRouter();
const { t } = useI18n();

const submitForApprovalImmediately = ref(true);
const selectedChannels = ref([]);

const channels = computed(() => store.getters['whatsappTemplates/getChannels'] || []);

onMounted(async () => {
  await store.dispatch('whatsappTemplates/fetchChannels');
  // Select all channels by default
  if (channels.value.length > 0) {
    selectedChannels.value = channels.value.map(c => c.id);
  }
});

const toggleChannel = (channelId) => {
  const index = selectedChannels.value.indexOf(channelId);
  if (index === -1) {
    selectedChannels.value.push(channelId);
  } else {
    selectedChannels.value.splice(index, 1);
  }
};

const selectAllChannels = () => {
  selectedChannels.value = channels.value.map(c => c.id);
};

const deselectAllChannels = () => {
  selectedChannels.value = [];
};

const handleSubmit = async (templateData) => {
  try {
    // Assign first selected channel as primary
    if (selectedChannels.value.length > 0) {
      templateData.channel_whatsapp_id = selectedChannels.value[0];
    }
    
    const created = await store.dispatch('whatsappTemplates/createTemplate', templateData);
    
    if (submitForApprovalImmediately.value && created?.id && selectedChannels.value.length > 0) {
      try {
        const result = await store.dispatch('whatsappTemplates/submitToChannels', {
          templateId: created.id,
          channelIds: selectedChannels.value
        });
        
        const successCount = result.results?.filter(r => r.success).length || 0;
        const failCount = result.results?.filter(r => !r.success).length || 0;
        
        if (failCount === 0) {
          useAlert(t('WHATSAPP_TEMPLATES.SUBMIT_TO_CHANNELS_SUCCESS', { count: successCount }));
        } else {
          useAlert(t('WHATSAPP_TEMPLATES.SUBMIT_TO_CHANNELS_PARTIAL', { success: successCount, failed: failCount }));
        }
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
    <!-- Channel Selection -->
    <div class="mb-4 p-4 bg-slate-50 border border-slate-200 rounded-xl">
      <div class="flex justify-between items-center mb-3">
        <h3 class="text-sm font-medium text-slate-700">
          {{ $t('WHATSAPP_TEMPLATES.SELECT_CHANNELS') }}
        </h3>
        <div class="flex gap-2">
          <button 
            type="button"
            class="text-xs text-woot-600 hover:text-woot-700"
            @click="selectAllChannels"
          >
            {{ $t('WHATSAPP_TEMPLATES.SELECT_ALL') }}
          </button>
          <span class="text-slate-300">|</span>
          <button 
            type="button"
            class="text-xs text-slate-500 hover:text-slate-700"
            @click="deselectAllChannels"
          >
            {{ $t('WHATSAPP_TEMPLATES.DESELECT_ALL') }}
          </button>
        </div>
      </div>
      
      <div v-if="channels.length === 0" class="text-sm text-slate-500">
        {{ $t('WHATSAPP_TEMPLATES.NO_CHANNELS_FOUND') }}
      </div>
      
      <div v-else class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-2">
        <label 
          v-for="channel in channels" 
          :key="channel.id"
          class="flex items-center gap-3 p-3 bg-white rounded-lg border cursor-pointer transition-all"
          :class="selectedChannels.includes(channel.id) 
            ? 'border-woot-500 bg-woot-50' 
            : 'border-slate-200 hover:border-slate-300'"
        >
          <input
            type="checkbox"
            :checked="selectedChannels.includes(channel.id)"
            class="rounded border-slate-300 text-woot-600 focus:ring-woot-500"
            @change="toggleChannel(channel.id)"
          />
          <div class="flex-1 min-w-0">
            <p class="text-sm font-medium text-slate-800 truncate">{{ channel.name }}</p>
            <p class="text-xs text-slate-500">{{ channel.phone_number }}</p>
          </div>
        </label>
      </div>
      
      <p class="text-xs text-slate-500 mt-3">
        {{ $t('WHATSAPP_TEMPLATES.SELECT_CHANNELS_HELP') }}
      </p>
    </div>

    <!-- Submit for approval option -->
    <div class="mb-4 p-4 bg-woot-50 border border-woot-200 rounded-xl">
      <label class="flex items-center gap-2 cursor-pointer">
        <input
          v-model="submitForApprovalImmediately"
          type="checkbox"
          class="rounded border-slate-300 text-woot-600 focus:ring-woot-500"
          :disabled="selectedChannels.length === 0"
        />
        <span class="text-sm font-medium text-slate-700">
          {{ $t('WHATSAPP_TEMPLATES.SUBMIT_FOR_APPROVAL_AFTER_CREATE') }}
        </span>
      </label>
      <p class="text-xs text-slate-500 mt-1 ml-6">
        {{ selectedChannels.length > 1 
          ? $t('WHATSAPP_TEMPLATES.SUBMIT_TO_MULTIPLE_CHANNELS_HELP', { count: selectedChannels.length })
          : $t('WHATSAPP_TEMPLATES.SUBMIT_FOR_APPROVAL_AFTER_CREATE_HELP') 
        }}
      </p>
    </div>
    
    <TemplateBuilder
      mode="create"
      @submit="handleSubmit"
      @cancel="handleCancel"
    />
  </div>
</template>
