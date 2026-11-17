<!-- A sample Vue single-file component -->
<template>
  <div id="app" class="container">
    <h1 v-if="show">{{ title.toUpperCase() }}</h1>
    <p v-else>Nothing to show &amp; nothing to hide.</p>
    <ul>
      <li v-for="(item, index) in items" :key="item.id" @click.prevent="select(item)">
        {{ index }}: {{ item.name }}
      </li>
    </ul>
    <input v-model.trim="query" :[attrName]="value" />
    <MyComponent #default="{ value }">{{ value }}</MyComponent>
  </div>
</template>

<script setup lang="ts">
import { ref, computed } from 'vue'

interface Item {
  id: number
  name: string
}

const title = ref<string>('Hello Vue')
const show = ref(true)
const items = ref<Item[]>([{ id: 1, name: 'First' }])
const count = computed(() => items.value.length * 2)

function select(item: Item): void {
  console.log(item.name)
}
</script>

<style scoped>
.container {
  color: #42b883;
  margin: 0 auto;
}
</style>
