<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store.js';

import Button from 'dashboard/components-next/button/Button.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

const emit = defineEmits([
  'close',
  'selectAssistant',
  'createAssistant',
  'deleteAssistant',
]);

const { t } = useI18n();
const route = useRoute();

const assistants = useMapGetter('captainAssistants/getRecords');

const currentAssistantId = computed(() => route.params.assistantId);

const isAssistantActive = assistant => {
  return assistant.id === Number(currentAssistantId.value);
};

const handleAssistantChange = assistant => {
  if (isAssistantActive(assistant)) return;
  emit('selectAssistant', assistant);
};

const openCreateAssistantDialog = () => {
  emit('createAssistant');
  emit('close');
};

const handleDeleteClick = (e, assistant) => {
  e.stopPropagation();
  e.preventDefault();
  emit('deleteAssistant', assistant);
};
</script>

<template>
  <div
    class="pt-5 pb-3 bg-n-alpha-3 backdrop-blur-[100px] outline outline-n-container outline-1 z-50 absolute w-[27.5rem] rounded-xl shadow-md flex flex-col gap-4"
  >
    <div
      class="flex items-center justify-between gap-4 px-6 pb-3 border-b border-n-alpha-2"
    >
      <div class="flex flex-col gap-1">
        <div class="flex items-center gap-2">
          <h2
            class="text-base font-medium cursor-pointer text-n-slate-12 w-fit hover:underline"
          >
            {{ t('CAPTAIN.ASSISTANT_SWITCHER.ASSISTANTS') }}
          </h2>
        </div>
        <p class="text-sm text-n-slate-11">
          {{ t('CAPTAIN.ASSISTANT_SWITCHER.SWITCH_ASSISTANT') }}
        </p>
      </div>
      <Button
        :label="t('CAPTAIN.ASSISTANT_SWITCHER.NEW_ASSISTANT')"
        color="slate"
        icon="i-lucide-plus"
        size="sm"
        type="button"
        class="!bg-n-alpha-2 hover:!bg-n-alpha-3"
        @click="openCreateAssistantDialog"
      />
    </div>
    <div v-if="assistants.length > 0" class="flex flex-col gap-2 px-4">
      <div
        v-for="assistant in assistants"
        :key="assistant.id"
        class="group flex items-center gap-1 rounded-lg hover:bg-n-alpha-2 cursor-pointer"
        @click="handleAssistantChange(assistant)"
      >
        <div class="flex items-center gap-2 flex-1 min-w-0 px-2 py-2">
          <Avatar
            :name="assistant.name"
            :size="20"
            icon-name="i-lucide-bot"
            rounded-full
          />
          <span class="text-sm font-medium truncate text-n-slate-12">
            {{ assistant.name || '' }}
          </span>
        </div>
        <i
          v-if="isAssistantActive(assistant)"
          class="i-lucide-check text-n-teal-10 size-4 shrink-0 mr-1"
        />
        <button
          type="button"
          class="opacity-0 group-hover:opacity-100 p-1 rounded hover:bg-n-alpha-3 shrink-0 mr-1 transition-opacity"
          @click="handleDeleteClick($event, assistant)"
        >
          <i class="i-lucide-trash-2 size-3.5 text-n-ruby-10" />
        </button>
      </div>
    </div>
    <div v-else class="flex flex-col items-center gap-2 px-4 py-3">
      <p class="text-sm text-n-slate-11">
        {{ t('CAPTAIN.ASSISTANT_SWITCHER.EMPTY_LIST') }}
      </p>
    </div>
  </div>
</template>
