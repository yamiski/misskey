<!--
SPDX-FileCopyrightText: syuilo and misskey-project
SPDX-License-Identifier: AGPL-3.0-only
-->

<template>
<div :class="$style.root">
	<input v-model="query" :class="$style.input" type="search" :placeholder="q">
	<button :class="$style.button" @click="search"><i class="ti ti-search"></i> {{ i18n.ts.searchByGoogle }}</button>
</div>
</template>

<script lang="ts" setup>
import { ref } from 'vue';
import { i18n } from '@/i18n.js';
import { defaultStore } from '@/store';

const props = defineProps<{
	q: string;
}>();

const query = ref(props.q);

const search = () => {
	const sp = new URLSearchParams();
	sp.append('q', query.value);
	window.open(`${defaultStore.state.searchEngine}${sp.toString()}`, '_blank', 'noopener');
};
</script>

<style lang="scss" module>
.root {
	display: flex;
	margin: 8px 0;
}

.input {
	flex-shrink: 1;
	padding: 10px;
	width: 100%;
	height: 40px;
	font-size: 16px;
	border: solid 1px var(--MI_THEME-divider);
	border-radius: 4px 0 0 4px;
	-webkit-appearance: textfield;
}

.button {
	flex-shrink: 0;
	margin: 0;
	padding: 0 16px;
	border: solid 1px var(--MI_THEME-divider);
	border-left: none;
	border-radius: 0 4px 4px 0;

	&:active {
		box-shadow: 0 2px 4px rgba(#000, 0.15) inset;
	}
}
</style>
