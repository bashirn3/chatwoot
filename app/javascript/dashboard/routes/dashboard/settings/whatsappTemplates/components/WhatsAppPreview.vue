<script setup>
import { computed } from 'vue';

const props = defineProps({
  template: {
    type: Object,
    required: true,
  },
  sampleValues: {
    type: Object,
    default: () => ({}),
  },
});

const previewHeader = computed(() => {
  if (!props.template.header_type || props.template.header_type === 'TEXT') {
    if (!props.template.header_content) return null;
    let text = props.template.header_content;
    Object.entries(props.sampleValues.header || {}).forEach(([key, value]) => {
      text = text.replace(`{{${key}}}`, value || `[Var ${key}]`);
    });
    return { type: 'text', content: text };
  }
  return {
    type: props.template.header_type?.toLowerCase(),
    content: props.template.header_content,
  };
});

const previewBody = computed(() => {
  let text = props.template.body_text || '';
  Object.entries(props.sampleValues.body || {}).forEach(([key, value]) => {
    text = text.replace(`{{${key}}}`, value || `[Var ${key}]`);
  });
  return text;
});

const previewFooter = computed(() => props.template.footer_text);

const previewButtons = computed(() => props.template.buttons || []);

const currentTime = computed(() => {
  const now = new Date();
  return now.toLocaleTimeString('en-US', {
    hour: 'numeric',
    minute: '2-digit',
    hour12: true,
  });
});

const formatBody = text => {
  if (!text) return '';
  return text
    .replace(/\n/g, '<br>')
    .replace(/\*([^*]+)\*/g, '<strong>$1</strong>')
    .replace(/_([^_]+)_/g, '<em>$1</em>');
};
</script>

<template>
  <div
    class="min-w-[320px] max-w-[360px] overflow-hidden rounded-xl bg-[#f0f2f5]"
  >
    <div class="bg-[#075e54] px-4 py-3 text-sm font-medium text-white">
      {{ $t('WHATSAPP_TEMPLATES.PREVIEW') }}
    </div>

    <div class="p-4">
      <div class="min-h-[200px] rounded-lg bg-[#e5ddd5] p-4">
        <div
          class="relative max-w-[280px] rounded-[7.5px] rounded-tl-none bg-white shadow-[0_1px_0.5px_rgba(0,0,0,0.13)] break-words"
        >
          <!-- Header -->
          <div v-if="previewHeader">
            <template v-if="previewHeader.type === 'text'">
              <div
                class="px-2.5 pt-1.5 text-[15px] font-semibold leading-[19px] text-black/75"
              >
                {{ previewHeader.content }}
              </div>
            </template>
            <template v-else-if="previewHeader.type === 'image'">
              <div class="p-0.5">
                <div
                  class="flex min-h-[100px] flex-col items-center justify-center gap-2 rounded bg-[#ccd0d5] text-[#666]"
                >
                  <span class="i-lucide-image h-8 w-8" />
                  <span>{{ $t('WHATSAPP_TEMPLATES.HEADER_TYPES.IMAGE') }}</span>
                </div>
              </div>
            </template>
            <template v-else-if="previewHeader.type === 'video'">
              <div class="p-0.5">
                <div
                  class="flex min-h-[100px] flex-col items-center justify-center gap-2 rounded bg-[#ccd0d5] text-[#666]"
                >
                  <span class="i-lucide-video h-8 w-8" />
                  <span>{{ $t('WHATSAPP_TEMPLATES.HEADER_TYPES.VIDEO') }}</span>
                </div>
              </div>
            </template>
            <template v-else-if="previewHeader.type === 'document'">
              <div class="p-0.5">
                <div
                  class="flex min-h-[100px] flex-col items-center justify-center gap-2 rounded bg-[#ccd0d5] text-[#666]"
                >
                  <span class="i-lucide-file-text h-8 w-8" />
                  <span>{{
                    $t('WHATSAPP_TEMPLATES.HEADER_TYPES.DOCUMENT')
                  }}</span>
                </div>
              </div>
            </template>
            <template v-else-if="previewHeader.type === 'location'">
              <div class="p-0.5">
                <div
                  class="flex min-h-[100px] flex-col items-center justify-center gap-2 rounded bg-[#ccd0d5] text-[#666]"
                >
                  <span class="i-lucide-map-pin h-8 w-8" />
                  <span>{{
                    template.location_name ||
                    $t('WHATSAPP_TEMPLATES.HEADER_TYPES.LOCATION')
                  }}</span>
                </div>
              </div>
            </template>
          </div>

          <!-- Body -->
          <div class="px-2.5 pb-1.5 pt-[7px]">
            <p
              class="m-0 whitespace-pre-wrap text-sm leading-[19px] text-[#262626]"
              v-html="formatBody(previewBody)"
            />
          </div>

          <!-- Footer -->
          <div
            v-if="previewFooter"
            class="px-2.5 pb-2 text-[13px] leading-[17px] text-black/45"
          >
            {{ previewFooter }}
          </div>

          <!-- Timestamp -->
          <div class="absolute bottom-1 right-2 text-[11px] text-black/40">
            {{ currentTime }}
          </div>

          <!-- Buttons -->
          <div
            v-if="previewButtons.length > 0"
            class="border-t border-[#dadde1]"
          >
            <div
              v-for="(button, index) in previewButtons"
              :key="index"
              class="flex cursor-pointer items-center justify-center gap-2 border-b border-[#dadde1] px-3 py-3 text-sm text-[#00a5f4] last:border-b-0 hover:bg-[#f5f5f5]"
            >
              <span
                v-if="button.type === 'URL'"
                class="i-lucide-external-link h-3.5 w-3.5"
              />
              <span
                v-else-if="button.type === 'PHONE_NUMBER'"
                class="i-lucide-phone h-3.5 w-3.5"
              />
              <span
                v-else-if="button.type === 'COPY_CODE'"
                class="i-lucide-copy h-3.5 w-3.5"
              />
              <span>{{
                button.text || $t('WHATSAPP_TEMPLATES.BUTTON_DEFAULT')
              }}</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
