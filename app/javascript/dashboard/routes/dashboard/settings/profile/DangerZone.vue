<script setup>
import { ref, computed } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { clearCookiesOnLogout } from 'dashboard/store/utils/api.js';
import authAPI from 'dashboard/api/auth';
import Button from 'dashboard/components-next/button/Button.vue';

const store = useStore();
const { t } = useI18n();

const currentUser = computed(() => store.getters.getCurrentUser || {});
const currentAccountId = computed(() => store.getters.getCurrentAccountId);
const accounts = computed(() => currentUser.value.accounts || []);
const currentAccount = computed(() =>
  accounts.value.find(a => Number(a.id) === Number(currentAccountId.value))
);

const isSoleAdminOfCurrent = computed(() => {
  // We don't know peers count from client state; backend enforces the
  // real rule. Heuristic: if they are admin of this account AND it's
  // their only account, we assume sole admin and hide the button.
  if (!currentAccount.value) return false;
  const isAdmin = currentAccount.value.role === 'administrator';
  return isAdmin && accounts.value.length === 1;
});

const canLeaveCurrent = computed(
  () => accounts.value.length > 1 && !!currentAccount.value
);

const showLeaveDialog = ref(false);
const showDeleteDialog = ref(false);
const deleteConfirmText = ref('');
const isSubmitting = ref(false);

const expectedDeleteWord = computed(() =>
  t('PROFILE_SETTINGS.FORM.DANGER_ZONE.DELETE.CONFIRM_WORD')
);

const canConfirmDelete = computed(
  () =>
    deleteConfirmText.value.trim().toUpperCase() ===
    expectedDeleteWord.value.toUpperCase()
);

const closeDialogs = () => {
  showLeaveDialog.value = false;
  showDeleteDialog.value = false;
  deleteConfirmText.value = '';
};

const leaveAccount = async () => {
  if (!currentAccountId.value || isSubmitting.value) return;
  isSubmitting.value = true;
  try {
    await authAPI.leaveAccount({ accountId: currentAccountId.value });
    useAlert(t('PROFILE_SETTINGS.FORM.DANGER_ZONE.LEAVE.SUCCESS'));
    // Route to the remaining account; if none, fall out to /app/login.
    const remaining = accounts.value.find(
      a => Number(a.id) !== Number(currentAccountId.value)
    );
    if (remaining) {
      window.location.href = `/app/accounts/${remaining.id}/dashboard`;
    } else {
      await authAPI.logout();
      window.location.href = '/app/login';
    }
  } catch (err) {
    useAlert(
      err?.response?.data?.error ||
        t('PROFILE_SETTINGS.FORM.DANGER_ZONE.LEAVE.ERROR')
    );
  } finally {
    isSubmitting.value = false;
  }
};

const deleteSelf = async () => {
  if (!canConfirmDelete.value || isSubmitting.value) return;
  isSubmitting.value = true;
  try {
    await authAPI.deleteSelf();
    clearCookiesOnLogout();
    // Hard-redirect to login with a friendly marker so the login page
    // could (optionally) flash a "Your account was deleted" banner.
    window.location.href = '/app/login?deleted=1';
  } catch (err) {
    useAlert(
      err?.response?.data?.error ||
        t('PROFILE_SETTINGS.FORM.DANGER_ZONE.DELETE.ERROR')
    );
    isSubmitting.value = false;
  }
};
</script>

<template>
  <section
    class="mt-8 flex flex-col gap-4 rounded-xl border border-n-ruby-8/60 dark:border-n-ruby-8/50 bg-n-ruby-9/5 dark:bg-n-ruby-9/10 p-6"
  >
    <div class="flex items-start gap-3">
      <span
        aria-hidden="true"
        class="size-8 shrink-0 rounded-full bg-n-ruby-9/15 text-n-ruby-11 inline-flex items-center justify-center"
      >
        <svg
          viewBox="0 0 24 24"
          class="size-4"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          stroke-linecap="round"
          stroke-linejoin="round"
          aria-hidden="true"
        >
          <path
            d="M10.29 3.86 1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0zM12 9v4M12 17h.01"
          />
        </svg>
      </span>
      <div>
        <h3 class="text-[15px] font-semibold text-n-slate-12">
          {{ $t('PROFILE_SETTINGS.FORM.DANGER_ZONE.TITLE') }}
        </h3>
        <p class="text-[13px] text-n-slate-11 mt-1 max-w-xl">
          {{ $t('PROFILE_SETTINGS.FORM.DANGER_ZONE.SUBTITLE') }}
        </p>
      </div>
    </div>

    <!-- Leave current organisation -->
    <div
      v-if="canLeaveCurrent"
      class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3 py-3 border-t border-n-ruby-8/30"
    >
      <div>
        <p class="text-[13.5px] font-medium text-n-slate-12">
          {{ $t('PROFILE_SETTINGS.FORM.DANGER_ZONE.LEAVE.HEADING') }}
        </p>
        <p class="text-[12.5px] text-n-slate-11">
          {{
            $t('PROFILE_SETTINGS.FORM.DANGER_ZONE.LEAVE.DESCRIPTION', {
              orgName: currentAccount?.name || '',
            })
          }}
        </p>
      </div>
      <Button
        variant="faded"
        color="ruby"
        size="sm"
        :label="$t('PROFILE_SETTINGS.FORM.DANGER_ZONE.LEAVE.BUTTON')"
        @click="showLeaveDialog = true"
      />
    </div>

    <div
      v-else-if="isSoleAdminOfCurrent"
      class="py-3 border-t border-n-ruby-8/30 text-[12.5px] text-n-slate-11"
    >
      {{ $t('PROFILE_SETTINGS.FORM.DANGER_ZONE.LEAVE.SOLE_ADMIN_HINT') }}
    </div>

    <!-- Delete account permanently -->
    <div
      class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3 py-3 border-t border-n-ruby-8/30"
    >
      <div>
        <p class="text-[13.5px] font-medium text-n-slate-12">
          {{ $t('PROFILE_SETTINGS.FORM.DANGER_ZONE.DELETE.HEADING') }}
        </p>
        <p class="text-[12.5px] text-n-slate-11 max-w-xl">
          {{ $t('PROFILE_SETTINGS.FORM.DANGER_ZONE.DELETE.DESCRIPTION') }}
        </p>
      </div>
      <Button
        variant="solid"
        color="ruby"
        size="sm"
        :label="$t('PROFILE_SETTINGS.FORM.DANGER_ZONE.DELETE.BUTTON')"
        @click="showDeleteDialog = true"
      />
    </div>

    <!-- Leave confirmation -->
    <woot-modal
      v-model:show="showLeaveDialog"
      :on-close="closeDialogs"
      size="medium"
    >
      <div class="flex flex-col gap-4 p-6">
        <h3 class="text-[17px] font-semibold text-n-slate-12">
          {{
            $t('PROFILE_SETTINGS.FORM.DANGER_ZONE.LEAVE.CONFIRM_TITLE', {
              orgName: currentAccount?.name || '',
            })
          }}
        </h3>
        <p class="text-[13.5px] text-n-slate-11">
          {{ $t('PROFILE_SETTINGS.FORM.DANGER_ZONE.LEAVE.CONFIRM_BODY') }}
        </p>
        <div class="flex justify-end gap-2 pt-2">
          <Button
            variant="ghost"
            color="slate"
            size="md"
            :label="$t('PROFILE_SETTINGS.FORM.DANGER_ZONE.CANCEL')"
            @click="closeDialogs"
          />
          <Button
            variant="solid"
            color="ruby"
            size="md"
            :is-loading="isSubmitting"
            :label="$t('PROFILE_SETTINGS.FORM.DANGER_ZONE.LEAVE.BUTTON')"
            @click="leaveAccount"
          />
        </div>
      </div>
    </woot-modal>

    <!-- Delete confirmation -->
    <woot-modal
      v-model:show="showDeleteDialog"
      :on-close="closeDialogs"
      size="medium"
    >
      <div class="flex flex-col gap-4 p-6">
        <h3 class="text-[17px] font-semibold text-n-slate-12">
          {{ $t('PROFILE_SETTINGS.FORM.DANGER_ZONE.DELETE.CONFIRM_TITLE') }}
        </h3>
        <p class="text-[13.5px] text-n-slate-11 text-pretty">
          {{ $t('PROFILE_SETTINGS.FORM.DANGER_ZONE.DELETE.CONFIRM_BODY') }}
        </p>
        <label class="flex flex-col gap-1">
          <span class="text-[12px] font-medium text-n-slate-11">
            {{
              $t('PROFILE_SETTINGS.FORM.DANGER_ZONE.DELETE.CONFIRM_PROMPT', {
                word: expectedDeleteWord,
              })
            }}
          </span>
          <input
            v-model="deleteConfirmText"
            type="text"
            class="px-3 py-2 rounded-lg border border-n-weak bg-n-alpha-1 focus:outline-none focus:ring-2 focus:ring-n-ruby-8 text-n-slate-12 font-mono text-[13px]"
            :placeholder="expectedDeleteWord"
            autocomplete="off"
          />
        </label>
        <div class="flex justify-end gap-2 pt-2">
          <Button
            variant="ghost"
            color="slate"
            size="md"
            :label="$t('PROFILE_SETTINGS.FORM.DANGER_ZONE.CANCEL')"
            @click="closeDialogs"
          />
          <Button
            variant="solid"
            color="ruby"
            size="md"
            :disabled="!canConfirmDelete"
            :is-loading="isSubmitting"
            :label="
              $t('PROFILE_SETTINGS.FORM.DANGER_ZONE.DELETE.CONFIRM_BUTTON')
            "
            @click="deleteSelf"
          />
        </div>
      </div>
    </woot-modal>
  </section>
</template>
