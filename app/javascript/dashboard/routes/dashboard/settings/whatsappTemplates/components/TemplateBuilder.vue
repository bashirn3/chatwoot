<script setup>
import { ref, reactive, computed, watch, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import WhatsAppPreview from './WhatsAppPreview.vue';

const props = defineProps({
  template: {
    type: Object,
    default: null,
  },
  mode: {
    type: String,
    default: 'create',
  },
});

const emit = defineEmits(['submit', 'cancel']);

const store = useStore();
const { t } = useI18n();

const formData = reactive({
  name: '',
  language: 'en',
  category: 'UTILITY',
  header_type: null,
  header_content: '',
  body_text: '',
  footer_text: '',
  buttons: [],
  location_latitude: '',
  location_longitude: '',
  location_name: '',
  location_address: '',
});

const sampleValues = reactive({
  header: {},
  body: {},
});

const isLoading = ref(false);
const showSampleModal = ref(false);
const showVariableHelp = ref(false);

const predefinedVariables = [
  { name: 'first_name', description: "Contact's first name", example: 'John' },
  { name: 'last_name', description: "Contact's last name", example: 'Doe' },
  {
    name: 'full_name',
    description: "Contact's full name",
    example: 'John Doe',
  },
  {
    name: 'email',
    description: "Contact's email address",
    example: 'john@example.com',
  },
  {
    name: 'phone',
    description: "Contact's phone number",
    example: '+1234567890',
  },
  {
    name: 'company',
    description: "Contact's company name",
    example: 'Acme Inc',
  },
  {
    name: 'order_id',
    description: 'Order or reference ID',
    example: 'ORD-12345',
  },
  { name: 'amount', description: 'Amount or price', example: '$99.99' },
  { name: 'date', description: 'Date value', example: 'Jan 15, 2026' },
  { name: 'time', description: 'Time value', example: '2:30 PM' },
  { name: 'link', description: 'URL or link', example: 'https://example.com' },
  {
    name: 'code',
    description: 'Verification or coupon code',
    example: 'ABC123',
  },
];

const languages = computed(
  () => store.getters['whatsappTemplates/getLanguages'] || { en: 'English' }
);
const samples = computed(
  () => store.getters['whatsappTemplates/getSamples'] || {}
);

const categories = [
  { value: 'UTILITY', labelKey: 'WHATSAPP_TEMPLATES.CATEGORIES.UTILITY' },
  { value: 'MARKETING', labelKey: 'WHATSAPP_TEMPLATES.CATEGORIES.MARKETING' },
  {
    value: 'AUTHENTICATION',
    labelKey: 'WHATSAPP_TEMPLATES.CATEGORIES.AUTHENTICATION',
  },
];

const headerTypes = [
  { value: null, labelKey: 'WHATSAPP_TEMPLATES.HEADER_TYPES.NONE' },
  { value: 'TEXT', labelKey: 'WHATSAPP_TEMPLATES.HEADER_TYPES.TEXT' },
  { value: 'IMAGE', labelKey: 'WHATSAPP_TEMPLATES.HEADER_TYPES.IMAGE' },
  { value: 'VIDEO', labelKey: 'WHATSAPP_TEMPLATES.HEADER_TYPES.VIDEO' },
  { value: 'DOCUMENT', labelKey: 'WHATSAPP_TEMPLATES.HEADER_TYPES.DOCUMENT' },
  { value: 'LOCATION', labelKey: 'WHATSAPP_TEMPLATES.HEADER_TYPES.LOCATION' },
];

const buttonTypes = [
  {
    value: 'QUICK_REPLY',
    labelKey: 'WHATSAPP_TEMPLATES.BUTTON_TYPES.QUICK_REPLY',
  },
  { value: 'URL', labelKey: 'WHATSAPP_TEMPLATES.BUTTON_TYPES.URL' },
  {
    value: 'PHONE_NUMBER',
    labelKey: 'WHATSAPP_TEMPLATES.BUTTON_TYPES.PHONE_NUMBER',
  },
];

const bodyCharCount = computed(() => formData.body_text?.length || 0);
const bodyVariableCount = computed(() => {
  const matches = formData.body_text?.match(/\{\{(\d+)\}\}/g);
  return matches ? matches.length : 0;
});

const canAddButton = computed(() => formData.buttons.length < 3);

const isValid = computed(() => {
  if (!formData.name || !formData.body_text) return false;
  if (formData.name.length < 1 || formData.name.length > 512) return false;
  if (formData.body_text.length > 1024) return false;
  return true;
});

const isMediaHeader = computed(() => {
  return ['IMAGE', 'VIDEO', 'DOCUMENT'].includes(formData.header_type);
});

const formatVarLabel = num => {
  return '{{' + num + '}}';
};

const loadTemplate = () => {
  if (props.template) {
    Object.assign(formData, {
      name: props.template.name || '',
      language: props.template.language || 'en',
      category: props.template.category || 'UTILITY',
      header_type: props.template.header_type || null,
      header_content: props.template.header_content || '',
      body_text: props.template.body_text || '',
      footer_text: props.template.footer_text || '',
      buttons: props.template.buttons || [],
      location_latitude: props.template.location_latitude || '',
      location_longitude: props.template.location_longitude || '',
      location_name: props.template.location_name || '',
      location_address: props.template.location_address || '',
    });

    if (props.template.body_params) {
      props.template.body_params.forEach(param => {
        sampleValues.body[param.index] = param.example;
      });
    }
  }
};

const loadSample = sampleKey => {
  const sample = samples.value[sampleKey];
  if (sample) {
    Object.assign(formData, {
      name: sample.name,
      language: sample.language,
      category: sample.category,
      header_type: sample.header_type || null,
      header_content: sample.header_content || '',
      body_text: sample.body_text,
      footer_text: sample.footer_text || '',
      buttons: sample.buttons || [],
    });
    showSampleModal.value = false;
    useAlert(t('WHATSAPP_TEMPLATES.SAMPLE_LOADED'));
  }
};

const insertVariable = field => {
  const currentText = formData[field] || '';
  const existingVars = currentText.match(/\{\{(\d+)\}\}/g) || [];
  const nextVar = existingVars.length + 1;
  formData[field] = currentText + `{{${nextVar}}}`;

  if (field === 'body_text') {
    sampleValues.body[nextVar] = `Example ${nextVar}`;
  } else if (field === 'header_content') {
    sampleValues.header[nextVar] = `Example ${nextVar}`;
  }
};

const insertPredefinedVariable = (variable, field = 'body_text') => {
  const currentText = formData[field] || '';
  const existingVars = currentText.match(/\{\{(\d+)\}\}/g) || [];
  const nextVar = existingVars.length + 1;
  formData[field] = currentText + `{{${nextVar}}}`;

  if (field === 'body_text') {
    sampleValues.body[nextVar] = variable.example;
  } else if (field === 'header_content') {
    sampleValues.header[nextVar] = variable.example;
  }
};

const addButton = type => {
  if (!canAddButton.value) return;

  const newButton = { type, text: '' };

  if (type === 'URL') {
    newButton.url = '';
  } else if (type === 'PHONE_NUMBER') {
    newButton.phone_number = '';
  }

  formData.buttons.push(newButton);
};

const removeButton = index => {
  formData.buttons.splice(index, 1);
};

const handleSubmit = async () => {
  if (!isValid.value) {
    useAlert(t('WHATSAPP_TEMPLATES.VALIDATION_ERROR'));
    return;
  }

  isLoading.value = true;

  try {
    const bodyParams = Object.entries(sampleValues.body).map(
      ([index, example]) => ({
        index: parseInt(index, 10),
        example,
      })
    );

    const headerParams = Object.entries(sampleValues.header).map(
      ([index, example]) => ({
        index: parseInt(index, 10),
        example,
      })
    );

    const templateData = {
      ...formData,
      body_params: bodyParams,
      header_params: headerParams,
    };

    emit('submit', templateData);
  } catch (error) {
    useAlert(error.message || t('WHATSAPP_TEMPLATES.SAVE_ERROR'));
  } finally {
    isLoading.value = false;
  }
};

const handleCancel = () => {
  emit('cancel');
};

watch(() => props.template, loadTemplate, { immediate: true });

onMounted(async () => {
  try {
    await store.dispatch('whatsappTemplates/fetchLanguages');
    await store.dispatch('whatsappTemplates/fetchSamples');
  } catch (e) {
    // noop
  }
});
</script>

<template>
  <div class="flex gap-6 h-full">
    <!-- Left Side: Form -->
    <div class="flex-1 overflow-y-auto overflow-x-visible pr-2">
      <!-- Header Actions -->
      <div class="flex justify-between items-center mb-6">
        <h2 class="text-xl font-semibold text-n-slate-12">
          {{
            mode === 'create'
              ? $t('WHATSAPP_TEMPLATES.CREATE_TITLE')
              : $t('WHATSAPP_TEMPLATES.EDIT_TITLE')
          }}
        </h2>
        <Button
          :label="$t('WHATSAPP_TEMPLATES.LOAD_SAMPLE')"
          slate
          faded
          sm
          @click="showSampleModal = true"
        />
      </div>

      <!-- Basic Info -->
      <div class="mb-6">
        <label class="block text-sm font-medium mb-2 text-n-slate-12">
          {{ $t('WHATSAPP_TEMPLATES.NAME') }}
          <span class="text-n-ruby-9">*</span>
        </label>
        <input
          v-model="formData.name"
          type="text"
          class="w-full px-3 py-2 border border-n-weak rounded-lg text-sm bg-n-alpha-black2 text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus:ring-2 focus:ring-woot-500 focus:border-transparent"
          :placeholder="$t('WHATSAPP_TEMPLATES.NAME_PLACEHOLDER')"
          :disabled="mode === 'edit' && template?.status !== 'DRAFT'"
        />
        <p class="text-xs text-n-slate-11 mt-1">
          {{ $t('WHATSAPP_TEMPLATES.NAME_HELP') }}
        </p>
      </div>

      <div class="grid grid-cols-2 gap-4 mb-6">
        <div>
          <label class="block text-sm font-medium mb-2 text-n-slate-12">
            {{ $t('WHATSAPP_TEMPLATES.LANGUAGE') }}
          </label>
          <div class="relative">
            <select
              v-model="formData.language"
              class="w-full h-10 px-3 pr-10 border border-n-weak rounded-lg text-sm bg-n-alpha-black2 text-n-slate-12 cursor-pointer appearance-none focus:outline-none focus:ring-2 focus:ring-woot-500 focus:border-transparent"
            >
              <option
                v-for="(label, code) in languages"
                :key="code"
                :value="code"
              >
                {{ label }}
              </option>
            </select>
            <svg
              class="absolute right-3 top-1/2 -translate-y-1/2 w-4 h-4 text-n-slate-10 pointer-events-none"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M19 9l-7 7-7-7"
              />
            </svg>
          </div>
        </div>

        <div>
          <label class="block text-sm font-medium mb-2 text-n-slate-12">
            {{ $t('WHATSAPP_TEMPLATES.CATEGORY') }}
          </label>
          <div class="relative">
            <select
              v-model="formData.category"
              class="w-full h-10 px-3 pr-10 border border-n-weak rounded-lg text-sm bg-n-alpha-black2 text-n-slate-12 cursor-pointer appearance-none focus:outline-none focus:ring-2 focus:ring-woot-500 focus:border-transparent"
            >
              <option
                v-for="cat in categories"
                :key="cat.value"
                :value="cat.value"
              >
                {{ $t(cat.labelKey) }}
              </option>
            </select>
            <svg
              class="absolute right-3 top-1/2 -translate-y-1/2 w-4 h-4 text-n-slate-10 pointer-events-none"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M19 9l-7 7-7-7"
              />
            </svg>
          </div>
        </div>
      </div>

      <!-- Header Section -->
      <div class="border-t border-n-weak pt-6 mb-6">
        <h3 class="font-medium mb-4 text-n-slate-12">
          {{ $t('WHATSAPP_TEMPLATES.HEADER') }}
        </h3>

        <div class="flex flex-wrap gap-2 mb-4">
          <button
            v-for="ht in headerTypes"
            :key="ht.value"
            class="px-3 py-1.5 text-sm rounded-lg border transition-colors"
            :class="[
              formData.header_type === ht.value
                ? 'bg-woot-500 text-white border-woot-500'
                : 'bg-n-alpha-black2 border-n-weak text-n-slate-12 hover:border-woot-300',
            ]"
            @click="formData.header_type = ht.value"
          >
            {{ $t(ht.labelKey) }}
          </button>
        </div>

        <!-- Text Header -->
        <div v-if="formData.header_type === 'TEXT'" class="mb-4">
          <div class="flex gap-2">
            <input
              v-model="formData.header_content"
              type="text"
              class="flex-1 px-3 py-2 border border-n-weak rounded-lg text-sm bg-n-alpha-black2 text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus:ring-2 focus:ring-woot-500 focus:border-transparent"
              :placeholder="$t('WHATSAPP_TEMPLATES.HEADER_TEXT_PLACEHOLDER')"
              maxlength="60"
            />
            <Button
              :label="$t('WHATSAPP_TEMPLATES.ADD_VARIABLE')"
              slate
              faded
              sm
              @click="insertVariable('header_content')"
            />
          </div>
          <p class="text-xs text-n-slate-11 mt-1">
            {{
              $t('WHATSAPP_TEMPLATES.CHAR_COUNT', {
                current: formData.header_content?.length || 0,
                max: 60,
              })
            }}
          </p>
        </div>

        <!-- Media Headers -->
        <div v-if="isMediaHeader" class="mb-4">
          <div class="p-4 bg-n-alpha-black2 rounded-lg border border-n-weak">
            <div class="flex items-center gap-3 mb-3">
              <div
                class="w-10 h-10 rounded-lg bg-n-alpha-black2 border border-n-weak flex items-center justify-center"
              >
                <svg
                  v-if="formData.header_type === 'IMAGE'"
                  class="w-5 h-5 text-n-slate-10"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"
                  />
                </svg>
                <svg
                  v-else-if="formData.header_type === 'VIDEO'"
                  class="w-5 h-5 text-n-slate-10"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M15 10l4.553-2.276A1 1 0 0121 8.618v6.764a1 1 0 01-1.447.894L15 14M5 18h8a2 2 0 002-2V8a2 2 0 00-2-2H5a2 2 0 00-2 2v8a2 2 0 002 2z"
                  />
                </svg>
                <svg
                  v-else-if="formData.header_type === 'DOCUMENT'"
                  class="w-5 h-5 text-n-slate-10"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"
                  />
                </svg>
              </div>
              <div>
                <p class="font-medium text-sm text-n-slate-12">
                  {{
                    $t('WHATSAPP_TEMPLATES.MEDIA_HEADER_TITLE', {
                      type: formData.header_type,
                    })
                  }}
                </p>
                <p class="text-xs text-n-slate-11">
                  {{ $t('WHATSAPP_TEMPLATES.MEDIA_SAMPLE_URL') }}
                </p>
              </div>
            </div>
            <input
              v-model="formData.header_content"
              type="url"
              class="w-full px-3 py-2 border border-n-weak rounded-lg text-sm bg-n-alpha-black2 text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus:ring-2 focus:ring-woot-500 focus:border-transparent"
              :placeholder="
                formData.header_type === 'IMAGE'
                  ? 'https://example.com/image.jpg'
                  : formData.header_type === 'VIDEO'
                    ? 'https://example.com/video.mp4'
                    : 'https://example.com/document.pdf'
              "
            />
            <p class="text-xs text-n-slate-11 mt-2">
              {{ $t('WHATSAPP_TEMPLATES.MEDIA_SAMPLE_NOTE') }}
            </p>
          </div>
        </div>

        <!-- Location Header -->
        <div v-if="formData.header_type === 'LOCATION'" class="space-y-4">
          <div class="grid grid-cols-2 gap-4">
            <div>
              <label class="block text-sm mb-1 text-n-slate-12">{{
                $t('WHATSAPP_TEMPLATES.LOCATION.LATITUDE')
              }}</label>
              <input
                v-model="formData.location_latitude"
                type="text"
                class="w-full px-3 py-2 border border-n-weak rounded-lg text-sm bg-n-alpha-black2 text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus:ring-2 focus:ring-woot-500 focus:border-transparent"
                :placeholder="
                  $t('WHATSAPP_TEMPLATES.LOCATION.LATITUDE_PLACEHOLDER')
                "
              />
            </div>
            <div>
              <label class="block text-sm mb-1 text-n-slate-12">{{
                $t('WHATSAPP_TEMPLATES.LOCATION.LONGITUDE')
              }}</label>
              <input
                v-model="formData.location_longitude"
                type="text"
                class="w-full px-3 py-2 border border-n-weak rounded-lg text-sm bg-n-alpha-black2 text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus:ring-2 focus:ring-woot-500 focus:border-transparent"
                :placeholder="
                  $t('WHATSAPP_TEMPLATES.LOCATION.LONGITUDE_PLACEHOLDER')
                "
              />
            </div>
          </div>
          <div>
            <label class="block text-sm mb-1 text-n-slate-12">{{
              $t('WHATSAPP_TEMPLATES.LOCATION.NAME')
            }}</label>
            <input
              v-model="formData.location_name"
              type="text"
              class="w-full px-3 py-2 border border-n-weak rounded-lg text-sm bg-n-alpha-black2 text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus:ring-2 focus:ring-woot-500 focus:border-transparent"
              :placeholder="$t('WHATSAPP_TEMPLATES.LOCATION.NAME_PLACEHOLDER')"
            />
          </div>
          <div>
            <label class="block text-sm mb-1 text-n-slate-12">{{
              $t('WHATSAPP_TEMPLATES.LOCATION.ADDRESS')
            }}</label>
            <input
              v-model="formData.location_address"
              type="text"
              class="w-full px-3 py-2 border border-n-weak rounded-lg text-sm bg-n-alpha-black2 text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus:ring-2 focus:ring-woot-500 focus:border-transparent"
              :placeholder="
                $t('WHATSAPP_TEMPLATES.LOCATION.ADDRESS_PLACEHOLDER')
              "
            />
          </div>
        </div>
      </div>

      <!-- Body Section -->
      <div class="border-t border-n-weak pt-6 mb-6">
        <div class="flex justify-between items-center mb-4">
          <h3 class="font-medium text-n-slate-12">
            {{ $t('WHATSAPP_TEMPLATES.BODY') }}
            <span class="text-n-ruby-9">*</span>
          </h3>
          <button
            class="text-sm text-woot-500 hover:text-woot-600"
            @click="showVariableHelp = !showVariableHelp"
          >
            {{ $t('WHATSAPP_TEMPLATES.VARIABLE_HELP_LINK') }}
          </button>
        </div>

        <!-- Variable Help Panel -->
        <div
          v-if="showVariableHelp"
          class="mb-4 p-4 bg-n-blue-2 dark:bg-n-blue-2 border border-n-blue-5 dark:border-n-blue-5 rounded-lg"
        >
          <h4 class="font-medium text-n-blue-11 mb-2">
            {{ $t('WHATSAPP_TEMPLATES.VARIABLE_HELP_TITLE') }}
          </h4>
          <p class="text-sm text-n-blue-11 mb-3">
            {{ $t('WHATSAPP_TEMPLATES.VARIABLE_HELP_DESC') }}
          </p>
          <p class="text-sm text-n-blue-11 mb-3">
            {{ $t('WHATSAPP_TEMPLATES.VARIABLE_HELP_EXAMPLE') }}
          </p>
          <p class="text-sm text-n-blue-11 mb-2">
            {{ $t('WHATSAPP_TEMPLATES.VARIABLE_HELP_INSERT') }}
          </p>
          <div class="flex flex-wrap gap-2">
            <button
              v-for="variable in predefinedVariables"
              :key="variable.name"
              class="px-2 py-1 text-xs bg-n-blue-3 dark:bg-n-blue-3 text-n-blue-11 rounded hover:bg-n-blue-4 dark:hover:bg-n-blue-4 transition-colors"
              :title="variable.description"
              @click="insertPredefinedVariable(variable)"
            >
              {{ variable.name }}
            </button>
          </div>
        </div>

        <textarea
          v-model="formData.body_text"
          class="w-full px-3 py-2 border border-n-weak rounded-lg text-sm resize-none bg-n-alpha-black2 text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus:ring-2 focus:ring-woot-500 focus:border-transparent"
          :placeholder="$t('WHATSAPP_TEMPLATES.BODY_PLACEHOLDER')"
          rows="6"
          maxlength="1024"
        />
        <div class="flex justify-between items-center mt-2">
          <Button
            :label="$t('WHATSAPP_TEMPLATES.ADD_BODY_VARIABLE')"
            slate
            faded
            sm
            @click="insertVariable('body_text')"
          />
          <span
            class="text-xs"
            :class="[
              bodyCharCount > 900 ? 'text-n-amber-10' : 'text-n-slate-11',
            ]"
          >
            {{
              $t('WHATSAPP_TEMPLATES.CHAR_COUNT', {
                current: bodyCharCount,
                max: 1024,
              })
            }}
          </span>
        </div>

        <!-- Variable Examples -->
        <div
          v-if="bodyVariableCount > 0"
          class="mt-4 p-4 bg-n-alpha-black2 rounded-lg border border-n-weak"
        >
          <label class="block text-sm font-medium mb-2 text-n-slate-12">
            {{ $t('WHATSAPP_TEMPLATES.VARIABLE_EXAMPLES') }}
          </label>
          <p class="text-xs text-n-slate-11 mb-4">
            {{ $t('WHATSAPP_TEMPLATES.VARIABLE_EXAMPLES_DESC') }}
          </p>
          <div class="space-y-3">
            <div
              v-for="i in bodyVariableCount"
              :key="i"
              class="flex items-center gap-3"
            >
              <span
                class="text-xs font-mono bg-woot-100 dark:bg-woot-900/30 text-woot-700 dark:text-woot-300 px-2 py-1.5 rounded font-semibold min-w-[50px] text-center border border-woot-200 dark:border-woot-700"
              >
                {{ formatVarLabel(i) }}
              </span>
              <input
                v-model="sampleValues.body[i]"
                type="text"
                class="flex-1 min-w-[150px] h-9 px-3 border border-n-weak rounded-lg text-sm bg-n-alpha-black2 text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus:ring-2 focus:ring-woot-500 focus:border-transparent"
                :placeholder="
                  $t('WHATSAPP_TEMPLATES.VARIABLE_EXAMPLE_PLACEHOLDER', {
                    index: i,
                  })
                "
              />
              <div class="relative">
                <select
                  class="h-9 px-3 pr-8 border border-n-weak rounded-lg text-sm bg-n-alpha-black2 text-n-slate-12 cursor-pointer appearance-none min-w-[140px] focus:outline-none focus:ring-2 focus:ring-woot-500 focus:border-transparent"
                  @change="
                    e => {
                      if (e.target.value) {
                        sampleValues.body[i] =
                          predefinedVariables.find(
                            v => v.name === e.target.value
                          )?.example || '';
                      }
                    }
                  "
                >
                  <option value="">
                    {{ $t('WHATSAPP_TEMPLATES.QUICK_FILL') }}
                  </option>
                  <option
                    v-for="v in predefinedVariables"
                    :key="v.name"
                    :value="v.name"
                  >
                    {{ `${v.name} (${v.example})` }}
                  </option>
                </select>
                <svg
                  class="absolute right-2 top-1/2 -translate-y-1/2 w-4 h-4 text-n-slate-10 pointer-events-none"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M19 9l-7 7-7-7"
                  />
                </svg>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Footer Section -->
      <div class="border-t border-n-weak pt-6 mb-6">
        <h3 class="font-medium mb-4 text-n-slate-12">
          {{ $t('WHATSAPP_TEMPLATES.FOOTER') }}
        </h3>
        <input
          v-model="formData.footer_text"
          type="text"
          class="w-full px-3 py-2 border border-n-weak rounded-lg text-sm bg-n-alpha-black2 text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus:ring-2 focus:ring-woot-500 focus:border-transparent"
          :placeholder="$t('WHATSAPP_TEMPLATES.FOOTER_PLACEHOLDER')"
          maxlength="60"
        />
        <p class="text-xs text-n-slate-11 mt-1">
          {{
            $t('WHATSAPP_TEMPLATES.CHAR_COUNT', {
              current: formData.footer_text?.length || 0,
              max: 60,
            })
          }}
        </p>
      </div>

      <!-- Buttons Section -->
      <div class="border-t border-n-weak pt-6 mb-6">
        <h3 class="font-medium mb-4 text-n-slate-12">
          {{ $t('WHATSAPP_TEMPLATES.BUTTONS') }}
        </h3>

        <div v-if="canAddButton" class="flex flex-wrap gap-2 mb-4">
          <Button
            v-for="bt in buttonTypes"
            :key="bt.value"
            :label="'+ ' + $t(bt.labelKey)"
            slate
            faded
            sm
            @click="addButton(bt.value)"
          />
        </div>
        <p v-else class="text-xs text-n-slate-11 mb-4">
          {{ $t('WHATSAPP_TEMPLATES.MAX_BUTTONS') }}
        </p>

        <div v-if="formData.buttons.length > 0" class="space-y-4">
          <div
            v-for="(button, index) in formData.buttons"
            :key="index"
            class="p-4 border border-n-weak rounded-lg"
          >
            <div class="flex justify-between items-center mb-3">
              <span class="text-sm font-medium text-n-slate-12">{{
                button.type.replace('_', ' ')
              }}</span>
              <button
                class="text-n-ruby-9 hover:text-n-ruby-10"
                @click="removeButton(index)"
              >
                <svg
                  class="w-4 h-4"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M6 18L18 6M6 6l12 12"
                  />
                </svg>
              </button>
            </div>

            <input
              v-model="button.text"
              type="text"
              class="w-full px-3 py-2 border border-n-weak rounded-lg text-sm mb-2 bg-n-alpha-black2 text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus:ring-2 focus:ring-woot-500 focus:border-transparent"
              :placeholder="$t('WHATSAPP_TEMPLATES.BUTTON_TEXT_PLACEHOLDER')"
              maxlength="25"
            />

            <input
              v-if="button.type === 'URL'"
              v-model="button.url"
              type="text"
              class="w-full px-3 py-2 border border-n-weak rounded-lg text-sm bg-n-alpha-black2 text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus:ring-2 focus:ring-woot-500 focus:border-transparent"
              :placeholder="$t('WHATSAPP_TEMPLATES.URL_PLACEHOLDER')"
            />

            <input
              v-if="button.type === 'PHONE_NUMBER'"
              v-model="button.phone_number"
              type="text"
              class="w-full px-3 py-2 border border-n-weak rounded-lg text-sm bg-n-alpha-black2 text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus:ring-2 focus:ring-woot-500 focus:border-transparent"
              :placeholder="$t('WHATSAPP_TEMPLATES.PHONE_PLACEHOLDER')"
            />
          </div>
        </div>
      </div>

      <!-- Actions -->
      <div class="flex justify-end gap-3 pt-6 border-t border-n-weak">
        <Button
          :label="$t('WHATSAPP_TEMPLATES.CANCEL')"
          slate
          faded
          @click="handleCancel"
        />
        <Button
          :label="
            mode === 'create'
              ? $t('WHATSAPP_TEMPLATES.CREATE')
              : $t('WHATSAPP_TEMPLATES.SAVE')
          "
          :is-loading="isLoading"
          :disabled="!isValid"
          @click="handleSubmit"
        />
      </div>
    </div>

    <!-- Right Side: Preview -->
    <div class="w-[380px] flex-shrink-0">
      <div class="sticky top-0">
        <WhatsAppPreview :template="formData" :sample-values="sampleValues" />
      </div>
    </div>

    <!-- Sample Modal -->
    <div
      v-if="showSampleModal"
      class="fixed inset-0 bg-black/50 flex items-center justify-center z-50"
      @click.self="showSampleModal = false"
    >
      <div
        class="bg-white dark:bg-n-solid-3 rounded-xl p-6 max-w-md w-full mx-4"
      >
        <h3 class="text-lg font-semibold mb-4 text-n-slate-12">
          {{ $t('WHATSAPP_TEMPLATES.SAMPLE_TEMPLATES') }}
        </h3>

        <div class="space-y-2 max-h-60 overflow-auto">
          <button
            v-for="(sample, key) in samples"
            :key="key"
            class="w-full text-left p-3 border border-n-weak rounded-lg hover:bg-n-alpha-black2 transition-colors"
            @click="loadSample(key)"
          >
            <p class="font-medium text-n-slate-12">{{ sample.name }}</p>
            <p class="text-sm text-n-slate-11">{{ sample.category }}</p>
          </button>
          <p
            v-if="Object.keys(samples).length === 0"
            class="text-sm text-n-slate-11 text-center py-4"
          >
            {{ $t('WHATSAPP_TEMPLATES.NO_SAMPLES') }}
          </p>
        </div>

        <div class="flex justify-end mt-4">
          <Button
            :label="$t('WHATSAPP_TEMPLATES.CLOSE')"
            slate
            faded
            @click="showSampleModal = false"
          />
        </div>
      </div>
    </div>
  </div>
</template>
