<script setup>
import { computed } from 'vue';
import { useRoute } from 'vue-router';
import PageLayout from 'dashboard/components-next/captain/PageLayout.vue';
import AssistantPlayground from 'dashboard/components-next/captain/assistant/AssistantPlayground.vue';

const route = useRoute();
const assistantId = computed(() => Number(route.params.assistantId));
</script>

<template>
  <PageLayout
    show-assistant-switcher
    :show-pagination-footer="false"
    :show-know-more="false"
    class="h-full"
  >
    <template #body>
      <div class="flex flex-col h-full min-h-0">
        <AssistantPlayground
          :assistant-id="assistantId"
          class="flex-1 min-h-0"
        />
      </div>
    </template>
  </PageLayout>
</template>
