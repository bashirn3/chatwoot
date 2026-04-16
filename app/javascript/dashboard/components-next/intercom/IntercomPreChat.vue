<script setup>
import { ref, computed, onMounted, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();

const isOpen = ref(false);
const step = ref(0);
const name = ref('');
const email = ref('');
const issueDescription = ref('');
const duration = ref('');
const screenshotNote = ref('');
const fileInput = ref(null);
const attachedFiles = ref([]);
const isSubmitting = ref(false);

const durationOptions = [
  { label: 'INTERCOM_PRECHAT.DURATION.JUST_NOW', value: 'just_now' },
  { label: 'INTERCOM_PRECHAT.DURATION.HOURS', value: 'hours' },
  { label: 'INTERCOM_PRECHAT.DURATION.DAYS', value: 'days' },
  { label: 'INTERCOM_PRECHAT.DURATION.WEEKS_PLUS', value: 'weeks_plus' },
];

const steps = [
  { title: 'INTERCOM_PRECHAT.STEPS.NAME', field: 'name' },
  { title: 'INTERCOM_PRECHAT.STEPS.EMAIL', field: 'email' },
  { title: 'INTERCOM_PRECHAT.STEPS.ISSUE', field: 'issue' },
  { title: 'INTERCOM_PRECHAT.STEPS.DURATION', field: 'duration' },
  { title: 'INTERCOM_PRECHAT.STEPS.SCREENSHOTS', field: 'screenshots' },
];

const currentStep = computed(() => steps[step.value]);
const progress = computed(() => ((step.value + 1) / steps.length) * 100);

const canProceed = computed(() => {
  switch (step.value) {
    case 0:
      return name.value.trim().length > 0;
    case 1:
      return email.value.trim().length > 0 && email.value.includes('@');
    case 2:
      return issueDescription.value.trim().length > 0;
    case 3:
      return duration.value.length > 0;
    case 4:
      return true;
    default:
      return false;
  }
});

function handleFileSelect(event) {
  const files = Array.from(event.target.files);
  files.forEach(file => {
    const reader = new FileReader();
    reader.onload = e => {
      attachedFiles.value.push({
        name: file.name,
        size: file.size,
        preview: file.type.startsWith('image/') ? e.target.result : null,
      });
    };
    reader.readAsDataURL(file);
  });
}

function removeFile(index) {
  attachedFiles.value.splice(index, 1);
}

function resetForm() {
  step.value = 0;
  name.value = '';
  email.value = '';
  issueDescription.value = '';
  duration.value = '';
  screenshotNote.value = '';
  attachedFiles.value = [];
}

function submitToIntercom() {
  isSubmitting.value = true;

  const durationLabel = durationOptions.find(o => o.value === duration.value);
  const durationText = durationLabel ? t(durationLabel.label) : 'Unknown';

  const screenshotInfo =
    attachedFiles.value.length > 0
      ? `\n📎 ${attachedFiles.value.length} screenshot(s): ${attachedFiles.value.map(f => f.name).join(', ')}`
      : '';
  const noteInfo = screenshotNote.value
    ? `\n📎 Note: ${screenshotNote.value}`
    : '';

  const firstMessage = [
    `Issue: ${issueDescription.value}`,
    `Duration: ${durationText}`,
    screenshotInfo,
    noteInfo,
  ]
    .filter(Boolean)
    .join('\n');

  window.Intercom('update', {
    name: name.value,
    email: email.value,
    issue_description: issueDescription.value,
    issue_duration: durationText,
    has_screenshots: attachedFiles.value.length > 0,
  });

  window.Intercom('showNewMessage', firstMessage);

  setTimeout(() => {
    isSubmitting.value = false;
    isOpen.value = false;
    resetForm();
  }, 500);
}

function nextStep() {
  if (step.value < steps.length - 1) {
    step.value += 1;
    nextTick(() => {
      const input = document.querySelector('.prechat-input-focus');
      if (input) input.focus();
    });
  } else {
    submitToIntercom();
  }
}

function prevStep() {
  if (step.value > 0) step.value -= 1;
}

function handleKeydown(e) {
  if (e.key === 'Enter' && !e.shiftKey && canProceed.value) {
    e.preventDefault();
    nextStep();
  }
  if (e.key === 'Escape') {
    isOpen.value = false;
  }
}

function openForm() {
  isOpen.value = true;
  nextTick(() => {
    const input = document.querySelector('.prechat-input-focus');
    if (input) input.focus();
  });
}

function prefillFromUser(user) {
  if (user?.name) name.value = user.name;
  if (user?.email) email.value = user.email;
  if (name.value && email.value) step.value = 2;
  else if (name.value) step.value = 1;
}

function interceptIntercomLauncher() {
  window.Intercom('onShow', () => {
    if (!isOpen.value) {
      window.Intercom('hide');
      openForm();
    }
  });
}

onMounted(() => {
  const checkIntercom = setInterval(() => {
    if (window.Intercom && typeof window.Intercom === 'function') {
      interceptIntercomLauncher();
      clearInterval(checkIntercom);
    }
  }, 500);

  setTimeout(() => clearInterval(checkIntercom), 15000);
});

defineExpose({ openForm, prefillFromUser });
</script>

<template>
  <Teleport to="body">
    <transition name="prechat-overlay">
      <div
        v-if="isOpen"
        class="fixed inset-0 z-[99998] flex items-end justify-end p-4 sm:p-6"
        @keydown="handleKeydown"
      >
        <div
          class="fixed inset-0 bg-black/40 backdrop-blur-sm"
          @click="isOpen = false"
        />

        <transition name="prechat-panel" appear>
          <div
            v-if="isOpen"
            class="relative z-[99999] w-full max-w-sm max-h-[520px] rounded-2xl bg-n-background shadow-2xl border border-n-weak overflow-hidden flex flex-col"
          >
            <div class="flex items-center justify-between px-5 pt-5 pb-3">
              <div class="flex items-center gap-2">
                <div
                  class="flex items-center justify-center w-8 h-8 rounded-full bg-n-brand text-white text-sm font-semibold"
                >
                  {{ t('INTERCOM_PRECHAT.BRAND_INITIAL') }}
                </div>
                <span class="text-sm font-medium text-n-slate-12">
                  {{ t('INTERCOM_PRECHAT.TITLE') }}
                </span>
              </div>
              <button
                class="flex items-center justify-center w-7 h-7 rounded-lg text-n-slate-11 hover:bg-n-alpha-2 transition-colors"
                @click="isOpen = false"
              >
                <svg
                  width="14"
                  height="14"
                  viewBox="0 0 14 14"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="2"
                  stroke-linecap="round"
                >
                  <path d="M1 1l12 12M13 1L1 13" />
                </svg>
              </button>
            </div>

            <div class="px-5 pb-3">
              <div class="h-1 w-full rounded-full bg-n-alpha-2 overflow-hidden">
                <div
                  class="h-full rounded-full bg-n-brand transition-all duration-300 ease-out"
                  :style="{ width: `${progress}%` }"
                />
              </div>
              <div class="flex justify-between mt-1.5">
                <span class="text-[11px] text-n-slate-10">
                  {{
                    t('INTERCOM_PRECHAT.STEP_PROGRESS', {
                      current: step + 1,
                      total: steps.length,
                    })
                  }}
                </span>
                <span class="text-[11px] text-n-slate-10">
                  {{ Math.round(progress) }}%
                </span>
              </div>
            </div>

            <div class="flex-1 px-5 pb-4 overflow-y-auto">
              <transition name="step-slide" mode="out-in">
                <div :key="step" class="flex flex-col gap-3">
                  <h3
                    class="text-base font-medium text-n-slate-12 leading-snug"
                  >
                    {{ t(currentStep.title) }}
                  </h3>

                  <template v-if="step === 0">
                    <input
                      v-model="name"
                      type="text"
                      :placeholder="t('INTERCOM_PRECHAT.PLACEHOLDERS.NAME')"
                      class="prechat-input-focus w-full rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2.5 text-sm text-n-slate-12 placeholder:text-n-slate-9 outline-none focus:border-n-brand focus:ring-1 focus:ring-n-brand transition-colors"
                    />
                  </template>

                  <template v-if="step === 1">
                    <input
                      v-model="email"
                      type="email"
                      :placeholder="t('INTERCOM_PRECHAT.PLACEHOLDERS.EMAIL')"
                      class="prechat-input-focus w-full rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2.5 text-sm text-n-slate-12 placeholder:text-n-slate-9 outline-none focus:border-n-brand focus:ring-1 focus:ring-n-brand transition-colors"
                    />
                  </template>

                  <template v-if="step === 2">
                    <textarea
                      v-model="issueDescription"
                      :placeholder="t('INTERCOM_PRECHAT.PLACEHOLDERS.ISSUE')"
                      rows="4"
                      class="prechat-input-focus w-full rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2.5 text-sm text-n-slate-12 placeholder:text-n-slate-9 outline-none focus:border-n-brand focus:ring-1 focus:ring-n-brand transition-colors resize-none"
                    />
                  </template>

                  <template v-if="step === 3">
                    <div class="flex flex-col gap-2">
                      <button
                        v-for="opt in durationOptions"
                        :key="opt.value"
                        type="button"
                        class="w-full text-left px-3.5 py-2.5 rounded-lg border text-sm transition-all duration-150"
                        :class="
                          duration === opt.value
                            ? 'border-n-brand bg-n-brand/10 text-n-slate-12 font-medium'
                            : 'border-n-weak bg-n-alpha-1 text-n-slate-11 hover:border-n-slate-7'
                        "
                        @click="duration = opt.value"
                      >
                        {{ t(opt.label) }}
                      </button>
                    </div>
                  </template>

                  <template v-if="step === 4">
                    <p class="text-sm text-n-slate-10">
                      {{ t('INTERCOM_PRECHAT.SCREENSHOT_HINT') }}
                    </p>
                    <div
                      class="flex flex-col items-center justify-center gap-2 rounded-lg border-2 border-dashed border-n-weak p-5 cursor-pointer hover:border-n-slate-7 transition-colors"
                      @click="fileInput?.click()"
                    >
                      <svg
                        width="24"
                        height="24"
                        viewBox="0 0 24 24"
                        fill="none"
                        stroke="currentColor"
                        stroke-width="1.5"
                        class="text-n-slate-10"
                      >
                        <path
                          d="M21 15v4a2 2 0 01-2 2H5a2 2 0 01-2-2v-4M17 8l-5-5-5 5M12 3v12"
                          stroke-linecap="round"
                          stroke-linejoin="round"
                        />
                      </svg>
                      <span class="text-xs text-n-slate-10">
                        {{ t('INTERCOM_PRECHAT.UPLOAD_LABEL') }}
                      </span>
                    </div>
                    <input
                      ref="fileInput"
                      type="file"
                      accept="image/*"
                      multiple
                      class="hidden"
                      @change="handleFileSelect"
                    />
                    <div
                      v-if="attachedFiles.length"
                      class="flex flex-wrap gap-2"
                    >
                      <div
                        v-for="(file, idx) in attachedFiles"
                        :key="idx"
                        class="flex items-center gap-1.5 rounded-md bg-n-alpha-2 px-2 py-1 text-xs text-n-slate-11"
                      >
                        <img
                          v-if="file.preview"
                          :src="file.preview"
                          class="h-6 w-6 rounded object-cover"
                        />
                        <span class="max-w-[120px] truncate">
                          {{ file.name }}
                        </span>
                        <button
                          :aria-label="t('INTERCOM_PRECHAT.REMOVE_FILE')"
                          type="button"
                          class="ml-0.5 text-n-slate-9 hover:text-n-slate-12"
                          @click.stop="removeFile(idx)"
                        >
                          <svg
                            width="10"
                            height="10"
                            viewBox="0 0 10 10"
                            fill="none"
                            stroke="currentColor"
                            stroke-width="1.5"
                            stroke-linecap="round"
                          >
                            <path d="M1 1l8 8M9 1l-8 8" />
                          </svg>
                        </button>
                      </div>
                    </div>
                    <textarea
                      v-model="screenshotNote"
                      :placeholder="
                        t('INTERCOM_PRECHAT.PLACEHOLDERS.SCREENSHOT_NOTE')
                      "
                      rows="2"
                      class="w-full rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-12 placeholder:text-n-slate-9 outline-none focus:border-n-brand focus:ring-1 focus:ring-n-brand transition-colors resize-none"
                    />
                  </template>
                </div>
              </transition>
            </div>

            <div
              class="flex items-center gap-2 px-5 py-4 border-t border-n-weak"
            >
              <button
                v-if="step > 0"
                type="button"
                class="flex-1 rounded-lg border border-n-weak bg-n-alpha-1 px-4 py-2 text-sm font-medium text-n-slate-11 hover:bg-n-alpha-2 transition-colors"
                @click="prevStep"
              >
                {{ t('INTERCOM_PRECHAT.BACK') }}
              </button>
              <button
                type="button"
                class="flex-1 rounded-lg px-4 py-2 text-sm font-medium text-white transition-all duration-150"
                :class="
                  canProceed
                    ? 'bg-n-brand hover:opacity-90 shadow-sm'
                    : 'bg-n-slate-8 cursor-not-allowed opacity-50'
                "
                :disabled="!canProceed || isSubmitting"
                @click="nextStep"
              >
                <span
                  v-if="isSubmitting"
                  class="flex items-center justify-center gap-2"
                >
                  <svg class="animate-spin h-4 w-4" viewBox="0 0 24 24">
                    <circle
                      class="opacity-25"
                      cx="12"
                      cy="12"
                      r="10"
                      stroke="currentColor"
                      stroke-width="4"
                      fill="none"
                    />
                    <path
                      class="opacity-75"
                      fill="currentColor"
                      d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"
                    />
                  </svg>
                  {{ t('INTERCOM_PRECHAT.SENDING') }}
                </span>
                <span v-else>
                  {{
                    step === steps.length - 1
                      ? t('INTERCOM_PRECHAT.START_CHAT')
                      : t('INTERCOM_PRECHAT.CONTINUE')
                  }}
                </span>
              </button>
            </div>
          </div>
        </transition>
      </div>
    </transition>
  </Teleport>
</template>

<style scoped>
.prechat-overlay-enter-active,
.prechat-overlay-leave-active {
  transition: opacity 0.2s ease;
}
.prechat-overlay-enter-from,
.prechat-overlay-leave-to {
  opacity: 0;
}

.prechat-panel-enter-active {
  transition:
    opacity 0.25s ease,
    transform 0.25s cubic-bezier(0.22, 1, 0.36, 1);
}
.prechat-panel-leave-active {
  transition:
    opacity 0.15s ease,
    transform 0.15s ease-in;
}
.prechat-panel-enter-from {
  opacity: 0;
  transform: translateY(16px) scale(0.97);
}
.prechat-panel-leave-to {
  opacity: 0;
  transform: translateY(8px) scale(0.98);
}

.step-slide-enter-active {
  transition:
    opacity 0.18s ease,
    transform 0.18s ease-out;
}
.step-slide-leave-active {
  transition:
    opacity 0.12s ease,
    transform 0.12s ease-in;
}
.step-slide-enter-from {
  opacity: 0;
  transform: translateX(12px);
}
.step-slide-leave-to {
  opacity: 0;
  transform: translateX(-12px);
}
</style>
