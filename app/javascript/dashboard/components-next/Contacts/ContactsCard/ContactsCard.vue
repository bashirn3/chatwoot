<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';

import CardLayout from 'dashboard/components-next/CardLayout.vue';
import ContactsForm from 'dashboard/components-next/Contacts/ContactsForm/ContactsForm.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Flag from 'dashboard/components-next/flag/Flag.vue';
import ContactDeleteSection from 'dashboard/components-next/Contacts/ContactsCard/ContactDeleteSection.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import countries from 'shared/constants/countries';

const props = defineProps({
  id: { type: Number, required: true },
  name: { type: String, default: '' },
  email: { type: String, default: '' },
  additionalAttributes: { type: Object, default: () => ({}) },
  phoneNumber: { type: String, default: '' },
  thumbnail: { type: String, default: '' },
  availabilityStatus: { type: String, default: null },
  isExpanded: { type: Boolean, default: false },
  isUpdating: { type: Boolean, default: false },
  selectable: { type: Boolean, default: false },
  isSelected: { type: Boolean, default: false },
});

const emit = defineEmits([
  'toggle',
  'updateContact',
  'showContact',
  'select',
  'avatarHover',
]);

const { t } = useI18n();

const contactsFormRef = ref(null);

const getInitialContactData = () => ({
  id: props.id,
  name: props.name,
  email: props.email,
  phoneNumber: props.phoneNumber,
  additionalAttributes: props.additionalAttributes,
});

const contactData = ref(getInitialContactData());

const isFormInvalid = computed(() => contactsFormRef.value?.isFormInvalid);

const countriesMap = computed(() => {
  return countries.reduce((acc, country) => {
    acc[country.code] = country;
    acc[country.id] = country;
    return acc;
  }, {});
});

const countryDetails = computed(() => {
  const attributes = props.additionalAttributes || {};
  const { country, countryCode, city } = attributes;

  if (!country && !countryCode) return null;

  const activeCountry =
    countriesMap.value[country] || countriesMap.value[countryCode];

  if (!activeCountry) return null;

  return {
    countryCode: activeCountry.id,
    city: city ? `${city},` : null,
    name: activeCountry.name,
  };
});

const formattedLocation = computed(() => {
  if (!countryDetails.value) return '';

  return [countryDetails.value.city, countryDetails.value.name]
    .filter(Boolean)
    .join(' ');
});

const handleFormUpdate = updatedData => {
  Object.assign(contactData.value, updatedData);
};

const handleUpdateContact = () => {
  emit('updateContact', contactData.value);
};

const onClickExpand = () => {
  emit('toggle');
  contactData.value = getInitialContactData();
};

const onClickViewDetails = () => emit('showContact', props.id);

const toggleSelect = checked => {
  emit('select', checked);
};

const handleAvatarHover = isHovered => {
  emit('avatarHover', isHovered);
};
</script>

<template>
  <div class="relative">
    <CardLayout
      :key="id"
      layout="row"
      class="[&>div]:!py-2.5 [&>div]:!px-4"
      :class="{
        'outline-n-weak !bg-n-slate-3 dark:!bg-n-solid-3': isSelected,
      }"
    >
      <div class="flex items-center justify-start flex-1 gap-3 min-w-0">
        <div
          class="relative flex-shrink-0"
          @mouseenter="handleAvatarHover(true)"
          @mouseleave="handleAvatarHover(false)"
        >
          <Avatar
            :name="name"
            :src="thumbnail"
            :size="32"
            :status="availabilityStatus"
            hide-offline-status
            rounded-full
          >
            <template v-if="selectable" #overlay="{ size }">
              <label
                class="flex items-center justify-center rounded-full cursor-pointer absolute inset-0 z-10 backdrop-blur-[2px] border border-n-weak"
                :style="{ width: `${size}px`, height: `${size}px` }"
                @click.stop
              >
                <Checkbox
                  :model-value="isSelected"
                  @change="event => toggleSelect(event.target.checked)"
                />
              </label>
            </template>
          </Avatar>
        </div>
        <div class="flex items-center gap-3 flex-1 min-w-0">
          <span class="text-sm font-medium truncate text-n-slate-12">
            {{ name }}
          </span>
          <span
            v-if="additionalAttributes?.companyName"
            class="hidden sm:inline-flex items-center gap-1 text-xs truncate text-n-slate-11"
          >
            <span class="i-ph-building-light size-3 text-n-slate-10" />
            {{ additionalAttributes.companyName }}
          </span>
          <div class="w-px h-3 bg-n-slate-6 hidden sm:block" />
          <span v-if="phoneNumber" class="text-xs truncate text-n-slate-11">
            {{ phoneNumber }}
          </span>
          <div
            v-if="phoneNumber && email"
            class="w-px h-3 bg-n-slate-6 hidden sm:block"
          />
          <span
            v-if="email"
            class="hidden lg:inline text-xs truncate text-n-slate-11 max-w-48"
            :title="email"
          >
            {{ email }}
          </span>
          <div
            v-if="countryDetails"
            class="w-px h-3 bg-n-slate-6 hidden lg:block"
          />
          <span
            v-if="countryDetails"
            class="hidden lg:inline-flex items-center gap-1.5 text-xs truncate text-n-slate-11"
          >
            <Flag :country="countryDetails.countryCode" class="size-3" />
            {{ formattedLocation }}
          </span>
        </div>
        <Button
          :label="t('CONTACTS_LAYOUT.CARD.VIEW_DETAILS')"
          variant="link"
          color="slate"
          size="xs"
          class="flex-shrink-0 !text-xs"
          @click="onClickViewDetails"
        />
      </div>

      <Button
        icon="i-lucide-chevron-down"
        variant="ghost"
        color="slate"
        size="xs"
        class="flex-shrink-0"
        :class="{ 'rotate-180': isExpanded }"
        @click="onClickExpand"
      />

      <template #after>
        <div
          class="transition-all duration-500 ease-in-out grid overflow-hidden"
          :class="
            isExpanded
              ? 'grid-rows-[1fr] opacity-100'
              : 'grid-rows-[0fr] opacity-0'
          "
        >
          <div class="overflow-hidden">
            <div class="flex flex-col gap-6 p-6 border-t border-n-strong">
              <ContactsForm
                ref="contactsFormRef"
                :contact-data="contactData"
                @update="handleFormUpdate"
              />
              <div>
                <Button
                  :label="
                    t('CONTACTS_LAYOUT.CARD.EDIT_DETAILS_FORM.UPDATE_BUTTON')
                  "
                  size="sm"
                  :is-loading="isUpdating"
                  :disabled="isUpdating || isFormInvalid"
                  @click="handleUpdateContact"
                />
              </div>
            </div>
            <ContactDeleteSection
              :selected-contact="{
                id: props.id,
                name: props.name,
              }"
            />
          </div>
        </div>
      </template>
    </CardLayout>
  </div>
</template>
