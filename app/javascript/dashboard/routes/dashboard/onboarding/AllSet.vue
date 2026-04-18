<script setup>
import { computed } from 'vue';
import { useStore } from 'vuex';
import { useRoute, useRouter } from 'vue-router';
import ConfettiField from './ConfettiField.vue';

const store = useStore();
const route = useRoute();
const router = useRouter();

const user = computed(() => store.getters.getCurrentUser || {});
const firstName = computed(() => {
  const full = (user.value.name || '').trim();
  if (!full) return '';
  return full.split(/\s+/)[0];
});

const brandName = computed(
  () => store.getters['globalConfig/get']?.installationName || 'wasup.co'
);

const brandDisplay = computed(() => {
  const raw = brandName.value;
  if (!raw) return '';
  // Title-case the first character for the welcome headline
  return raw.charAt(0).toUpperCase() + raw.slice(1);
});

const onGoToDashboard = () => {
  const userId = user.value?.id;
  const accountId = route.params.accountId;
  try {
    if (userId && accountId) {
      localStorage.setItem(`cw_onboarding_done_${userId}_${accountId}`, 'true');
    }
  } catch (_e) {
    // ignore
  }
  router.replace(`/app/accounts/${accountId}/dashboard`);
};
</script>

<!-- eslint-disable vue/no-static-inline-styles -->
<!-- eslint-disable vue/no-bare-strings-in-template -->
<template>
  <section class="relative w-full flex-1 flex items-center justify-center">
    <ConfettiField />

    <div
      class="relative z-10 flex flex-col items-center text-center gap-8 max-w-[720px] px-6"
    >
      <h1
        class="font-semibold tracking-tight text-balance text-n-slate-12 text-[40px] leading-[1.08] sm:text-[56px] sm:leading-[1.04]"
      >
        <span class="inline-flex items-center gap-3 flex-wrap justify-center">
          <span class="headline-word" style="animation-delay: 40ms">
            All Set,
          </span>
          <span
            v-if="firstName"
            class="headline-word"
            style="animation-delay: 120ms"
          >
            {{ firstName }}
          </span>
          <span
            class="headline-word inline-block"
            style="animation-delay: 200ms"
            aria-hidden="true"
          >
            🎉
          </span>
        </span>
        <br />
        <span class="headline-word inline-block" style="animation-delay: 280ms">
          {{ $t('ONBOARDING.ALL_SET.WELCOME', { brandName: brandDisplay }) }}
        </span>
      </h1>

      <button
        type="button"
        class="headline-word group relative inline-flex items-center justify-center gap-2 rounded-full bg-n-slate-12 hover:bg-n-slate-11 transition-colors px-7 py-3.5 text-[13px] font-medium text-n-background dark:text-n-slate-1 shadow-sm w-full sm:w-[420px]"
        style="animation-delay: 380ms"
        @click="onGoToDashboard"
      >
        <span>{{ $t('ONBOARDING.ALL_SET.CTA') }}</span>
        <svg
          viewBox="0 0 16 16"
          class="size-3.5 transition-transform duration-200 group-hover:translate-x-0.5"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          stroke-linecap="round"
          stroke-linejoin="round"
          aria-hidden="true"
        >
          <polyline points="6 3 11 8 6 13" />
        </svg>
      </button>
    </div>
  </section>
</template>

<style scoped>
@keyframes headline-rise {
  0% {
    opacity: 0;
    transform: translateY(8px);
  }
  100% {
    opacity: 1;
    transform: translateY(0);
  }
}

.headline-word {
  opacity: 0;
  animation: headline-rise 420ms cubic-bezier(0.22, 1, 0.36, 1) forwards;
}

@media (prefers-reduced-motion: reduce) {
  .headline-word {
    animation: none;
    opacity: 1;
    transform: none;
  }
}
</style>
