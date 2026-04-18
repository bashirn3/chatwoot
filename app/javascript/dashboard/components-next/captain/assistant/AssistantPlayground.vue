<script setup>
import { nextTick, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import NextButton from 'dashboard/components-next/button/Button.vue';
import MessageList from './MessageList.vue';
import CaptainAssistant from 'dashboard/api/captain/assistant';

const { assistantId } = defineProps({
  assistantId: {
    type: Number,
    required: true,
  },
});

const { t } = useI18n();
const messages = ref([]);
const newMessage = ref('');
const isLoading = ref(false);
const textareaRef = ref(null);

const formatMessagesForApi = () =>
  messages.value.map(m => ({ role: m.sender, content: m.content }));

const resetConversation = () => {
  messages.value = [];
  newMessage.value = '';
  // eslint-disable-next-line no-use-before-define
  nextTick(() => autoGrow());
};

const autoGrow = () => {
  const el = textareaRef.value;
  if (!el) return;
  el.style.height = 'auto';
  el.style.height = `${Math.min(el.scrollHeight, 160)}px`;
};

watch(
  () => assistantId,
  (n, o) => {
    if (o && n !== o) resetConversation();
  }
);

watch(newMessage, () => nextTick(() => autoGrow()));

const sendMessage = async () => {
  const content = newMessage.value.trim();
  if (!content || isLoading.value) return;

  messages.value.push({
    content,
    sender: 'user',
    timestamp: new Date().toISOString(),
  });
  newMessage.value = '';
  nextTick(() => autoGrow());

  try {
    isLoading.value = true;
    const { data } = await CaptainAssistant.playground({
      assistantId,
      messageContent: content,
      messageHistory: formatMessagesForApi(),
    });
    messages.value.push({
      content: data.response,
      sender: 'assistant',
      timestamp: new Date().toISOString(),
    });
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('Error getting assistant response:', error);
    messages.value.push({
      content: t('CAPTAIN.PLAYGROUND.ERROR_MESSAGE') || 'Something went wrong.',
      sender: 'assistant',
      timestamp: new Date().toISOString(),
      isError: true,
    });
  } finally {
    isLoading.value = false;
  }
};

const onEnter = e => {
  if (e.shiftKey) return;
  e.preventDefault();
  sendMessage();
};

const usePrompt = text => {
  newMessage.value = text;
  nextTick(() => {
    textareaRef.value?.focus();
    autoGrow();
  });
};
</script>

<template>
  <div
    class="flex flex-col min-h-0 rounded-xl border border-n-weak bg-n-solid-1 overflow-hidden"
  >
    <header
      class="flex items-center justify-between gap-3 px-5 h-12 border-b border-n-weak shrink-0"
    >
      <div class="flex items-center gap-2">
        <span
          class="size-2 rounded-full bg-emerald-500/80"
          aria-hidden="true"
        />
        <h3 class="text-sm font-medium text-n-slate-12 text-balance">
          {{ t('CAPTAIN.PLAYGROUND.HEADER') }}
        </h3>
      </div>
      <NextButton
        ghost
        xs
        slate
        icon="i-lucide-rotate-ccw"
        :aria-label="t('CAPTAIN.PLAYGROUND.RESET')"
        :disabled="!messages.length && !newMessage"
        @click="resetConversation"
      />
    </header>

    <div class="flex-1 min-h-0 flex flex-col">
      <MessageList
        v-if="messages.length || isLoading"
        :messages="messages"
        :is-loading="isLoading"
        class="flex-1 min-h-0"
      />
      <div
        v-else
        class="flex-1 min-h-0 flex flex-col items-center justify-center px-8 text-center gap-5"
      >
        <div
          class="size-12 rounded-full flex items-center justify-center bg-n-alpha-2 text-n-slate-11"
          aria-hidden="true"
        >
          <span class="i-lucide-sparkles size-5" />
        </div>
        <div class="space-y-1.5 max-w-sm">
          <h4 class="text-base font-medium text-n-slate-12 text-balance">
            {{ t('CAPTAIN.PLAYGROUND.EMPTY_TITLE') }}
          </h4>
          <p class="text-sm text-n-slate-11 text-pretty">
            {{ t('CAPTAIN.PLAYGROUND.EMPTY_SUBTITLE') }}
          </p>
        </div>
        <div class="flex flex-wrap items-center justify-center gap-2">
          <button
            v-for="key in ['GREET', 'CAPABILITIES', 'ESCALATE']"
            :key="key"
            type="button"
            class="px-3 h-8 rounded-full text-xs font-medium text-n-slate-12 bg-n-alpha-2 hover:bg-n-alpha-3 cursor-pointer transition-colors duration-150 ease-out"
            @click="usePrompt(t(`CAPTAIN.PLAYGROUND.PROMPT_HINTS.${key}`))"
          >
            {{ t(`CAPTAIN.PLAYGROUND.PROMPT_HINTS.${key}`) }}
          </button>
        </div>
      </div>
    </div>

    <footer class="shrink-0 border-t border-n-weak px-4 py-3 bg-n-solid-1">
      <div
        class="flex items-end gap-2 rounded-xl border border-n-weak bg-n-background px-3 py-2 focus-within:border-n-slate-8 transition-colors duration-150 ease-out"
      >
        <textarea
          ref="textareaRef"
          v-model="newMessage"
          rows="1"
          :placeholder="t('CAPTAIN.PLAYGROUND.MESSAGE_PLACEHOLDER')"
          class="flex-1 resize-none bg-transparent border-none focus:outline-none text-sm leading-6 text-n-slate-12 placeholder:text-n-slate-10 max-h-40 py-1"
          :aria-label="t('CAPTAIN.PLAYGROUND.MESSAGE_PLACEHOLDER')"
          @keydown.enter="onEnter"
        />
        <NextButton
          solid
          sm
          icon="i-lucide-arrow-up"
          :disabled="!newMessage.trim() || isLoading"
          :is-loading="isLoading"
          :aria-label="t('CAPTAIN.PLAYGROUND.SEND')"
          class="shrink-0 !size-8 !rounded-lg"
          @click="sendMessage"
        />
      </div>
      <p class="mt-2 text-[11px] text-center text-n-slate-10">
        {{ t('CAPTAIN.PLAYGROUND.CREDIT_NOTE') }}
      </p>
    </footer>
  </div>
</template>
