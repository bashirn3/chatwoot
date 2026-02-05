<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useStore } from 'vuex';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';

const store = useStore();
const router = useRouter();
const { t } = useI18n();

// State
const searchQuery = ref('');
const selectedStatus = ref('');
const selectedCategory = ref('');
const selectedChannel = ref('');
const currentPage = ref(1);

// Computed
const templates = computed(() => store.getters['whatsappTemplates/getTemplates']);
const channels = computed(() => store.getters['whatsappTemplates/getChannels'] || []);
const uiFlags = computed(() => store.getters['whatsappTemplates/getUIFlags']);
const meta = computed(() => store.getters['whatsappTemplates/getMeta']);

const channelFilters = computed(() => [
  { value: '', label: 'All Channels' },
  ...channels.value.map(c => ({ value: c.id.toString(), label: c.name }))
]);

const statusFilters = [
  { value: '', label: 'All Status' },
  { value: 'DRAFT', label: 'Draft' },
  { value: 'PENDING', label: 'Pending' },
  { value: 'APPROVED', label: 'Approved' },
  { value: 'REJECTED', label: 'Rejected' },
  { value: 'PAUSED', label: 'Paused' },
];

const categoryFilters = [
  { value: '', label: 'All Categories' },
  { value: 'UTILITY', label: 'Utility' },
  { value: 'MARKETING', label: 'Marketing' },
  { value: 'AUTHENTICATION', label: 'Authentication' },
];

// Methods
const fetchTemplates = async () => {
  try {
    await store.dispatch('whatsappTemplates/fetchTemplates', {
      page: currentPage.value,
      status: selectedStatus.value,
      category: selectedCategory.value,
      channelId: selectedChannel.value,
      search: searchQuery.value,
    });
  } catch (error) {
    console.error('Failed to fetch templates:', error);
  }
};

const fetchChannels = async () => {
  try {
    await store.dispatch('whatsappTemplates/fetchChannels');
  } catch (error) {
    console.error('Failed to fetch channels:', error);
  }
};

const navigateToCreate = () => {
  router.push({
    name: 'settings_whatsapp_templates_new',
  });
};

const navigateToEdit = (template) => {
  router.push({
    name: 'settings_whatsapp_templates_edit',
    params: { templateId: template.id },
  });
};

const handleSubmitTemplate = async (template) => {
  try {
    await store.dispatch('whatsappTemplates/submitTemplate', template.id);
    useAlert(t('WHATSAPP_TEMPLATES.SUBMIT_SUCCESS'));
    fetchTemplates();
  } catch (error) {
    useAlert(error.message || t('WHATSAPP_TEMPLATES.SUBMIT_ERROR'));
  }
};

const handleSyncTemplate = async (template) => {
  try {
    await store.dispatch('whatsappTemplates/syncTemplate', template.id);
    useAlert(t('WHATSAPP_TEMPLATES.SYNC_SUCCESS'));
  } catch (error) {
    useAlert(error.message || t('WHATSAPP_TEMPLATES.SYNC_ERROR'));
  }
};

const handleResetToDraft = async (template) => {
  try {
    await store.dispatch('whatsappTemplates/resetToDraft', template.id);
    useAlert(t('WHATSAPP_TEMPLATES.RESET_TO_DRAFT_SUCCESS'));
    fetchTemplates();
  } catch (error) {
    useAlert(error.response?.data?.error || error.message || t('WHATSAPP_TEMPLATES.RESET_TO_DRAFT_ERROR'));
  }
};

const handleSyncAll = async () => {
  try {
    await store.dispatch('whatsappTemplates/syncAllTemplates');
    useAlert(t('WHATSAPP_TEMPLATES.SYNC_ALL_SUCCESS'));
  } catch (error) {
    useAlert(error.message || t('WHATSAPP_TEMPLATES.SYNC_ERROR'));
  }
};

const handleDeleteTemplate = async (template) => {
  if (!confirm(t('WHATSAPP_TEMPLATES.DELETE_CONFIRM', { name: template.name }))) {
    return;
  }
  
  try {
    await store.dispatch('whatsappTemplates/deleteTemplate', template.id);
    useAlert(t('WHATSAPP_TEMPLATES.DELETE_SUCCESS'));
    fetchTemplates();
  } catch (error) {
    useAlert(error.message || t('WHATSAPP_TEMPLATES.DELETE_ERROR'));
  }
};

const getStatusClass = (status) => {
  const classes = {
    DRAFT: 'bg-slate-100 text-slate-700',
    PENDING: 'bg-yellow-100 text-yellow-800',
    APPROVED: 'bg-green-100 text-green-800',
    REJECTED: 'bg-red-100 text-red-800',
    PAUSED: 'bg-orange-100 text-orange-800',
    DISABLED: 'bg-gray-100 text-gray-700',
  };
  return classes[status] || 'bg-slate-100 text-slate-700';
};

// Watchers
watch([selectedStatus, selectedCategory, selectedChannel, searchQuery], () => {
  currentPage.value = 1;
  fetchTemplates();
});

watch(currentPage, fetchTemplates);

// Lifecycle
onMounted(() => {
  fetchTemplates();
  fetchChannels();
});
</script>

<template>
  <div class="flex-1 overflow-auto p-6">
    <BaseSettingsHeader
      :title="$t('WHATSAPP_TEMPLATES.TITLE')"
      :description="$t('WHATSAPP_TEMPLATES.DESCRIPTION')"
      feature-name="whatsapp_templates"
    >
      <template #actions>
        <div class="flex gap-2">
          <Button
            icon="i-lucide-refresh-cw"
            :label="$t('WHATSAPP_TEMPLATES.SYNC_FROM_META')"
            slate
            faded
            :is-loading="uiFlags.isSyncing"
            @click="handleSyncAll"
          />
          <Button
            icon="i-lucide-plus"
            :label="$t('WHATSAPP_TEMPLATES.CREATE_NEW')"
            @click="navigateToCreate"
          />
        </div>
      </template>
    </BaseSettingsHeader>

    <!-- Filters -->
    <div class="flex gap-4 mb-6 flex-wrap items-center">
      <div class="relative flex-1 min-w-[200px] max-w-[300px]">
        <input
          v-model="searchQuery"
          type="text"
          class="w-full h-10 py-2 px-4 border border-slate-200 rounded-lg text-sm bg-white focus:outline-none focus:ring-2 focus:ring-woot-500 focus:border-transparent"
          :placeholder="$t('WHATSAPP_TEMPLATES.SEARCH_PLACEHOLDER')"
        />
      </div>
      
      <div class="relative">
        <select 
          v-model="selectedStatus" 
          class="custom-select h-10 px-4 pr-10 border border-slate-200 rounded-lg text-sm bg-white min-w-[150px] cursor-pointer focus:outline-none focus:ring-2 focus:ring-woot-500 focus:border-transparent"
        >
          <option v-for="f in statusFilters" :key="f.value" :value="f.value">
            {{ f.label }}
          </option>
        </select>
        <svg class="absolute right-3 top-1/2 transform -translate-y-1/2 w-4 h-4 text-slate-400 pointer-events-none" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
        </svg>
      </div>
      
      <div class="relative">
        <select 
          v-model="selectedCategory" 
          class="custom-select h-10 px-4 pr-10 border border-slate-200 rounded-lg text-sm bg-white min-w-[150px] cursor-pointer focus:outline-none focus:ring-2 focus:ring-woot-500 focus:border-transparent"
        >
          <option v-for="f in categoryFilters" :key="f.value" :value="f.value">
            {{ f.label }}
          </option>
        </select>
        <svg class="absolute right-3 top-1/2 transform -translate-y-1/2 w-4 h-4 text-slate-400 pointer-events-none" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
        </svg>
      </div>
      
      <div v-if="channels.length > 1" class="relative">
        <select 
          v-model="selectedChannel" 
          class="custom-select h-10 px-4 pr-10 border border-slate-200 rounded-lg text-sm bg-white min-w-[150px] cursor-pointer focus:outline-none focus:ring-2 focus:ring-woot-500 focus:border-transparent"
        >
          <option v-for="f in channelFilters" :key="f.value" :value="f.value">
            {{ f.label }}
          </option>
        </select>
        <svg class="absolute right-3 top-1/2 transform -translate-y-1/2 w-4 h-4 text-slate-400 pointer-events-none" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
        </svg>
      </div>
    </div>

    <!-- Loading State -->
    <woot-loading-state
      v-if="uiFlags.isFetching"
      :message="$t('WHATSAPP_TEMPLATES.LOADING')"
    />

    <!-- Empty State -->
    <div 
      v-else-if="templates.length === 0" 
      class="flex flex-col items-center justify-center py-16 text-center text-slate-600"
    >
      <span class="i-lucide-file-text w-12 h-12 mb-4 text-slate-400" />
      <h3 class="text-lg font-medium mb-2">{{ $t('WHATSAPP_TEMPLATES.EMPTY_TITLE') }}</h3>
      <p class="mb-4">{{ $t('WHATSAPP_TEMPLATES.EMPTY_DESCRIPTION') }}</p>
      <Button
        icon="i-lucide-plus"
        :label="$t('WHATSAPP_TEMPLATES.CREATE_FIRST')"
        @click="navigateToCreate"
      />
    </div>

    <!-- Templates Grid -->
    <div v-else class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
      <div
        v-for="template in templates"
        :key="template.id"
        class="bg-white border border-slate-100 rounded-xl p-4 cursor-pointer transition-all hover:border-woot-200 hover:shadow-sm"
        @click="navigateToEdit(template)"
      >
        <div class="flex justify-between items-start mb-3">
          <div class="flex gap-2">
            <span 
              :class="[
                'text-xs font-medium px-2 py-0.5 rounded uppercase',
                getStatusClass(template.status)
              ]"
            >
              {{ template.status }}
            </span>
            <span class="text-xs px-2 py-0.5 rounded bg-woot-50 text-woot-700">
              {{ template.category }}
            </span>
          </div>
          <span 
            v-if="template.quality_score && !['UNKNOWN', 'NONE', ''].includes(template.quality_score)" 
            :class="[
              'text-xs px-2 py-0.5 rounded',
              template.quality_score === 'GREEN' ? 'bg-green-100 text-green-700' :
              template.quality_score === 'YELLOW' ? 'bg-yellow-100 text-yellow-700' :
              template.quality_score === 'RED' ? 'bg-red-100 text-red-700' :
              'bg-slate-100 text-slate-700'
            ]"
          >
            {{ template.quality_score }}
          </span>
        </div>
        
        <div class="mb-3">
          <h3 class="font-medium font-mono text-sm mb-1">{{ template.name }}</h3>
          <div class="flex items-center gap-2 mb-2">
            <span class="text-xs text-slate-500">{{ template.language_name }}</span>
            <span v-if="template.channel_name" class="text-xs px-1.5 py-0.5 bg-slate-100 text-slate-600 rounded">
              {{ template.channel_name }}
            </span>
          </div>
          <p class="text-sm text-slate-700 line-clamp-3">
            {{ template.body_text }}
          </p>
        </div>
        
        <div 
          v-if="template.rejection_reason && !['NONE', 'none', ''].includes(template.rejection_reason)" 
          class="flex items-start gap-2 p-2 bg-red-50 rounded mb-3 text-xs text-red-800"
        >
          <span class="i-lucide-alert-triangle w-4 h-4 flex-shrink-0" />
          <span>{{ template.rejection_reason }}</span>
        </div>
        
        <div class="flex justify-between items-center pt-3 border-t border-slate-100">
          <span class="text-xs text-slate-500">
            {{ template.submitted_at 
              ? `Submitted ${new Date(template.submitted_at).toLocaleDateString()}`
              : `Created ${new Date(template.created_at).toLocaleDateString()}`
            }}
          </span>
          
          <div class="flex gap-1" @click.stop>
            <Button
              v-if="template.status === 'DRAFT'"
              :label="$t('WHATSAPP_TEMPLATES.SUBMIT_FOR_APPROVAL')"
              xs
              :is-loading="uiFlags.isSubmitting"
              @click="handleSubmitTemplate(template)"
            />
            
            <Button
              v-if="['PENDING', 'REJECTED', 'PAUSED'].includes(template.status)"
              :label="$t('WHATSAPP_TEMPLATES.RESET_TO_DRAFT')"
              xs
              slate
              faded
              :is-loading="uiFlags.isUpdating"
              @click="handleResetToDraft(template)"
            />
            
            <Button
              v-if="template.meta_template_id"
              icon="i-lucide-refresh-cw"
              xs
              slate
              faded
              @click="handleSyncTemplate(template)"
            />
            
            <Button
              icon="i-lucide-trash-2"
              xs
              ruby
              faded
              @click="handleDeleteTemplate(template)"
            />
          </div>
        </div>
      </div>
    </div>

    <!-- Pagination -->
    <div v-if="meta.totalPages > 1" class="flex justify-center items-center gap-4 mt-8">
      <Button
        label="Previous"
        slate
        faded
        sm
        :disabled="currentPage <= 1"
        @click="currentPage--"
      />
      <span class="text-sm text-slate-600">
        Page {{ currentPage }} of {{ meta.totalPages }}
      </span>
      <Button
        label="Next"
        slate
        faded
        sm
        :disabled="currentPage >= meta.totalPages"
        @click="currentPage++"
      />
    </div>
  </div>
</template>

<style scoped>
.custom-select {
  appearance: none;
  -webkit-appearance: none;
  -moz-appearance: none;
  background-image: none;
}

.custom-select::-ms-expand {
  display: none;
}
</style>
