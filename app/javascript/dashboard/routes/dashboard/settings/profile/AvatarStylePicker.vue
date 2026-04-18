<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  DICEBEAR_STYLES,
  dicebearAvatarUrl,
} from 'dashboard/components-next/avatar/dicebearStyles';

const props = defineProps({
  name: { type: String, default: '' },
  currentStyle: { type: String, default: 'adventurer' },
});

const emit = defineEmits(['select']);

const { t } = useI18n();

const styles = computed(() =>
  DICEBEAR_STYLES.map(style => ({
    key: style,
    label: style
      .split('-')
      .map(w => w.charAt(0).toUpperCase() + w.slice(1))
      .join(' '),
    url: dicebearAvatarUrl(props.name || 'User', style),
  }))
);
</script>

<template>
  <div class="flex flex-col gap-2">
    <span class="text-sm font-medium text-n-slate-12">
      {{ t('PROFILE_SETTINGS.FORM.AVATAR_STYLE.TITLE') }}
    </span>
    <p class="text-xs text-n-slate-10">
      {{ t('PROFILE_SETTINGS.FORM.AVATAR_STYLE.NOTE') }}
    </p>
    <div class="flex flex-wrap gap-2 mt-1">
      <button
        v-for="style in styles"
        :key="style.key"
        type="button"
        class="flex flex-col items-center gap-1 p-1.5 rounded-xl transition-all duration-150 reset-base"
        :class="
          currentStyle === style.key
            ? 'ring-2 ring-woot-500 bg-n-alpha-2'
            : 'hover:bg-n-alpha-1'
        "
        :title="style.label"
        @click="emit('select', style.key)"
      >
        <img :src="style.url" :alt="style.label" class="size-10 rounded-full" />
        <span class="text-[10px] text-n-slate-11 truncate max-w-[60px]">
          {{ style.label }}
        </span>
      </button>
    </div>
  </div>
</template>
