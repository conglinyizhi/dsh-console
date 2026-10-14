<script setup lang="ts">
import { ref } from 'vue'
import SideNav from './components/SideNav.vue'
import NavTopBar from './components/NavTopBar.vue'
import OverviewView from './views/OverviewView.vue'
import LogsView from './views/LogsView.vue'
import AboutView from './views/AboutView.vue'
import type { NavKey } from './nav'

const page = ref<NavKey>('overview')

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
        <LogsView v-else-if="page === 'logs'" />
        <AboutView v-else />
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
