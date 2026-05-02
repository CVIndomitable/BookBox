import { PrismaClient } from '@prisma/client';
import apn from 'apn';

const prisma = new PrismaClient();

let apnProvider = null;

// 初始化 APNs
export function initAPNs() {
  const apnKeyPath = process.env.APN_KEY_PATH;
  const apnKeyId = process.env.APN_KEY_ID;
  const apnTeamId = process.env.APN_TEAM_ID;
  const apnTopic = process.env.APN_TOPIC;

  if (!apnKeyPath || !apnKeyId || !apnTeamId || !apnTopic) {
    console.warn('APNs 配置不完整，推送功能将不可用');
    return;
  }

  try {
    apnProvider = new apn.Provider({
      token: {
        key: apnKeyPath,
        keyId: apnKeyId,
        teamId: apnTeamId
      },
      production: process.env.NODE_ENV === 'production'
    });
    console.log('APNs 初始化成功');
  } catch (error) {
    console.error('APNs 初始化失败:', error);
  }
}

// 发送推送通知
export async function sendPushNotification(apnsToken, title, body, data = {}) {
  if (!apnProvider) {
    console.warn('APNs 未初始化，跳过推送');
    return { success: false, error: 'APNs not initialized' };
  }

  const notification = new apn.Notification();
  notification.alert = { title, body };
  notification.sound = 'default';
  notification.badge = 1;
  notification.topic = process.env.APN_TOPIC;
  notification.payload = data;

  try {
    const result = await apnProvider.send(notification, apnsToken);
    if (result.failed.length > 0) {
      console.error('推送失败:', result.failed);
      return { success: false, error: result.failed[0].response };
    }
    return { success: true };
  } catch (error) {
    console.error('推送异常:', error);
    return { success: false, error: error.message };
  }
}

// 检查并发送晒书提醒
export async function checkAndSendSunReminders() {
  try {
    const now = new Date();
    const reminders = await prisma.sunReminder.findMany({
      where: {
        nextSunAt: { lte: now },
        notified: false
      },
      include: {
        user: {
          select: { apnsToken: true }
        }
      }
    });

    console.log(`找到 ${reminders.length} 条待发送的晒书提醒`);

    for (const reminder of reminders) {
      if (!reminder.user.apnsToken) {
        console.log(`用户 ${reminder.userId} 未设置 APNs token，跳过`);
        continue;
      }

      const title = '晒书提醒';
      const body = `${reminder.targetName} 该晒书啦！`;
      const data = {
        type: 'sun_reminder',
        reminderId: reminder.id,
        targetType: reminder.targetType,
        targetId: reminder.targetId
      };

      const result = await sendPushNotification(reminder.user.apnsToken, title, body, data);

      if (result.success) {
        await prisma.sunReminder.update({
          where: { id: reminder.id },
          data: { notified: true }
        });
        console.log(`晒书提醒 ${reminder.id} 推送成功`);
      } else {
        console.error(`晒书提醒 ${reminder.id} 推送失败:`, result.error);
      }
    }
  } catch (error) {
    console.error('检查晒书提醒失败:', error);
  }
}

// 启动定时任务（每小时检查一次）
export function startSunReminderScheduler() {
  const interval = parseInt(process.env.SUN_REMINDER_INTERVAL_MS) || 3600000; // 默认 1 小时
  setInterval(checkAndSendSunReminders, interval);
  console.log(`晒书提醒定时任务已启动，间隔 ${interval / 1000} 秒`);

  // 启动时立即检查一次
  checkAndSendSunReminders();
}
