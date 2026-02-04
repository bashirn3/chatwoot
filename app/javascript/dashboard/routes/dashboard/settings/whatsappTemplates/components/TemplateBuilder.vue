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

// Form data
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

// Sample values for preview
const sampleValues = reactive({
  header: {},
  body: {},
});

// UI state
const isLoading = ref(false);
const showSampleModal = ref(false);
const showVariableHelp = ref(false);

// Predefined variables that can be used in templates
const predefinedVariables = [
  { name: 'first_name', description: 'Contact\'s first name', example: 'John' },
  { name: 'last_name', description: 'Contact\'s last name', example: 'Doe' },
  { name: 'full_name', description: 'Contact\'s full name', example: 'John Doe' },
  { name: 'email', description: 'Contact\'s email address', example: 'john@example.com' },
  { name: 'phone', description: 'Contact\'s phone number', example: '+1234567890' },
  { name: 'company', description: 'Contact\'s company name', example: 'Acme Inc' },
  { name: 'order_id', description: 'Order or reference ID', example: 'ORD-12345' },
  { name: 'amount', description: 'Amount or price', example: '$99.99' },
  { name: 'date', description: 'Date value', example: 'Jan 15, 2026' },
  { name: 'time', description: 'Time value', example: '2:30 PM' },
  { name: 'link', description: 'URL or link', example: 'https://example.com' },
  { name: 'code', description: 'Verification or coupon code', example: 'ABC123' },
];

// Languages and categories
const languages = computed(() => store.getters['whatsappTemplates/getLanguages'] || { en: 'English' });
const samples = computed(() => store.getters['whatsappTemplates/getSamples'] || {});

const categories = [
  { value: 'UTILITY', label: 'Utility', description: 'Updates, confirmations, reminders' },
  { value: 'MARKETING', label: 'Marketing', description: 'Promotions, offers, newsletters' },
  { value: 'AUTHENTICATION', label: 'Authentication', description: 'OTP, verification codes' },
];

const headerTypes = [
  { value: null, label: 'None' },
  { value: 'TEXT', label: 'Text' },
  { value: 'IMAGE', label: 'Image' },
  { value: 'VIDEO', label: 'Video' },
  { value: 'DOCUMENT', label: 'Document' },
  { value: 'LOCATION', label: 'Location' },
];

const buttonTypes = [
  { value: 'QUICK_REPLY', label: 'Quick Reply' },
  { value: 'URL', label: 'URL Button' },
  { value: 'PHONE_NUMBER', label: 'Phone Number' },
];

// Computed
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

// Helper to format variable placeholder for display
const formatVarLabel = (num) => {
  return '{{' + num + '}}';
};

// Methods
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

const loadSample = (sampleKey) => {
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

const insertVariable = (field) => {
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
  
  // Set the example value from predefined variable
  if (field === 'body_text') {
    sampleValues.body[nextVar] = variable.example;
  } else if (field === 'header_content') {
    sampleValues.header[nextVar] = variable.example;
  }
};

const addButton = (type) => {
  if (!canAddButton.value) return;
  
  const newButton = { type, text: '' };
  
  if (type === 'URL') {
    newButton.url = '';
  } else if (type === 'PHONE_NUMBER') {
    newButton.phone_number = '';
  }
  
  formData.buttons.push(newButton);
};

const removeButton = (index) => {
  formData.buttons.splice(index, 1);
};

const handleSubmit = async () => {
  if (!isValid.value) {
    useAlert(t('WHATSAPP_TEMPLATES.VALIDATION_ERROR'));
    return;
  }
  
  isLoading.value = true;
  
  try {
    const bodyParams = Object.entries(sampleValues.body).map(([index, example]) => ({
      index: parseInt(index),
      example,
    }));
    
    const headerParams = Object.entries(sampleValues.header).map(([index, example]) => ({
      index: parseInt(index),
      example,
    }));
    
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

// Watchers
watch(() => props.template, loadTemplate, { immediate: true });

// Lifecycle
onMounted(async () => {
  try {
    await store.dispatch('whatsappTemplates/fetchLanguages');
    await store.dispatch('whatsappTemplates/fetchSamples');
  } catch (e) {
    console.error('Failed to load template resources:', e);
  }
});
</script>

<template>
  <div class="flex gap-6 h-full">
    <!-- Left Side: Form -->
    <div class="flex-1 overflow-y-auto overflow-x-visible pr-2">
      <!-- Header Actions -->
      <div class="flex justify-between items-center mb-6">
        <h2 class="text-xl font-semibold">
          {{ mode === 'create' ? $t('WHATSAPP_TEMPLATES.CREATE_TITLE') : $t('WHATSAPP_TEMPLATES.EDIT_TITLE') }}
        </h2>
        <Button
          label="Load Sample"
          slate
          faded
          sm
          @click="showSampleModal = true"
        />
      </div>
      
      <!-- Basic Info -->
      <div class="mb-6">
        <label class="block text-sm font-medium mb-2">
          {{ $t('WHATSAPP_TEMPLATES.NAME') }}
          <span class="text-red-500">*</span>
        </label>
        <input
          v-model="formData.name"
          type="text"
          class="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm"
          :placeholder="$t('WHATSAPP_TEMPLATES.NAME_PLACEHOLDER')"
          :disabled="mode === 'edit' && template?.status !== 'DRAFT'"
        />
        <p class="text-xs text-slate-500 mt-1">
          {{ $t('WHATSAPP_TEMPLATES.NAME_HELP') }}
        </p>
      </div>
      
      <div class="grid grid-cols-2 gap-4 mb-6">
        <div>
          <label class="block text-sm font-medium mb-2">
            {{ $t('WHATSAPP_TEMPLATES.LANGUAGE') }}
          </label>
          <div class="relative">
            <select 
              v-model="formData.language" 
              class="w-full h-10 px-3 pr-10 border border-slate-200 rounded-lg text-sm bg-white cursor-pointer focus:outline-none focus:ring-2 focus:ring-woot-500 focus:border-transparent"
              style="appearance: none; -webkit-appearance: none; -moz-appearance: none;"
            >
              <option 
                v-for="(label, code) in languages" 
                :key="code" 
                :value="code"
              >
                {{ label }}
              </option>
            </select>
            <svg class="absolute right-3 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-400 pointer-events-none" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7"></path>
            </svg>
          </div>
        </div>
        
        <div>
          <label class="block text-sm font-medium mb-2">
            {{ $t('WHATSAPP_TEMPLATES.CATEGORY') }}
          </label>
          <div class="relative">
            <select 
              v-model="formData.category" 
              class="w-full h-10 px-3 pr-10 border border-slate-200 rounded-lg text-sm bg-white cursor-pointer focus:outline-none focus:ring-2 focus:ring-woot-500 focus:border-transparent"
              style="appearance: none; -webkit-appearance: none; -moz-appearance: none;"
            >
              <option 
                v-for="cat in categories" 
                :key="cat.value" 
                :value="cat.value"
              >
                {{ cat.label }}
              </option>
            </select>
            <svg class="absolute right-3 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-400 pointer-events-none" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7"></path>
            </svg>
          </div>
        </div>
      </div>
      
      <!-- Header Section -->
      <div class="border-t border-slate-200 pt-6 mb-6">
        <h3 class="font-medium mb-4">{{ $t('WHATSAPP_TEMPLATES.HEADER') }}</h3>
        
        <div class="flex flex-wrap gap-2 mb-4">
          <button
            v-for="ht in headerTypes"
            :key="ht.value"
            :class="[
              'px-3 py-1.5 text-sm rounded-lg border transition-colors',
              formData.header_type === ht.value 
                ? 'bg-woot-500 text-white border-woot-500' 
                : 'bg-white border-slate-200 hover:border-woot-300'
            ]"
            @click="formData.header_type = ht.value"
          >
            {{ ht.label }}
          </button>
        </div>
        
        <!-- Text Header -->
        <div v-if="formData.header_type === 'TEXT'" class="mb-4">
          <div class="flex gap-2">
            <input
              v-model="formData.header_content"
              type="text"
              class="flex-1 px-3 py-2 border border-slate-200 rounded-lg text-sm"
              :placeholder="$t('WHATSAPP_TEMPLATES.HEADER_TEXT_PLACEHOLDER')"
              maxlength="60"
            />
            <Button
              label="+ Variable"
              slate
              faded
              sm
              @click="insertVariable('header_content')"
            />
          </div>
          <p class="text-xs text-slate-500 mt-1">{{ formData.header_content?.length || 0 }}/60 characters</p>
        </div>
        
        <!-- Media Headers (Image, Video, Document) -->
        <div v-if="isMediaHeader" class="mb-4">
          <div class="p-4 bg-slate-50 rounded-lg border border-slate-200">
            <div class="flex items-center gap-3 mb-3">
              <div class="w-10 h-10 rounded-lg bg-slate-200 flex items-center justify-center">
                <svg v-if="formData.header_type === 'IMAGE'" class="w-5 h-5 text-slate-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"></path>
                </svg>
                <svg v-else-if="formData.header_type === 'VIDEO'" class="w-5 h-5 text-slate-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 10l4.553-2.276A1 1 0 0121 8.618v6.764a1 1 0 01-1.447.894L15 14M5 18h8a2 2 0 002-2V8a2 2 0 00-2-2H5a2 2 0 00-2 2v8a2 2 0 002 2z"></path>
                </svg>
                <svg v-else-if="formData.header_type === 'DOCUMENT'" class="w-5 h-5 text-slate-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"></path>
                </svg>
              </div>
              <div>
                <p class="font-medium text-sm">{{ formData.header_type }} Header</p>
                <p class="text-xs text-slate-500">Enter a sample URL for the media file</p>
              </div>
            </div>
            <input
              v-model="formData.header_content"
              type="url"
              class="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm"
              :placeholder="formData.header_type === 'IMAGE' 
                ? 'https://example.com/image.jpg' 
                : formData.header_type === 'VIDEO' 
                  ? 'https://example.com/video.mp4' 
                  : 'https://example.com/document.pdf'"
            />
            <p class="text-xs text-slate-500 mt-2">
              <strong>Note:</strong> When sending, you'll provide the actual media URL. This is just a sample for template approval.
            </p>
          </div>
        </div>
        
        <!-- Location Header -->
        <div v-if="formData.header_type === 'LOCATION'" class="space-y-4">
          <div class="grid grid-cols-2 gap-4">
            <div>
              <label class="block text-sm mb-1">Latitude</label>
              <input
                v-model="formData.location_latitude"
                type="text"
                class="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm"
                placeholder="e.g., 37.7749"
              />
            </div>
            <div>
              <label class="block text-sm mb-1">Longitude</label>
              <input
                v-model="formData.location_longitude"
                type="text"
                class="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm"
                placeholder="e.g., -122.4194"
              />
            </div>
          </div>
          <div>
            <label class="block text-sm mb-1">Location Name</label>
            <input
              v-model="formData.location_name"
              type="text"
              class="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm"
              placeholder="e.g., Our Office"
            />
          </div>
          <div>
            <label class="block text-sm mb-1">Address</label>
            <input
              v-model="formData.location_address"
              type="text"
              class="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm"
              placeholder="e.g., 123 Main St, City, Country"
            />
          </div>
        </div>
      </div>
      
      <!-- Body Section -->
      <div class="border-t border-slate-200 pt-6 mb-6">
        <div class="flex justify-between items-center mb-4">
          <h3 class="font-medium">
            {{ $t('WHATSAPP_TEMPLATES.BODY') }}
            <span class="text-red-500">*</span>
          </h3>
          <button 
            class="text-sm text-woot-500 hover:text-woot-600"
            @click="showVariableHelp = !showVariableHelp"
          >
            How do variables work?
          </button>
        </div>
        
        <!-- Variable Help Panel -->
        <div v-if="showVariableHelp" class="mb-4 p-4 bg-blue-50 border border-blue-200 rounded-lg">
          <h4 class="font-medium text-blue-900 mb-2">Understanding Variables</h4>
          <p class="text-sm text-blue-800 mb-3">
            Variables are placeholders in your template that get replaced with actual values when sending messages.
            WhatsApp uses numbered placeholders like <code class="bg-blue-100 px-1 rounded">{'{{1}}'}</code>, <code class="bg-blue-100 px-1 rounded">{'{{2}}'}</code>, etc.
          </p>
          <p class="text-sm text-blue-800 mb-3">
            <strong>Example:</strong> "Hi {'{{1}}'}, your order {'{{2}}'} is ready!" becomes "Hi John, your order #12345 is ready!"
          </p>
          <p class="text-sm text-blue-800 mb-2">
            <strong>Click a variable below to insert it:</strong>
          </p>
          <div class="flex flex-wrap gap-2">
            <button
              v-for="variable in predefinedVariables"
              :key="variable.name"
              class="px-2 py-1 text-xs bg-blue-100 text-blue-800 rounded hover:bg-blue-200 transition-colors"
              :title="variable.description"
              @click="insertPredefinedVariable(variable)"
            >
              {{ variable.name }}
            </button>
          </div>
        </div>
        
        <textarea
          v-model="formData.body_text"
          class="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm resize-none"
          :placeholder="$t('WHATSAPP_TEMPLATES.BODY_PLACEHOLDER')"
          rows="6"
          maxlength="1024"
        ></textarea>
        <div class="flex justify-between items-center mt-2">
          <Button
            label="+ Add Variable"
            slate
            faded
            sm
            @click="insertVariable('body_text')"
          />
          <span :class="['text-xs', bodyCharCount > 900 ? 'text-orange-500' : 'text-slate-500']">
            {{ bodyCharCount }}/1024
          </span>
        </div>
        
        <!-- Variable Examples -->
        <div v-if="bodyVariableCount > 0" class="mt-4 p-4 bg-slate-50 rounded-lg border border-slate-200">
          <label class="block text-sm font-medium mb-2">
            {{ $t('WHATSAPP_TEMPLATES.VARIABLE_EXAMPLES') }}
          </label>
          <p class="text-xs text-slate-500 mb-4">
            Provide example values for each variable. These are used for template approval and preview.
          </p>
          <div class="space-y-3">
            <div v-for="i in bodyVariableCount" :key="i" class="flex items-center gap-3">
              <span class="text-xs font-mono bg-woot-100 text-woot-700 px-2 py-1.5 rounded font-semibold min-w-[50px] text-center border border-woot-200">
                {{ formatVarLabel(i) }}
              </span>
              <input
                v-model="sampleValues.body[i]"
                type="text"
                class="flex-1 min-w-[150px] h-9 px-3 border border-slate-300 rounded-lg text-sm bg-white focus:outline-none focus:ring-2 focus:ring-woot-500 focus:border-transparent"
                :placeholder="`Enter example for variable ${i}`"
              />
              <select 
                class="h-9 px-3 pr-8 border border-slate-300 rounded-lg text-sm bg-white cursor-pointer focus:outline-none focus:ring-2 focus:ring-woot-500 focus:border-transparent"
                style="appearance: none; -webkit-appearance: none; min-width: 140px;"
                @change="(e) => { if (e.target.value) { sampleValues.body[i] = predefinedVariables.find(v => v.name === e.target.value)?.example || ''; } }"
              >
                <option value="">Quick fill...</option>
                <option v-for="v in predefinedVariables" :key="v.name" :value="v.name">
                  {{ v.name }} ({{ v.example }})
                </option>
              </select>
            </div>
          </div>
        </div>
      </div>
      
      <!-- Footer Section -->
      <div class="border-t border-slate-200 pt-6 mb-6">
        <h3 class="font-medium mb-4">{{ $t('WHATSAPP_TEMPLATES.FOOTER') }}</h3>
        <input
          v-model="formData.footer_text"
          type="text"
          class="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm"
          :placeholder="$t('WHATSAPP_TEMPLATES.FOOTER_PLACEHOLDER')"
          maxlength="60"
        />
        <p class="text-xs text-slate-500 mt-1">{{ formData.footer_text?.length || 0 }}/60 characters</p>
      </div>
      
      <!-- Buttons Section -->
      <div class="border-t border-slate-200 pt-6 mb-6">
        <h3 class="font-medium mb-4">{{ $t('WHATSAPP_TEMPLATES.BUTTONS') }}</h3>
        
        <div v-if="canAddButton" class="flex flex-wrap gap-2 mb-4">
          <Button
            v-for="bt in buttonTypes"
            :key="bt.value"
            :label="'+ ' + bt.label"
            slate
            faded
            sm
            @click="addButton(bt.value)"
          />
        </div>
        <p v-else class="text-xs text-slate-500 mb-4">Maximum 3 buttons allowed</p>
        
        <div v-if="formData.buttons.length > 0" class="space-y-4">
          <div 
            v-for="(button, index) in formData.buttons" 
            :key="index"
            class="p-4 border border-slate-200 rounded-lg"
          >
            <div class="flex justify-between items-center mb-3">
              <span class="text-sm font-medium">{{ button.type.replace('_', ' ') }}</span>
              <button 
                class="text-red-500 hover:text-red-600"
                @click="removeButton(index)"
              >
                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
                </svg>
              </button>
            </div>
            
            <input
              v-model="button.text"
              type="text"
              class="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm mb-2"
              placeholder="Button text"
              maxlength="25"
            />
            
            <input
              v-if="button.type === 'URL'"
              v-model="button.url"
              type="text"
              class="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm"
              placeholder="https://example.com"
            />
            
            <input
              v-if="button.type === 'PHONE_NUMBER'"
              v-model="button.phone_number"
              type="text"
              class="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm"
              placeholder="+1234567890"
            />
          </div>
        </div>
      </div>
      
      <!-- Actions -->
      <div class="flex justify-end gap-3 pt-6 border-t border-slate-200">
        <Button
          :label="$t('WHATSAPP_TEMPLATES.CANCEL')"
          slate
          faded
          @click="handleCancel"
        />
        <Button
          :label="mode === 'create' ? $t('WHATSAPP_TEMPLATES.CREATE') : $t('WHATSAPP_TEMPLATES.SAVE')"
          :is-loading="isLoading"
          :disabled="!isValid"
          @click="handleSubmit"
        />
      </div>
    </div>
    
    <!-- Right Side: Preview -->
    <div class="w-[380px] flex-shrink-0">
      <div class="sticky top-0">
        <WhatsAppPreview 
          :template="formData"
          :sample-values="sampleValues"
        />
      </div>
    </div>
    
    <!-- Sample Modal -->
    <div 
      v-if="showSampleModal" 
      class="fixed inset-0 bg-black/50 flex items-center justify-center z-50"
      @click.self="showSampleModal = false"
    >
      <div class="bg-white rounded-xl p-6 max-w-md w-full mx-4">
        <h3 class="text-lg font-semibold mb-4">{{ $t('WHATSAPP_TEMPLATES.SAMPLE_TEMPLATES') }}</h3>
        
        <div class="space-y-2 max-h-60 overflow-auto">
          <button
            v-for="(sample, key) in samples"
            :key="key"
            class="w-full text-left p-3 border border-slate-200 rounded-lg hover:bg-slate-50 transition-colors"
            @click="loadSample(key)"
          >
            <p class="font-medium">{{ sample.name }}</p>
            <p class="text-sm text-slate-500">{{ sample.category }}</p>
          </button>
          <p v-if="Object.keys(samples).length === 0" class="text-sm text-slate-500 text-center py-4">
            No sample templates available
          </p>
        </div>
        
        <div class="flex justify-end mt-4">
          <Button
            label="Close"
            slate
            faded
            @click="showSampleModal = false"
          />
        </div>
      </div>
    </div>
  </div>
</template>
