<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useStore } from 'vuex';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';

defineProps({
  embedded: { type: Boolean, default: false },
});

const store = useStore();
const router = useRouter();
const { t } = useI18n();

const searchQuery = ref('');
const selectedStatus = ref('');
const selectedCategory = ref('');
const selectedChannel = ref('');
const currentPage = ref(1);

const templates = computed(
  () => store.getters['whatsappTemplates/getTemplates']
);
const channels = computed(
  () => store.getters['whatsappTemplates/getChannels'] || []
);
const uiFlags = computed(() => store.getters['whatsappTemplates/getUIFlags']);
const meta = computed(() => store.getters['whatsappTemplates/getMeta']);

const channelFilters = computed(() => [
  { value: '', label: t('WHATSAPP_TEMPLATES.FILTERS.ALL_CHANNELS') },
  ...channels.value.map(c => ({ value: c.id.toString(), label: c.name })),
]);

const statusFilters = computed(() => [
  { value: '', label: t('WHATSAPP_TEMPLATES.FILTERS.ALL_STATUS') },
  { value: 'DRAFT', label: t('WHATSAPP_TEMPLATES.STATUS.DRAFT') },
  { value: 'PENDING', label: t('WHATSAPP_TEMPLATES.STATUS.PENDING') },
  { value: 'APPROVED', label: t('WHATSAPP_TEMPLATES.STATUS.APPROVED') },
  { value: 'REJECTED', label: t('WHATSAPP_TEMPLATES.STATUS.REJECTED') },
  { value: 'PAUSED', label: t('WHATSAPP_TEMPLATES.STATUS.PAUSED') },
]);

const categoryFilters = computed(() => [
  { value: '', label: t('WHATSAPP_TEMPLATES.FILTERS.ALL_CATEGORIES') },
  { value: 'UTILITY', label: t('WHATSAPP_TEMPLATES.CATEGORIES.UTILITY') },
  { value: 'MARKETING', label: t('WHATSAPP_TEMPLATES.CATEGORIES.MARKETING') },
  {
    value: 'AUTHENTICATION',
    label: t('WHATSAPP_TEMPLATES.CATEGORIES.AUTHENTICATION'),
  },
]);

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
    // noop
  }
};

const fetchChannels = async () => {
  try {
    await store.dispatch('whatsappTemplates/fetchChannels');
  } catch (error) {
    // noop
  }
};

const navigateToCreate = () => {
  router.push({
    name: 'settings_whatsapp_templates_new',
  });
};

const navigateToEdit = template => {
  router.push({
    name: 'settings_whatsapp_templates_edit',
    params: { templateId: template.id },
  });
};

const handleSubmitTemplate = async template => {
  try {
    await store.dispatch('whatsappTemplates/submitTemplate', template.id);
    useAlert(t('WHATSAPP_TEMPLATES.SUBMIT_SUCCESS'));
    fetchTemplates();
  } catch (error) {
    useAlert(error.message || t('WHATSAPP_TEMPLATES.SUBMIT_ERROR'));
  }
};

const handleSyncTemplate = async template => {
  try {
    await store.dispatch('whatsappTemplates/syncTemplate', template.id);
    useAlert(t('WHATSAPP_TEMPLATES.SYNC_SUCCESS'));
  } catch (error) {
    useAlert(error.message || t('WHATSAPP_TEMPLATES.SYNC_ERROR'));
  }
};

const handleResetToDraft = async template => {
  try {
    await store.dispatch('whatsappTemplates/resetToDraft', template.id);
    useAlert(t('WHATSAPP_TEMPLATES.RESET_TO_DRAFT_SUCCESS'));
    fetchTemplates();
  } catch (error) {
    useAlert(
      error.response?.data?.error ||
        error.message ||
        t('WHATSAPP_TEMPLATES.RESET_TO_DRAFT_ERROR')
    );
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

const handleImportFromMeta = async () => {
  try {
    const result = await store.dispatch('whatsappTemplates/importFromMeta');
    if (result && result.total_imported > 0) {
      useAlert(
        t('WHATSAPP_TEMPLATES.IMPORT_SUCCESS', { count: result.total_imported })
      );
    }
    return result;
  } catch (error) {
    // Silent failure on auto-import
    return null;
  }
};

const handleDuplicateTemplate = async template => {
  const newName = window.prompt(
    t('WHATSAPP_TEMPLATES.DUPLICATE_PROMPT'),
    `${template.name}_copy`
  );

  if (!newName) return;

  try {
    const duplicate = await store.dispatch(
      'whatsappTemplates/duplicateTemplate',
      {
        templateId: template.id,
        newName,
      }
    );
    useAlert(t('WHATSAPP_TEMPLATES.DUPLICATE_SUCCESS'));
    navigateToEdit(duplicate);
  } catch (error) {
    useAlert(
      error.response?.data?.error ||
        error.message ||
        t('WHATSAPP_TEMPLATES.DUPLICATE_ERROR')
    );
  }
};

const handleDeleteTemplate = async template => {
  if (
    !window.confirm(
      t('WHATSAPP_TEMPLATES.DELETE_CONFIRM', { name: template.name })
    )
  ) {
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

const getStatusClass = status => {
  const classes = {
    DRAFT: 'bg-slate-100 dark:bg-slate-800 text-slate-700 dark:text-slate-300',
    PENDING:
      'bg-yellow-100 dark:bg-yellow-900/30 text-yellow-800 dark:text-yellow-200',
    APPROVED:
      'bg-green-100 dark:bg-green-900/30 text-green-800 dark:text-green-200',
    REJECTED: 'bg-red-100 dark:bg-red-900/30 text-red-800 dark:text-red-200',
    PAUSED:
      'bg-orange-100 dark:bg-orange-900/30 text-orange-800 dark:text-orange-200',
    DISABLED: 'bg-gray-100 dark:bg-gray-800 text-gray-700 dark:text-gray-300',
  };
  return (
    classes[status] ||
    'bg-slate-100 dark:bg-slate-800 text-slate-700 dark:text-slate-300'
  );
};

watch([selectedStatus, selectedCategory, selectedChannel, searchQuery], () => {
  currentPage.value = 1;
  fetchTemplates();
});

watch(currentPage, fetchTemplates);

onMounted(async () => {
  await fetchChannels();

  if (channels.value && channels.value.length > 0) {
    await handleImportFromMeta();
  }

  fetchTemplates();
});
</script>

<template>
  <div class="flex-1 overflow-auto p-6">
    <BaseSettingsHeader
      v-if="!embedded"
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
    <div v-else class="flex gap-2 mb-4">
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

    <!-- Filters -->
    <div class="flex gap-4 mb-6 flex-wrap items-center">
      <div class="relative flex-1 min-w-[200px] max-w-[300px]">
        <input
          v-model="searchQuery"
          type="text"
          class="w-full h-10 py-2 px-4 border border-n-weak rounded-lg text-sm bg-n-alpha-black2 text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus:ring-2 focus:ring-woot-500 focus:border-transparent"
          :placeholder="$t('WHATSAPP_TEMPLATES.SEARCH_PLACEHOLDER')"
        />
      </div>

      <div class="relative">
        <select
          v-model="selectedStatus"
          class="h-10 px-4 pr-10 border border-n-weak rounded-lg text-sm bg-n-alpha-black2 text-n-slate-12 min-w-[150px] cursor-pointer appearance-none focus:outline-none focus:ring-2 focus:ring-woot-500 focus:border-transparent"
        >
          <option v-for="f in statusFilters" :key="f.value" :value="f.value">
            {{ f.label }}
          </option>
        </select>
        <svg
          class="absolute right-3 top-1/2 -translate-y-1/2 w-4 h-4 text-n-slate-10 pointer-events-none"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M19 9l-7 7-7-7"
          />
        </svg>
      </div>

      <div class="relative">
        <select
          v-model="selectedCategory"
          class="h-10 px-4 pr-10 border border-n-weak rounded-lg text-sm bg-n-alpha-black2 text-n-slate-12 min-w-[150px] cursor-pointer appearance-none focus:outline-none focus:ring-2 focus:ring-woot-500 focus:border-transparent"
        >
          <option v-for="f in categoryFilters" :key="f.value" :value="f.value">
            {{ f.label }}
          </option>
        </select>
        <svg
          class="absolute right-3 top-1/2 -translate-y-1/2 w-4 h-4 text-n-slate-10 pointer-events-none"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M19 9l-7 7-7-7"
          />
        </svg>
      </div>

      <div v-if="channels.length > 1" class="relative">
        <select
          v-model="selectedChannel"
          class="h-10 px-4 pr-10 border border-n-weak rounded-lg text-sm bg-n-alpha-black2 text-n-slate-12 min-w-[150px] cursor-pointer appearance-none focus:outline-none focus:ring-2 focus:ring-woot-500 focus:border-transparent"
        >
          <option v-for="f in channelFilters" :key="f.value" :value="f.value">
            {{ f.label }}
          </option>
        </select>
        <svg
          class="absolute right-3 top-1/2 -translate-y-1/2 w-4 h-4 text-n-slate-10 pointer-events-none"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M19 9l-7 7-7-7"
          />
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
      class="flex flex-col items-center justify-center py-16 text-center text-n-slate-11"
    >
      <span class="i-lucide-file-text w-12 h-12 mb-4 text-n-slate-10" />
      <h3 class="text-lg font-medium mb-2 text-n-slate-12">
        {{ $t('WHATSAPP_TEMPLATES.EMPTY_TITLE') }}
      </h3>
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
        class="bg-white dark:bg-n-solid-2 border border-n-weak rounded-xl p-4 cursor-pointer transition-all hover:border-woot-200 dark:hover:border-woot-700 hover:shadow-sm"
        @click="navigateToEdit(template)"
      >
        <div class="flex justify-between items-start mb-3">
          <div class="flex gap-2">
            <span
              class="text-xs font-medium px-2 py-0.5 rounded uppercase"
              :class="getStatusClass(template.status)"
            >
              {{ template.status }}
            </span>
            <span
              class="text-xs px-2 py-0.5 rounded bg-woot-50 dark:bg-woot-900/30 text-woot-700 dark:text-woot-300"
            >
              {{ template.category }}
            </span>
          </div>
          <span
            v-if="
              template.quality_score &&
              !['UNKNOWN', 'NONE', ''].includes(template.quality_score)
            "
            class="text-xs px-2 py-0.5 rounded"
            :class="[
              template.quality_score === 'GREEN'
                ? 'bg-green-100 dark:bg-green-900/30 text-green-700 dark:text-green-300'
                : template.quality_score === 'YELLOW'
                  ? 'bg-yellow-100 dark:bg-yellow-900/30 text-yellow-700 dark:text-yellow-300'
                  : template.quality_score === 'RED'
                    ? 'bg-red-100 dark:bg-red-900/30 text-red-700 dark:text-red-300'
                    : 'bg-slate-100 dark:bg-slate-800 text-slate-700 dark:text-slate-300',
            ]"
          >
            {{ template.quality_score }}
          </span>
        </div>

        <div class="mb-3">
          <h3 class="font-medium font-mono text-sm mb-1 text-n-slate-12">
            {{ template.name }}
          </h3>
          <div class="flex items-center gap-2 mb-2">
            <span class="text-xs text-n-slate-11">{{
              template.language_name
            }}</span>
            <span
              v-if="template.channel_name"
              class="text-xs px-1.5 py-0.5 bg-n-alpha-black2 text-n-slate-11 rounded"
            >
              {{ template.channel_name }}
            </span>
          </div>
          <p class="text-sm text-n-slate-11 line-clamp-3">
            {{ template.body_text }}
          </p>
        </div>

        <div
          v-if="
            template.rejection_reason &&
            !['NONE', 'none', ''].includes(template.rejection_reason)
          "
          class="flex items-start gap-2 p-2 bg-red-50 dark:bg-red-900/20 rounded mb-3 text-xs text-red-800 dark:text-red-200"
        >
          <span class="i-lucide-alert-triangle w-4 h-4 flex-shrink-0" />
          <span>{{ template.rejection_reason }}</span>
        </div>

        <div
          class="flex justify-between items-center pt-3 border-t border-n-weak"
        >
          <span class="text-xs text-n-slate-11">
            {{
              template.submitted_at
                ? `${$t('WHATSAPP_TEMPLATES.SUBMITTED')} ${new Date(template.submitted_at).toLocaleDateString()}`
                : `${$t('WHATSAPP_TEMPLATES.CREATED')} ${new Date(template.created_at).toLocaleDateString()}`
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
              v-if="template.status === 'APPROVED'"
              icon="i-lucide-copy"
              xs
              slate
              faded
              :title="$t('WHATSAPP_TEMPLATES.DUPLICATE_TO_EDIT')"
              @click="handleDuplicateTemplate(template)"
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
    <div
      v-if="meta.totalPages > 1"
      class="flex justify-center items-center gap-4 mt-8"
    >
      <Button
        :label="$t('WHATSAPP_TEMPLATES.PREVIOUS')"
        slate
        faded
        sm
        :disabled="currentPage <= 1"
        @click="currentPage--"
      />
      <span class="text-sm text-n-slate-11">
        {{
          $t('WHATSAPP_TEMPLATES.PAGE_INFO', {
            current: currentPage,
            total: meta.totalPages,
          })
        }}
      </span>
      <Button
        :label="$t('WHATSAPP_TEMPLATES.NEXT')"
        slate
        faded
        sm
        :disabled="currentPage >= meta.totalPages"
        @click="currentPage++"
      />
    </div>
  </div>
</template>
