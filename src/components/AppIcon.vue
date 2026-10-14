<script setup lang="ts">
import { icons, type IconName } from './icons'

const props = withDefaults(defineProps<{ name: IconName; size?: number }>(), {
  size: 18,
})
</script>

<template>
  <component
    :is="icons[props.name]"
    class="icon"
    :width="props.size"
    :height="props.size"
    aria-hidden="true"
  />
</template>

<style scoped>
.icon {
  display: block;
  flex: none;
}
</style>
