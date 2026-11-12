export interface ParseResult {
  sportName: string;
  duration: number;
  calories: number;
}

const SPORT_KEYWORDS: Record<string, string> = {
  '跑步': '跑步', '跑': '跑步',
  '游泳': '游泳', '游': '游泳',
  '骑行': '骑行', '骑': '骑行',
  '健身': '健身',
  '瑜伽': '瑜伽',
  '跳绳': '跳绳',
  '走路': '走路', '步行': '走路', '走': '走路',
  '篮球': '篮球', '打篮球': '篮球',
  '足球': '足球', '踢球': '足球',
  '羽毛球': '羽毛球', '打球': '羽毛球',
  '爬山': '爬山', '登山': '爬山',
  '乒乓球': '乒乓球',
  '网球': '网球',
  '拳击': '拳击',
  '跳舞': '跳舞',
  '滑雪': '滑雪',
  '滑冰': '滑冰',
  '举铁': '举铁', '力量训练': '举铁'
};

// 中文数字映射表
const CN_NUM_MAP: Record<string, number> = {
  '零': 0, '一': 1, '二': 2, '三': 3, '四': 4,
  '五': 5, '六': 6, '七': 7, '八': 8, '九': 9,
  '十': 10, '百': 100
};

function chineseToNumber(cn: string): number {
  let result: number = 0;
  let current: number = 0;
  for (let i = 0; i < cn.length; i++) {
    const char: string = cn[i];
    const val: number = CN_NUM_MAP[char] ?? -1;
    if (val < 0) {
      continue;
    }
    if (val >= 10) {
      if (current === 0) {
        current = 1;
      }
      result += current * val;
      current = 0;
    } else {
      current = val;
    }
  }
  result += current;
  return result;
}

export class SportVoiceParser {
  static parse(voiceText: string): ParseResult {
    const text = voiceText.trim();
    if (text.length === 0) {
      return { sportName: '', duration: 0, calories: 0 } as ParseResult;
    }

    // 1. 匹配运动类型
    let sportName: string = '';
    const keys: string[] = Object.keys(SPORT_KEYWORDS);
    for (let i = 0; i < keys.length; i++) {
      if (text.includes(keys[i])) {
        sportName = SPORT_KEYWORDS[keys[i]];
        break;
      }
    }
    if (sportName.length === 0) {
      sportName = '运动';
    }

    // 2. 提取时长（支持"10分钟"和"十分钟"两种格式）
    let duration: number = 0;

    // 先尝试阿拉伯数字格式
    const hourMatch = text.match(/(\d+)\s*小\s*时/);
    if (hourMatch) {
      duration = parseInt(hourMatch[1]) * 60;
    }
    const minMatch = text.match(/(\d+)\s*分\s*(?:钟|)/);
    if (minMatch) {
      duration += parseInt(minMatch[1]);
    }

    // 如果还没匹配到，再尝试中文数字格式
    if (duration === 0) {
      // 中文"小时"匹配：如"半小时"、"一小时"
      if (text.includes('半') && text.includes('小时')) {
        duration = 30;
      } else {
        // 匹配"X小时Y分钟"中的中文小时数
        const cnHourMatch = text.match(/([一二三四五六七八九十百]+)\s*小\s*时/);
        if (cnHourMatch) {
          duration = chineseToNumber(cnHourMatch[1]) * 60;
        }
        // 匹配"X分钟"中的中文分钟数
        const cnMinMatch = text.match(/([一二三四五六七八九十百]+)\s*分\s*(?:钟|)/);
        if (cnMinMatch) {
          duration += chineseToNumber(cnMinMatch[1]);
        }
      }
    }

    // 3. 提取卡路里（支持阿拉伯数字和中文数字）
    let calories: number = 0;
    const calMatch = text.match(/(\d+)\s*(?:千卡|大卡|卡路里|卡)/);
    if (calMatch) {
      calories = parseInt(calMatch[1]);
    } else {
      const cnCalMatch = text.match(/([一二三四五六七八九十百]+)\s*(?:千卡|大卡|卡路里|卡)/);
      if (cnCalMatch) {
        calories = chineseToNumber(cnCalMatch[1]);
      }
    }

    return { sportName: sportName, duration: duration, calories: calories } as ParseResult;
  }
}
