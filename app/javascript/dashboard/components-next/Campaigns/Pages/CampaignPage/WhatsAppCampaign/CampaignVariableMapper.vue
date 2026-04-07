<script setup>
/**
 * Campaign-specific template variable mapper.
 * For each template variable ({{1}}, {{2}}, etc.), lets the user either:
 *   - Pick a contact field (name, first_name, email, custom attributes)
 *   - Type a static value
 *
 * Selected contact fields are stored as Liquid syntax (e.g. {{contact.first_name}})
 * which the backend resolves per-contact at send time.
 *
 * Exposes the same interface as WhatsAppTemplateParser (processedParams, renderedTemplate, v$)
 * so the parent form needs minimal changes.
 */
import { ref, computed, onMounted, watch } from 'vue';
import { useVuelidate } from '@vuelidate/core';
import { requiredIf } from '@vuelidate/validators';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';

import Input from 'dashboard/components-next/input/Input.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import {
  buildTemplateParameters,
  allKeysRequired,
  replaceTemplateVariables,
  DEFAULT_LANGUAGE,
  DEFAULT_CATEGORY,
  COMPONENT_TYPES,
  MEDIA_FORMATS,
  findComponentByType,
} from 'dashboard/helper/templateHelper';

const props = defineProps({
  template: {
    type: Object,
    default: () => ({}),
    validator: value => {
      if (!value || typeof value !== 'object') return false;
      if (!value.components || !Array.isArray(value.components)) return false;
      return true;
    },
  },
});

const { t } = useI18n();
const store = useStore();

const processedParams = ref({});
// Tracks which variables use field mapping vs static text
// key = variable key (e.g. "1"), value = 'field' | 'static'
const variableModes = ref({});

// Load custom attribute definitions
onMounted(() => {
  store.dispatch('attributes/get');
});

const contactAttributes = computed(
  () => store.getters['attributes/getContactAttributes'] || []
);

const STANDARD_FIELDS = [
  { value: '{{contact.name}}', label: 'Full Name' },
  { value: '{{contact.first_name}}', label: 'First Name' },
  { value: '{{contact.last_name}}', label: 'Last Name' },
  { value: '{{contact.email}}', label: 'Email' },
  { value: '{{contact.phone_number}}', label: 'Phone Number' },
];

const fieldOptions = computed(() => {
  const customOptions = contactAttributes.value.map(attr => ({
    value: `{{contact.custom_attribute.${attr.attributeKey}}}`,
    label: `${attr.attributeDisplayName}`,
  }));
  return [...STANDARD_FIELDS, ...customOptions];
});

const languageLabel = computed(() => {
  return `${t('WHATSAPP_TEMPLATES.PARSER.LANGUAGE')}: ${props.template.language || DEFAULT_LANGUAGE}`;
});

const categoryLabel = computed(() => {
  return `${t('WHATSAPP_TEMPLATES.PARSER.CATEGORY')}: ${props.template.category || DEFAULT_CATEGORY}`;
});

const headerComponent = computed(() =>
  findComponentByType(props.template, COMPONENT_TYPES.HEADER)
);

const bodyComponent = computed(() =>
  findComponentByType(props.template, COMPONENT_TYPES.BODY)
);

const bodyText = computed(() => bodyComponent.value?.text || '');

const hasMediaHeader = computed(() =>
  MEDIA_FORMATS.includes(headerComponent.value?.format)
);

const formatType = computed(() => {
  const format = headerComponent.value?.format;
  return format ? format.charAt(0) + format.slice(1).toLowerCase() : '';
});

const isDocumentTemplate = computed(
  () => headerComponent.value?.format?.toLowerCase() === 'document'
);

const hasVariables = computed(
  () => bodyText.value?.match(/{{([^}]+)}}/g) !== null
);

const renderedTemplate = computed(() =>
  replaceTemplateVariables(bodyText.value, processedParams.value)
);

const v$ = useVuelidate(
  {
    processedParams: {
      requiredIfKeysPresent: requiredIf(hasVariables),
      allKeysRequired,
    },
  },
  { processedParams }
);

const initializeTemplateParameters = () => {
  processedParams.value = buildTemplateParameters(
    props.template,
    hasMediaHeader.value
  );
  // Default all body variables to field mapping mode
  if (processedParams.value.body) {
    const modes = {};
    Object.keys(processedParams.value.body).forEach(key => {
      modes[key] = 'field';
    });
    variableModes.value = modes;
  }
};

const toggleMode = key => {
  variableModes.value[key] =
    variableModes.value[key] === 'field' ? 'static' : 'field';
  // Clear the value when switching modes
  processedParams.value.body[key] = '';
};

const formatVariableLabel = key => `{{${key}}}`;

const onFieldSelected = (key, value) => {
  processedParams.value.body[key] = value;
};

const updateMediaUrl = value => {
  processedParams.value.header ??= {};
  processedParams.value.header.media_url = value;
};

const updateMediaName = value => {
  processedParams.value.header ??= {};
  processedParams.value.header.media_name = value;
};

onMounted(initializeTemplateParameters);

watch(
  () => props.template,
  () => {
    initializeTemplateParameters();
    v$.value.$reset();
  },
  { deep: true }
);

defineExpose({
  processedParams,
  hasVariables,
  hasMediaHeader,
  isDocumentTemplate,
  headerComponent,
  renderedTemplate,
  v$,
  updateMediaUrl,
  updateMediaName,
});
</script>

<template>
  <div>
    <!-- Template Preview -->
    <div class="flex flex-col gap-4 p-4 mb-4 rounded-lg bg-n-alpha-black2">
      <div class="flex justify-between items-center">
        <h3 class="text-sm font-medium text-n-slate-12">
          {{ template.name }}
        </h3>
        <span class="text-xs text-n-slate-11">
          {{ languageLabel }}
        </span>
      </div>

      <div class="flex flex-col gap-2">
        <div class="rounded-md">
          <div class="text-sm whitespace-pre-wrap text-n-slate-12">
            {{ renderedTemplate }}
          </div>
        </div>
      </div>

      <div class="text-xs text-n-slate-11">
        {{ categoryLabel }}
      </div>
    </div>

    <div v-if="hasVariables || hasMediaHeader">
      <!-- Media Header (same as original parser) -->
      <div v-if="hasMediaHeader" class="mb-4">
        <p class="mb-2.5 text-sm font-semibold text-n-slate-12">
          {{
            $t('WHATSAPP_TEMPLATES.PARSER.MEDIA_HEADER_LABEL', {
              type: formatType,
            }) || `${formatType} Header`
          }}
        </p>
        <div class="flex items-center mb-2.5">
          <Input
            :model-value="processedParams.header?.media_url || ''"
            type="url"
            class="flex-1"
            :placeholder="
              t('WHATSAPP_TEMPLATES.PARSER.MEDIA_URL_LABEL', {
                type: formatType,
              })
            "
            @update:model-value="updateMediaUrl"
          />
        </div>
        <div v-if="isDocumentTemplate" class="flex items-center mb-2.5">
          <Input
            :model-value="processedParams.header?.media_name || ''"
            type="text"
            class="flex-1"
            :placeholder="
              t('WHATSAPP_TEMPLATES.PARSER.DOCUMENT_NAME_PLACEHOLDER')
            "
            @update:model-value="updateMediaName"
          />
        </div>
      </div>

      <!-- Body Variables with Field Mapping -->
      <div v-if="processedParams.body">
        <div class="flex items-center justify-between mb-2.5">
          <p class="text-sm font-semibold text-n-slate-12">
            {{ $t('WHATSAPP_TEMPLATES.VARIABLE_MAPPER.TITLE') }}
          </p>
        </div>
        <p class="mb-3 text-xs text-n-slate-11">
          {{ $t('WHATSAPP_TEMPLATES.VARIABLE_MAPPER.DESCRIPTION') }}
        </p>

        <div
          v-for="(_, key) in processedParams.body"
          :key="`body-${key}`"
          class="mb-3"
        >
          <div class="flex items-center gap-2 mb-1.5">
            <span
              class="text-xs font-medium text-n-slate-11 bg-n-slate-3 px-1.5 py-0.5 rounded font-mono"
            >
              {{ formatVariableLabel(key) }}
            </span>
            <button
              type="button"
              class="text-xs text-n-blue-11 hover:underline cursor-pointer"
              @click="toggleMode(key)"
            >
              {{
                variableModes[key] === 'field'
                  ? $t('WHATSAPP_TEMPLATES.VARIABLE_MAPPER.USE_STATIC')
                  : $t('WHATSAPP_TEMPLATES.VARIABLE_MAPPER.USE_FIELD')
              }}
            </button>
          </div>

          <!-- Field mapping mode -->
          <ComboBox
            v-if="variableModes[key] === 'field'"
            :model-value="processedParams.body[key]"
            :options="fieldOptions"
            :placeholder="$t('WHATSAPP_TEMPLATES.VARIABLE_MAPPER.SELECT_FIELD')"
            class="[&>div>button]:bg-n-alpha-black2 [&>div>button:not(.focused)]:dark:outline-n-weak [&>div>button:not(.focused)]:hover:!outline-n-slate-6"
            @update:model-value="value => onFieldSelected(key, value)"
          />

          <!-- Static value mode -->
          <Input
            v-else
            v-model="processedParams.body[key]"
            type="text"
            :placeholder="
              $t('WHATSAPP_TEMPLATES.VARIABLE_MAPPER.STATIC_PLACEHOLDER', {
                variable: key,
              })
            "
          />
        </div>
      </div>

      <!-- Button Variables (same as original parser) -->
      <div v-if="processedParams.buttons">
        <p class="mb-2.5 text-sm font-semibold text-n-slate-12">
          {{ t('WHATSAPP_TEMPLATES.PARSER.BUTTON_PARAMETERS') }}
        </p>
        <div
          v-for="(button, index) in processedParams.buttons"
          :key="`button-${index}`"
          class="flex items-center mb-2.5"
        >
          <Input
            v-model="processedParams.buttons[index].parameter"
            type="text"
            class="flex-1"
            :placeholder="t('WHATSAPP_TEMPLATES.PARSER.BUTTON_PARAMETER')"
          />
        </div>
      </div>

      <p
        v-if="v$.$dirty && v$.$invalid"
        class="p-2.5 text-center rounded-md bg-n-ruby-9/20 text-n-ruby-9"
      >
        {{ $t('WHATSAPP_TEMPLATES.PARSER.FORM_ERROR_MESSAGE') }}
      </p>
    </div>
  </div>
</template>
