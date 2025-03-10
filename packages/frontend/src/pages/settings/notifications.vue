<!--
SPDX-FileCopyrightText: syuilo and misskey-project
SPDX-License-Identifier: AGPL-3.0-only
-->

<template>
	<div class="_gaps_m">
		<FormSection first>
			<template #label>{{ i18n.ts.notificationRecieveConfig }}</template>
			<div class="_gaps_s">
				<MkFolder v-for="type in filteredNotificationTypes" :key="type">
					<template #label>{{ i18n.ts._notification._types[type] }}</template>
					<template #suffix>
						{{
							getNotificationConfigValue(type).type === 'never' ? i18n.ts.none :
								getNotificationConfigValue(type).type === 'following' ? i18n.ts.following :
									getNotificationConfigValue(type).type === 'follower' ? i18n.ts.followers :
										getNotificationConfigValue(type).type === 'mutualFollow' ? i18n.ts.mutualFollow :
											getNotificationConfigValue(type).type === 'followingOrFollower' ? i18n.ts.followingOrFollower :
												getNotificationConfigValue(type).type === 'list' ? i18n.ts.userList :
													i18n.ts.all
						}}
					</template>

					<XNotificationConfig :userLists="userLists" :value="getNotificationConfigValue(type)"
						:configurableTypes="onlyOnOrOffNotificationTypes.includes(type) ? ['all', 'never'] : undefined"
						@update="(res) => updateReceiveConfig(type, res)" />
				</MkFolder>
			</div>
		</FormSection>
		<FormSection>
			<div class="_gaps_m">
				<FormLink @click="readAllNotifications">{{ i18n.ts.markAsReadAllNotifications }}</FormLink>
				<FormLink @click="readAllUnreadNotes">{{ i18n.ts.markAsReadAllUnreadNotes }}</FormLink>
			</div>
		</FormSection>
		<FormSection>
			<div class="_gaps_m">
				<FormLink @click="testNotification">{{ i18n.ts._notification.sendTestNotification }}</FormLink>
				<FormLink @click="flushNotification">{{ i18n.ts._notification.flushNotification }}</FormLink>
			</div>
		</FormSection>
		<FormSection>
			<template #label>{{ i18n.ts.pushNotification }}</template>

			<div class="_gaps_m">
				<MkPushNotificationAllowButton ref="allowButton" />
				<MkSwitch :disabled="!pushRegistrationInServer" :modelValue="sendReadMessage"
					@update:modelValue="onChangeSendReadMessage">
					<template #label>{{ i18n.ts.sendPushNotificationReadMessage }}</template>
					<template #caption>
						<I18n :src="i18n.ts.sendPushNotificationReadMessageCaption">
							<template #emptyPushNotificationMessage>{{ i18n.ts._notification.emptyPushNotificationMessage
								}}</template>
						</I18n>
					</template>
				</MkSwitch>
			</div>
		</FormSection>
	</div>
</template>

<script lang="ts" setup>
import { shallowRef, computed } from 'vue';
import XNotificationConfig, { type NotificationConfig } from './notifications.notification-config.vue';
import FormLink from '@/components/form/link.vue';
import FormSection from '@/components/form/section.vue';
import MkFolder from '@/components/MkFolder.vue';
import MkSwitch from '@/components/MkSwitch.vue';
import * as os from '@/os.js';
import { signinRequired } from '@/account.js';
import { misskeyApi } from '@/scripts/misskey-api.js';
import { i18n } from '@/i18n.js';
import { definePageMetadata } from '@/scripts/page-metadata.js';
import MkPushNotificationAllowButton from '@/components/MkPushNotificationAllowButton.vue';
import { notificationTypes } from '@@/js/const.js';

const $i = signinRequired();

const nonConfigurableNotificationTypes = ['note', 'roleAssigned', 'followRequestAccepted', 'test', 'exportCompleted'] satisfies (typeof notificationTypes[number])[] as string[];

const onlyOnOrOffNotificationTypes = ['app', 'achievementEarned', 'login'] satisfies (typeof notificationTypes[number])[] as string[];

const allowButton = shallowRef<InstanceType<typeof MkPushNotificationAllowButton>>();
const pushRegistrationInServer = computed(() => allowButton.value?.pushRegistrationInServer);
const sendReadMessage = computed(() => pushRegistrationInServer.value?.sendReadMessage || false);
const userLists = await misskeyApi('users/lists/list');

const canQuote = $i.policies.canChangeQuoteNotificationSetting;

const filteredNotificationTypes = computed(() => {
    return notificationTypes.filter(type => {
        // 設定不可能な通知タイプを除外
        if (nonConfigurableNotificationTypes.includes(type)) {
            return false;
        }

        // 各通知タイプに対応するポリシーに基づいたフィルタリング
        if (type === 'quote' && !$i.policies.canChangeQuoteNotificationSetting) {
            return false;
        }

        if (type === 'unfollow' && !$i.policies.canChangeUnfollowNotificationSetting) {
            return false;
        }

        if (type === 'blocked' && !$i.policies.canChangeBlockedNotificationSetting) {
            return false;
        }

        if (type === 'unblocked' && !$i.policies.canChangeUnblockedNotificationSetting) {
            return false;
        }

        return true;
    });
});

// 通知設定の値を取得するヘルパー関数
function getNotificationConfigValue(type) {
	// unfollow, blocked, unblocked で設定がない場合は never をデフォルトにする
	if ((type === 'unfollow' || type === 'blocked' || type === 'unblocked') && !$i.notificationRecieveConfig[type]) {
		return { type: 'never' };
	}
	// その他はデフォルトで all
	return $i.notificationRecieveConfig[type] ?? { type: 'all' };
}

async function readAllUnreadNotes() {
	await os.apiWithDialog('i/read-all-unread-notes');
}

async function readAllNotifications() {
	await os.apiWithDialog('notifications/mark-all-as-read');
}

async function updateReceiveConfig(type: typeof notificationTypes[number], value: NotificationConfig) {
	await os.apiWithDialog('i/update', {
		notificationRecieveConfig: {
			...$i.notificationRecieveConfig,
			[type]: value,
		},
	}).then(i => {
		$i.notificationRecieveConfig = i.notificationRecieveConfig;
	});
}

function onChangeSendReadMessage(v: boolean) {
	if (!pushRegistrationInServer.value) return;

	os.apiWithDialog('sw/update-registration', {
		endpoint: pushRegistrationInServer.value.endpoint,
		sendReadMessage: v,
	}).then(res => {
		if (!allowButton.value) return;
		allowButton.value.pushRegistrationInServer = res;
	});
}

function testNotification(): void {
	misskeyApi('notifications/test-notification');
}

async function flushNotification() {
	const { canceled } = await os.confirm({
		type: 'warning',
		text: i18n.ts.resetAreYouSure,
	});

	if (canceled) return;

	os.apiWithDialog('notifications/flush');
}

const headerActions = computed(() => []);

const headerTabs = computed(() => []);

definePageMetadata(() => ({
	title: i18n.ts.notifications,
	icon: 'ti ti-bell',
}));
</script>
