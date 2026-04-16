<script setup>
import { ref, watch } from 'vue';

const props = defineProps({
  title: { type: String, required: true },
  isOpen: { type: Boolean, default: false },
});

const isExpanded = ref(props.isOpen);

const toggleAccordion = () => {
  isExpanded.value = !isExpanded.value;
};

watch(
  () => props.isOpen,
  newValue => {
    isExpanded.value = newValue;
  }
);
</script>

<template>
  <div class="border rounded-lg border-n-slate-4">
    <button
      type="button"
      class="flex items-center justify-between w-full p-4 text-left"
      @click="toggleAccordion"
    >
      <span class="text-sm font-medium text-n-slate-12">{{ title }}</span>
      <span
        class="w-5 h-5 transition-transform duration-200 i-lucide-chevron-down"
        :class="{ 'rotate-180': isExpanded }"
      />
    </button>
    <div
      class="accordion-body grid transition-[grid-template-rows,opacity] duration-200 ease-out"
      :class="isExpanded ? 'grid-rows-[1fr] opacity-100' : 'grid-rows-[0fr] opacity-0'"
    >
      <div class="overflow-hidden">
        <div class="p-4 pt-0">
          <slot />
        </div>
      </div>
    </div>
  </div>
</template>
