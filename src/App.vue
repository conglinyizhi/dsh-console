<script setup lang="ts">
import { computed, ref } from 'vue'
import SideNav from './components/SideNav.vue'
import NavTopBar from './components/NavTopBar.vue'
import OverviewView from './views/OverviewView.vue'
import PlaceholderView from './views/PlaceholderView.vue'
import { navItems, type NavKey } from './nav'

const page = ref<NavKey>('overview')

const currentLabel = computed(
  () => navItems.find((item) => item.key === page.value)?.label ?? '',
)

function selectPage(key: NavKey) {
  page.value = key
}
</script>

<template>
  <div class="shell">
    <SideNav :current="page" @select="selectPage" />
    <div class="workbench">
      <NavTopBar />
      <main class="main">
        <OverviewView v-if="page === 'overview'" />
        <PlaceholderView v-else :title="currentLabel" />
      </main>
    </div>
  </div>
</template>

<style scoped>
.shell {
  height: 100%;
  display: flex;
  overflow: hidden;
}
.workbench {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
}
.main {
  flex: 1;
  min-height: 0;
  overflow-y: auto;
  overflow-x: hidden;
}
</style>
