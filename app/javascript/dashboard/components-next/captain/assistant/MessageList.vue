<script setup>
import { useI18n } from 'vue-i18n';
import { ref, watch, nextTick } from 'vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';

const props = defineProps({
  messages: {
    type: Array,
    required: true,
  },
  isLoading: {
    type: Boolean,
    default: false,
  },
});

const messageContainer = ref(null);

const { t } = useI18n();
const { formatMessage } = useMessageFormatter();

const isUserMessage = sender => sender === 'user';

const getMessageAlignment = sender =>
  isUserMessage(sender) ? 'justify-end' : 'justify-start';

const getMessageDirection = sender =>
  isUserMessage(sender) ? 'flex-row-reverse' : 'flex-row';

const getAvatarName = sender =>
  isUserMessage(sender)
    ? t('CAPTAIN.PLAYGROUND.USER')
    : t('CAPTAIN.PLAYGROUND.ASSISTANT');

const getMessageStyle = sender =>
  isUserMessage(sender)
    ? 'bg-n-solid-blue text-n-slate-12 rounded-br-sm rounded-bl-xl rounded-t-xl'
    : 'bg-n-solid-iris text-n-slate-12 rounded-bl-sm rounded-br-xl rounded-t-xl';

const scrollToBottom = async () => {
  await nextTick();
  if (messageContainer.value) {
    messageContainer.value.scrollTop = messageContainer.value.scrollHeight;
  }
};

watch(() => props.messages.length, scrollToBottom);
</script>

<template>
  <div
    ref="messageContainer"
    class="min-h-0 overflow-y-auto px-5 py-5 space-y-4"
  >
    <div
      v-for="(message, index) in messages"
      :key="index"
      class="flex"
      :class="getMessageAlignment(message.sender)"
    >
      <div
        class="flex items-end gap-2 max-w-[90%] md:max-w-[75%]"
        :class="getMessageDirection(message.sender)"
      >
        <Avatar
          :name="getAvatarName(message.sender)"
          rounded-full
          :size="24"
          class="shrink-0"
        />
        <div
          class="px-3.5 py-2.5 text-sm leading-relaxed [overflow-wrap:break-word]"
          :class="getMessageStyle(message.sender)"
        >
          <div v-html="formatMessage(message.content)" />
        </div>
      </div>
    </div>
    <div v-if="isLoading" class="flex justify-start">
      <div class="flex items-end gap-2">
        <Avatar :name="getAvatarName('assistant')" rounded-full :size="24" />
        <div
          class="rounded-bl-sm rounded-br-xl rounded-t-xl px-3.5 py-2.5 bg-n-solid-iris text-n-slate-12"
        >
          <div class="flex gap-1 items-center h-4">
            <div class="size-1.5 rounded-full bg-n-iris-10 animate-bounce" />
            <div
              class="size-1.5 rounded-full bg-n-iris-10 animate-bounce [animation-delay:0.15s]"
            />
            <div
              class="size-1.5 rounded-full bg-n-iris-10 animate-bounce [animation-delay:0.3s]"
            />
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
