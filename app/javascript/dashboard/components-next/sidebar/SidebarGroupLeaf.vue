<script setup>
import { isVNode, computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store.js';
import Icon from 'next/icon/Icon.vue';
import Policy from 'dashboard/components/policy.vue';
import { useSidebarContext } from './provider';

const props = defineProps({
  label: { type: String, required: true },
  to: { type: [String, Object], required: true },
  icon: { type: [String, Object], default: null },
  active: { type: Boolean, default: false },
  component: { type: Function, default: null },
  activeAccent: { type: String, default: '' },
  getterKeys: { type: Object, default: () => ({}) },
});

const { resolvePermissions, resolveFeatureFlag } = useSidebarContext();

const shouldRenderComponent = computed(() => {
  return typeof props.component === 'function' || isVNode(props.component);
});

const accentStyle = computed(() => {
  if (props.active && props.activeAccent) {
    return {
      color: props.activeAccent,
      boxShadow: `inset 2px 0 0 0 ${props.activeAccent}`,
    };
  }
  return {};
});

const showBadge = useMapGetter(props.getterKeys.badge);
const dynamicCount = useMapGetter(props.getterKeys.count);
const count = computed(() =>
  dynamicCount.value > 99 ? '99+' : dynamicCount.value
);
</script>

<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <Policy
    :permissions="resolvePermissions(to)"
    :feature-flag="resolveFeatureFlag(to)"
    as="li"
    class="py-0.5 ltr:pl-2 rtl:pr-2 rtl:mr-3 ltr:ml-3 relative text-n-slate-11 after:bg-transparent after:border-n-slate-4 before:left-0 rtl:before:right-0 min-w-0"
    :class="[
      activeAccent ? '' : 'child-item',
      activeAccent
        ? 'before:bg-transparent'
        : active
          ? 'before:bg-n-slate-9'
          : 'before:bg-n-slate-4',
    ]"
  >
    <component
      :is="to ? 'router-link' : 'div'"
      :to="to"
      :title="label"
      class="flex h-8 items-center gap-2 px-2 py-1 rounded-lg hover:bg-gradient-to-r from-transparent via-n-slate-3/70 to-n-slate-3/70 transition-[background-color,opacity] duration-150 group min-w-0"
      :class="{
        'text-n-slate-12 bg-n-slate-3 dark:bg-n-slate-3/50 font-medium active':
          active,
      }"
      :style="accentStyle"
    >
      <component
        :is="component"
        v-if="shouldRenderComponent"
        :label
        :icon
        :active
      />
      <template v-else>
        <Icon v-if="icon" :icon="icon" class="size-4 inline-block" />
        <div class="flex-1 truncate min-w-0">{{ label }}</div>
        <span
          v-if="dynamicCount"
          class="rounded-md text-xs leading-5 font-medium text-center outline outline-1 px-1 flex-shrink-0 tabular-nums"
          :class="
            active
              ? 'text-n-slate-12 outline-n-slate-6'
              : 'text-n-slate-11 outline-n-strong'
          "
        >
          {{ count }}
        </span>
        <span
          v-else-if="showBadge"
          class="size-2 rounded-full bg-n-brand flex-shrink-0"
        />
      </template>
    </component>
  </Policy>
</template>
