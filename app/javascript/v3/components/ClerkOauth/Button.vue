<script>
import Icon from 'dashboard/components-next/icon/Icon.vue';

export default {
  components: {
    Icon,
  },
  methods: {
    handleClerkLogin() {
      this.$router.push('/app/auth/clerk');
    },
  },
};
</script>

<template>
  <div class="flex flex-col">
    <button
      type="button"
      class="inline-flex justify-center w-full px-4 py-3 bg-n-background dark:bg-n-solid-3 items-center rounded-md shadow-sm ring-1 ring-inset ring-n-container dark:ring-n-container focus:outline-offset-0 hover:bg-n-alpha-2 dark:hover:bg-n-alpha-2"
      @click="handleClerkLogin"
    >
      <Icon icon="i-lucide-shield-check" class="size-5 text-n-slate-11" />
      <span class="ml-2 text-base font-medium text-n-slate-12">
        {{ $t('LOGIN.CLERK.LABEL') }}
      </span>
    </button>
  </div>
</template>
