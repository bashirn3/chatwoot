<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';

const store = useStore();
const route = useRoute();
const { t } = useI18n();

const isLoading = ref(true);
const editorUrl = ref('');
const errorMessage = ref('');

const inboxId = computed(() => route.params.inboxId);

const resolveEditorUrl = async () => {
  try {
    const hooks = store.getters['integrations/getIntegration']('router');
    if (!hooks || !hooks.hooks?.length) {
      errorMessage.value = t('BOT_EDITOR.NO_ROUTER_HOOK');
      return;
    }

    const inboxHook = inboxId.value
      ? hooks.hooks.find(h => h.inbox?.id === Number(inboxId.value))
      : hooks.hooks[0];

    if (!inboxHook) {
      errorMessage.value = t('BOT_EDITOR.NO_HOOK_FOR_INBOX');
      return;
    }

    const typebotUrl = inboxHook.settings?.typebot_url;
    const publicId = inboxHook.settings?.public_id;

    if (!typebotUrl || !publicId) {
      errorMessage.value = t('BOT_EDITOR.MISSING_CONFIG');
      return;
    }

    editorUrl.value = `${typebotUrl}/typebots/${publicId}/edit`;
  } catch (error) {
    errorMessage.value = t('BOT_EDITOR.LOAD_ERROR');
  } finally {
    isLoading.value = false;
  }
};

onMounted(async () => {
  await store.dispatch('integrations/get');
  await store.dispatch('inboxes/get');
  resolveEditorUrl();
});
</script>

<template>
  <div class="flex h-full flex-col">
    <BaseSettingsHeader
      :title="$t('BOT_EDITOR.TITLE')"
      :description="$t('BOT_EDITOR.DESCRIPTION')"
      feature-name="bot_editor"
    >
      <template #actions>
        <Button
          v-if="editorUrl"
          icon="i-lucide-external-link"
          :label="$t('BOT_EDITOR.OPEN_EXTERNAL')"
          slate
          faded
          sm
          @click="window.open(editorUrl, '_blank')"
        />
      </template>
    </BaseSettingsHeader>

    <woot-loading-state v-if="isLoading" :message="$t('BOT_EDITOR.LOADING')" />

    <div
      v-else-if="errorMessage"
      class="flex flex-1 flex-col items-center justify-center gap-4 text-n-slate-11"
    >
      <span class="i-lucide-bot h-12 w-12 text-n-slate-10" />
      <p class="text-sm">{{ errorMessage }}</p>
    </div>

    <iframe
      v-else-if="editorUrl"
      :src="editorUrl"
      class="flex-1 border-0"
      allow="clipboard-read; clipboard-write"
      :title="$t('BOT_EDITOR.TITLE')"
    />
  </div>
</template>
