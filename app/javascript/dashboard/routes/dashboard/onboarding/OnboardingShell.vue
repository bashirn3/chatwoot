<script setup>
import { computed } from 'vue';
import { useStore } from 'vuex';
import { useRoute, useRouter } from 'vue-router';

const store = useStore();
const route = useRoute();
const router = useRouter();

const brandName = computed(
  () => store.getters['globalConfig/get']?.installationName || 'wasup.co'
);

const showSkip = computed(() => route.meta?.showSkip !== false);

const markComplete = () => {
  const userId = store.getters.getCurrentUser?.id;
  const accountId = route.params.accountId;
  if (!userId || !accountId) return;
  try {
    localStorage.setItem(`cw_onboarding_done_${userId}_${accountId}`, 'true');
  } catch (_e) {
    // localStorage unavailable, fall through
  }
};

const onSkip = () => {
  markComplete();
  router.replace(`/app/accounts/${route.params.accountId}/dashboard`);
};
</script>

<!-- eslint-disable vue/no-static-inline-styles -->
<template>
  <div
    class="h-dvh w-full bg-n-brand/5 dark:bg-n-background text-n-slate-12 relative overflow-hidden flex flex-col antialiased"
  >
    <!-- Atmospheric background: soft conic mesh + grain. Inline styles are
         intentional for dynamic radial gradients / noise patterns that can't
         be expressed as Tailwind utilities. -->
    <div
      aria-hidden="true"
      class="pointer-events-none absolute inset-0 opacity-70 dark:opacity-50"
      style="
        background: radial-gradient(
            600px 400px at 12% -8%,
            rgba(99, 102, 241, 0.18),
            transparent 60%
          ),
          radial-gradient(
            720px 520px at 105% 105%,
            rgba(236, 72, 153, 0.14),
            transparent 60%
          ),
          radial-gradient(
            520px 360px at 95% 5%,
            rgba(16, 185, 129, 0.1),
            transparent 60%
          );
      "
    />
    <div
      aria-hidden="true"
      class="pointer-events-none absolute inset-0 opacity-[0.03] dark:opacity-[0.05] mix-blend-overlay"
      style="
        background-image: radial-gradient(
          circle at 1px 1px,
          currentColor 1px,
          transparent 0
        );
        background-size: 22px 22px;
      "
    />

    <header
      class="flex items-center justify-between px-6 sm:px-10 pt-4 sm:pt-5 relative z-20 shrink-0"
    >
      <div
        class="font-bold text-[14px] tracking-tight lowercase select-none text-n-slate-12"
      >
        {{ brandName }}
      </div>
      <button
        v-if="showSkip"
        type="button"
        class="text-[13px] font-medium text-n-slate-11 hover:text-n-slate-12 transition-colors px-2 py-1 -mr-2"
        @click="onSkip"
      >
        {{ $t('ONBOARDING.SKIP') }}
      </button>
    </header>

    <main
      class="flex-1 min-h-0 flex flex-col items-stretch justify-center px-6 sm:px-10 py-8 sm:py-10 overflow-y-auto relative z-10"
    >
      <router-view v-slot="{ Component }">
        <transition
          enter-active-class="transition duration-300 ease-out"
          enter-from-class="opacity-0 translate-y-2"
          enter-to-class="opacity-100 translate-y-0"
          leave-active-class="transition duration-200 ease-in"
          leave-from-class="opacity-100"
          leave-to-class="opacity-0"
          mode="out-in"
        >
          <component :is="Component" />
        </transition>
      </router-view>
    </main>
  </div>
</template>
