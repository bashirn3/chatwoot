<script setup>
import { computed, onMounted, ref, nextTick } from 'vue';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { useAccount } from 'dashboard/composables/useAccount';
import CaptainGoogleDrive from 'dashboard/api/captain/googleDrive';

import DeleteDialog from 'dashboard/components-next/captain/pageComponents/DeleteDialog.vue';
import DocumentCard from 'dashboard/components-next/captain/assistant/DocumentCard.vue';
import PageLayout from 'dashboard/components-next/captain/PageLayout.vue';
import CaptainPaywall from 'dashboard/components-next/captain/pageComponents/Paywall.vue';
import RelatedResponses from 'dashboard/components-next/captain/pageComponents/document/RelatedResponses.vue';
import CreateDocumentDialog from 'dashboard/components-next/captain/pageComponents/document/CreateDocumentDialog.vue';
import DocumentPageEmptyState from 'dashboard/components-next/captain/pageComponents/emptyStates/DocumentPageEmptyState.vue';
import FeatureSpotlightPopover from 'dashboard/components-next/feature-spotlight/FeatureSpotlightPopover.vue';
import LimitBanner from 'dashboard/components-next/captain/pageComponents/document/LimitBanner.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const route = useRoute();
const store = useStore();
const { t } = useI18n();

const { isOnChatwootCloud } = useAccount();
const uiFlags = useMapGetter('captainDocuments/getUIFlags');
const documents = useMapGetter('captainDocuments/getRecords');
const isFetching = computed(() => uiFlags.value.fetchingList);
const documentsMeta = useMapGetter('captainDocuments/getMeta');

const selectedAssistantId = computed(() => Number(route.params.assistantId));

const selectedDocument = ref(null);
const deleteDocumentDialog = ref(null);

const handleDelete = () => {
  deleteDocumentDialog.value.dialogRef.open();
};

const showRelatedResponses = ref(false);
const showCreateDialog = ref(false);
const createDocumentDialog = ref(null);
const relationQuestionDialog = ref(null);

const driveConnected = ref(false);
const driveLastSynced = ref(null);
const driveLoading = ref(false);
const driveSyncing = ref(false);

const fetchDriveStatus = async () => {
  try {
    const { data } = await CaptainGoogleDrive.status();
    driveConnected.value = data.connected;
    driveLastSynced.value = data.last_synced_at;
  } catch {
    driveConnected.value = false;
  }
};

const handleConnectDrive = async () => {
  driveLoading.value = true;
  try {
    const { data } = await CaptainGoogleDrive.authorize(
      selectedAssistantId.value
    );
    if (data.url) {
      window.location.href = data.url;
    }
  } catch {
    useAlert(t('CAPTAIN.DOCUMENTS.GOOGLE_DRIVE.CONNECT_ERROR'));
    driveLoading.value = false;
  }
};

const handleSyncDrive = async () => {
  driveSyncing.value = true;
  try {
    await CaptainGoogleDrive.sync();
    useAlert(t('CAPTAIN.DOCUMENTS.GOOGLE_DRIVE.SYNC_STARTED'));
  } catch {
    useAlert(t('CAPTAIN.DOCUMENTS.GOOGLE_DRIVE.CONNECT_ERROR'));
  } finally {
    driveSyncing.value = false;
  }
};

const handleDisconnectDrive = async () => {
  if (!window.confirm(t('CAPTAIN.DOCUMENTS.GOOGLE_DRIVE.DISCONNECT_CONFIRM')))
    return;
  try {
    await CaptainGoogleDrive.disconnect();
    driveConnected.value = false;
    driveLastSynced.value = null;
    useAlert(t('CAPTAIN.DOCUMENTS.GOOGLE_DRIVE.DISCONNECT_SUCCESS'));
  } catch {
    useAlert(t('CAPTAIN.DOCUMENTS.GOOGLE_DRIVE.DISCONNECT_ERROR'));
  }
};

const handleDriveCallback = () => {
  const urlParams = new URLSearchParams(window.location.search);
  if (urlParams.get('google_drive') === 'connected') {
    driveConnected.value = true;
    fetchDriveStatus();
    window.history.replaceState({}, '', window.location.pathname);
  }
};

const formattedLastSynced = computed(() => {
  if (!driveLastSynced.value)
    return t('CAPTAIN.DOCUMENTS.GOOGLE_DRIVE.NEVER_SYNCED');
  const date = new Date(driveLastSynced.value);
  return t('CAPTAIN.DOCUMENTS.GOOGLE_DRIVE.LAST_SYNCED', {
    time: date.toLocaleString(),
  });
});

const handleShowRelatedDocument = () => {
  showRelatedResponses.value = true;
  nextTick(() => relationQuestionDialog.value.dialogRef.open());
};
const handleCreateDocument = () => {
  showCreateDialog.value = true;
  nextTick(() => createDocumentDialog.value.dialogRef.open());
};

const handleRelatedResponseClose = () => {
  showRelatedResponses.value = false;
};

const handleCreateDialogClose = () => {
  showCreateDialog.value = false;
};

const handleAction = ({ action, id }) => {
  selectedDocument.value = documents.value.find(
    captainDocument => id === captainDocument.id
  );

  nextTick(() => {
    if (action === 'delete') {
      handleDelete();
    } else if (action === 'viewRelatedQuestions') {
      handleShowRelatedDocument();
    }
  });
};

const fetchDocuments = (page = 1) => {
  const filterParams = { page };

  if (selectedAssistantId.value) {
    filterParams.assistantId = selectedAssistantId.value;
  }
  store.dispatch('captainDocuments/get', filterParams);
};

const onPageChange = page => fetchDocuments(page);

const onDeleteSuccess = () => {
  if (documents.value?.length === 0 && documentsMeta.value?.page > 1) {
    onPageChange(documentsMeta.value.page - 1);
  }
};

onMounted(() => {
  fetchDocuments();
  fetchDriveStatus();
  handleDriveCallback();
});
</script>

<template>
  <PageLayout
    :header-title="$t('CAPTAIN.DOCUMENTS.HEADER')"
    :button-label="$t('CAPTAIN.DOCUMENTS.ADD_NEW')"
    :button-policy="['administrator']"
    :total-count="documentsMeta.totalCount"
    :current-page="documentsMeta.page"
    :show-pagination-footer="!isFetching && !!documents.length"
    :is-fetching="isFetching"
    :is-empty="!documents.length"
    :show-know-more="false"
    :feature-flag="FEATURE_FLAGS.CAPTAIN"
    @update:current-page="onPageChange"
    @click="handleCreateDocument"
  >
    <template #knowMore>
      <FeatureSpotlightPopover
        :button-label="$t('CAPTAIN.HEADER_KNOW_MORE')"
        :title="$t('CAPTAIN.DOCUMENTS.EMPTY_STATE.FEATURE_SPOTLIGHT.TITLE')"
        :note="$t('CAPTAIN.DOCUMENTS.EMPTY_STATE.FEATURE_SPOTLIGHT.NOTE')"
        :hide-actions="!isOnChatwootCloud"
        fallback-thumbnail="/assets/images/dashboard/captain/document-popover-light.svg"
        fallback-thumbnail-dark="/assets/images/dashboard/captain/document-popover-dark.svg"
        learn-more-url="https://chwt.app/captain-document"
      />
    </template>

    <template #emptyState>
      <DocumentPageEmptyState @click="handleCreateDocument" />
    </template>

    <template #paywall>
      <CaptainPaywall />
    </template>

    <template #body>
      <LimitBanner class="mb-5" />

      <div
        class="flex items-center justify-between p-4 mb-5 border rounded-xl border-n-weak bg-n-surface-2"
      >
        <div class="flex items-center gap-3">
          <div
            class="flex items-center justify-center rounded-lg size-10 bg-n-alpha-2"
          >
            <span class="i-lucide-hard-drive text-n-slate-11 size-5" />
          </div>
          <div>
            <h4
              v-if="driveConnected"
              class="text-sm font-medium text-n-slate-12"
            >
              {{ $t('CAPTAIN.DOCUMENTS.GOOGLE_DRIVE.CONNECTED') }}
            </h4>
            <h4 v-else class="text-sm font-medium text-n-slate-12">
              {{ $t('CAPTAIN.DOCUMENTS.GOOGLE_DRIVE.CONNECT') }}
            </h4>
            <p class="text-xs text-n-slate-11">
              <template v-if="driveConnected">
                {{ formattedLastSynced }}
              </template>
              <template v-else>
                {{ $t('CAPTAIN.DOCUMENTS.GOOGLE_DRIVE.CONNECT_DESCRIPTION') }}
              </template>
            </p>
          </div>
        </div>
        <div class="flex items-center gap-2">
          <template v-if="driveConnected">
            <Button
              :label="
                driveSyncing
                  ? $t('CAPTAIN.DOCUMENTS.GOOGLE_DRIVE.SYNCING')
                  : $t('CAPTAIN.DOCUMENTS.GOOGLE_DRIVE.SYNC_NOW')
              "
              icon="i-lucide-refresh-cw"
              variant="faded"
              color="slate"
              size="sm"
              :is-loading="driveSyncing"
              @click="handleSyncDrive"
            />
            <Button
              :label="$t('CAPTAIN.DOCUMENTS.GOOGLE_DRIVE.DISCONNECT')"
              variant="ghost"
              color="ruby"
              size="sm"
              @click="handleDisconnectDrive"
            />
          </template>
          <template v-else>
            <Button
              :label="$t('CAPTAIN.DOCUMENTS.GOOGLE_DRIVE.CONNECT')"
              icon="i-lucide-link"
              variant="faded"
              color="slate"
              size="sm"
              :is-loading="driveLoading"
              @click="handleConnectDrive"
            />
          </template>
        </div>
      </div>

      <div class="flex flex-col gap-4">
        <DocumentCard
          v-for="doc in documents"
          :id="doc.id"
          :key="doc.id"
          :name="doc.name || doc.external_link"
          :external-link="doc.external_link"
          :assistant="doc.assistant"
          :created-at="doc.created_at"
          @action="handleAction"
        />
      </div>
    </template>

    <RelatedResponses
      v-if="showRelatedResponses"
      ref="relationQuestionDialog"
      :captain-document="selectedDocument"
      @close="handleRelatedResponseClose"
    />
    <CreateDocumentDialog
      v-if="showCreateDialog"
      ref="createDocumentDialog"
      :assistant-id="selectedAssistantId"
      @close="handleCreateDialogClose"
    />
    <DeleteDialog
      v-if="selectedDocument"
      ref="deleteDocumentDialog"
      :entity="selectedDocument"
      type="Documents"
      @delete-success="onDeleteSuccess"
    />
  </PageLayout>
</template>
