<script setup>
import { ref, computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const emit = defineEmits(['import']);
const { t } = useI18n();

const uiFlags = useMapGetter('contacts/getUIFlags');
const isImportingContact = computed(() => uiFlags.value.isImporting);

const dialogRef = ref(null);
const fileInput = ref(null);

const hasSelectedFile = ref(null);
const selectedFileName = ref('');
const csvPreviewHeaders = ref([]);
const csvPreviewRows = ref([]);

const csvUrl = '/downloads/import-contacts-sample.csv';

// Column mapping aliases mirroring backend DataImport::ContactManager
const STANDARD_FIELD_ALIASES = {
  email: ['email', 'e-mail', 'email_address', 'emailaddress', 'mail'],
  phone_number: [
    'phone_number',
    'phonenumber',
    'phone',
    'phone_no',
    'mobile',
    'mobile_number',
    'cell',
    'cellphone',
    'telephone',
    'tel',
  ],
  identifier: [
    'identifier',
    'id',
    'external_id',
    'externalid',
    'customer_id',
    'customerid',
    'user_id',
    'userid',
  ],
  name: [
    'name',
    'full_name',
    'fullname',
    'contact_name',
    'contactname',
    'customer_name',
    'customername',
    'first_name',
    'firstname',
  ],
  company: [
    'company',
    'company_name',
    'companyname',
    'organization',
    'organisation',
    'org',
    'business',
  ],
  city: ['city', 'location', 'town'],
};

const IGNORED_COLUMNS = ['id', 'ip_address', 'created_at', 'updated_at'];

const resolveFieldMapping = header => {
  const normalized = header.toLowerCase().trim().replace(/\s+/g, '_');
  if (IGNORED_COLUMNS.includes(normalized))
    return { type: 'ignored', label: 'Ignored' };

  const matchedField = Object.entries(STANDARD_FIELD_ALIASES).find(
    ([, aliases]) => aliases.includes(normalized)
  );
  if (matchedField) {
    const label = matchedField[0]
      .replace(/_/g, ' ')
      .replace(/\b\w/g, l => l.toUpperCase());
    return { type: 'standard', label };
  }
  return { type: 'custom', label: 'Custom Attribute' };
};

const columnMappings = computed(() =>
  csvPreviewHeaders.value.map(header => ({
    header,
    mapping: resolveFieldMapping(header),
  }))
);

const parseCSV = text => {
  const lines = text.split(/\r?\n/).filter(line => line.trim());
  if (lines.length === 0) return { headers: [], rows: [] };

  // Simple CSV parse handling quoted fields
  const parseLine = line => {
    const result = [];
    let current = '';
    let inQuotes = false;
    [...line].forEach(char => {
      if (char === '"') {
        inQuotes = !inQuotes;
      } else if (char === ',' && !inQuotes) {
        result.push(current.trim());
        current = '';
      } else {
        current += char;
      }
    });
    result.push(current.trim());
    return result;
  };

  const headers = parseLine(lines[0]);
  const rows = lines.slice(1, 4).map(parseLine);
  return { headers, rows };
};

const handleFileClick = () => fileInput.value?.click();

const processFileName = fileName => {
  const lastDotIndex = fileName.lastIndexOf('.');
  const extension = fileName.slice(lastDotIndex);
  const baseName = fileName.slice(0, lastDotIndex);

  return baseName.length > 20
    ? `${baseName.slice(0, 20)}...${extension}`
    : fileName;
};

const handleFileChange = () => {
  const file = fileInput.value?.files[0];
  hasSelectedFile.value = file;
  selectedFileName.value = file ? processFileName(file.name) : '';

  // Parse CSV for preview
  if (file) {
    const reader = new FileReader();
    reader.onload = e => {
      const { headers, rows } = parseCSV(e.target.result);
      csvPreviewHeaders.value = headers;
      csvPreviewRows.value = rows;
    };
    reader.readAsText(file);
  } else {
    csvPreviewHeaders.value = [];
    csvPreviewRows.value = [];
  }
};

const handleRemoveFile = () => {
  hasSelectedFile.value = null;
  if (fileInput.value) {
    fileInput.value.value = null;
  }
  selectedFileName.value = '';
  csvPreviewHeaders.value = [];
  csvPreviewRows.value = [];
};

const uploadFile = async () => {
  if (!hasSelectedFile.value) return;
  emit('import', hasSelectedFile.value);
};

defineExpose({ dialogRef });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.TITLE')"
    :confirm-button-label="
      t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.IMPORT')
    "
    :is-loading="isImportingContact"
    :disable-confirm-button="isImportingContact"
    @confirm="uploadFile"
  >
    <template #description>
      <p class="mb-0 text-sm text-n-slate-11">
        {{ t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.DESCRIPTION') }}
        <a
          :href="csvUrl"
          target="_blank"
          rel="noopener noreferrer"
          download="import-contacts-sample.csv"
          class="text-n-blue-11"
        >
          {{
            t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.DOWNLOAD_LABEL')
          }}
        </a>
      </p>
    </template>

    <div class="flex flex-col gap-2">
      <div class="flex items-center gap-2">
        <label class="text-sm text-n-slate-12 whitespace-nowrap">
          {{ t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.LABEL') }}
        </label>
        <div class="flex items-center justify-between w-full gap-2">
          <span v-if="hasSelectedFile" class="text-sm text-n-slate-12">
            {{ selectedFileName }}
          </span>
          <Button
            v-if="!hasSelectedFile"
            :label="
              t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.CHOOSE_FILE')
            "
            icon="i-lucide-upload"
            color="slate"
            variant="ghost"
            size="sm"
            class="!w-fit"
            @click="handleFileClick"
          />
          <div v-else class="flex items-center gap-1">
            <Button
              :label="t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.CHANGE')"
              color="slate"
              variant="ghost"
              size="sm"
              @click="handleFileClick"
            />
            <div class="w-px h-3 bg-n-strong" />
            <Button
              icon="i-lucide-trash"
              color="slate"
              variant="ghost"
              size="sm"
              @click="handleRemoveFile"
            />
          </div>
        </div>
      </div>
    </div>

    <!-- CSV Preview & Column Mapping -->
    <div v-if="csvPreviewHeaders.length > 0" class="mt-4 flex flex-col gap-3">
      <!-- Column Mapping -->
      <div>
        <p class="mb-2 text-xs font-semibold text-n-slate-12">
          {{
            t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.COLUMN_MAPPING')
          }}
        </p>
        <div class="flex flex-wrap gap-1.5">
          <span
            v-for="col in columnMappings"
            :key="col.header"
            class="inline-flex items-center gap-1 text-xs px-2 py-1 rounded-md"
            :class="{
              'bg-n-teal-3 text-n-teal-11': col.mapping.type === 'standard',
              'bg-n-blue-3 text-n-blue-11': col.mapping.type === 'custom',
              'bg-n-slate-3 text-n-slate-10 line-through':
                col.mapping.type === 'ignored',
            }"
          >
            <span class="font-mono font-medium">{{ col.header }}</span>
            <span class="i-lucide-arrow-right size-3 opacity-60" />
            <span>{{ col.mapping.label }}</span>
          </span>
        </div>
      </div>

      <!-- Data Preview -->
      <div>
        <p class="mb-2 text-xs font-semibold text-n-slate-12">
          {{ t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.DATA_PREVIEW') }}
        </p>
        <div class="overflow-x-auto rounded-lg border border-n-weak">
          <table class="w-full text-xs">
            <thead>
              <tr class="bg-n-slate-3">
                <th
                  v-for="header in csvPreviewHeaders"
                  :key="header"
                  class="px-2.5 py-1.5 text-left font-medium text-n-slate-11 whitespace-nowrap"
                >
                  {{ header }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="(row, rowIdx) in csvPreviewRows"
                :key="rowIdx"
                class="border-t border-n-weak"
              >
                <td
                  v-for="(cell, cellIdx) in row"
                  :key="cellIdx"
                  class="px-2.5 py-1.5 text-n-slate-12 whitespace-nowrap max-w-[200px] truncate"
                >
                  {{ cell }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <p class="mt-1.5 text-xs text-n-slate-10">
          {{ t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.PREVIEW_NOTE') }}
        </p>
      </div>
    </div>

    <input
      ref="fileInput"
      type="file"
      accept="text/csv"
      class="hidden"
      @change="handleFileChange"
    />
  </Dialog>
</template>
