import { preferences } from '@kit.ArkData';

// 运动记录数据模型 - 与 sport_record 表字段一一对应
@Observed
export class SportRecord {
  id: string;
  sport_name: string;
  duration: number;
  calories: number;
  sport_date: string;
  create_time: string;
  completed: boolean;

  constructor(id: string, sport_name: string, duration: number, calories: number,
    sport_date: string, create_time: string, completed: boolean = false) {
    this.id = id;
    this.sport_name = sport_name;
    this.duration = duration;
    this.calories = calories;
    this.sport_date = sport_date;
    this.create_time = create_time;
    this.completed = completed;
  }
}

export class SportDataManager {
  private static instance: SportDataManager | null = null;
  private pref: preferences.Preferences | null = null;
  private records: SportRecord[] = [];

  private constructor() {}

  static getInstance(): SportDataManager {
    if (SportDataManager.instance === null) {
      SportDataManager.instance = new SportDataManager();
    }
    return SportDataManager.instance;
  }

  init(context: Context): void {
    try {
      this.pref = preferences.getPreferencesSync(context, { name: 'sport_data' });
      const data = this.pref.getSync('records', '[]') as string;
      if (data && data.length > 0) {
        const raw = JSON.parse(data) as Array<Record<string, Object>>;
        if (Array.isArray(raw)) {
          this.records = raw.map(r => new SportRecord(
            String(r.id ?? ''),
            String(r.sport_name ?? ''),
            Number(r.duration) || 0,
            Number(r.calories) || 0,
            String(r.sport_date ?? ''),
            String(r.create_time ?? ''),
            r.completed === true ? true : false
          ));
          return;
        }
      }
      this.records = [];
    } catch (err) {
      console.error('初始化运动数据失败:', JSON.stringify(err));
      this.records = [];
    }
  }

  getRecords(): SportRecord[] {
    return this.records;
  }

  getTodayRecords(): SportRecord[] {
    const today = this.formatDate(new Date());
    return this.records.filter(r => r.sport_date === today);
  }

  getRecordsByDate(date: string): SportRecord[] {
    return this.records.filter(r => r.sport_date === date);
  }

  getWeekRecords(days: Date[]): SportRecord[] {
    const dates = days.map(d => this.formatDate(d));
    return this.records.filter(r => dates.includes(r.sport_date));
  }

  async addRecord(record: SportRecord): Promise<void> {
    this.records.push(record);
    await this.save();
  }

  async deleteRecord(id: string): Promise<void> {
    this.records = this.records.filter(r => r.id !== id);
    await this.save();
  }

  async clearAll(): Promise<void> {
    this.records = [];
    await this.save();
  }

  async save(): Promise<void> {
    if (!this.pref) return;
    this.pref.putSync('records', JSON.stringify(this.records));
    await this.pref.flush();
  }

  formatDate(date: Date): string {
    const y = date.getFullYear();
    const m = String(date.getMonth() + 1).padStart(2, '0');
    const d = String(date.getDate()).padStart(2, '0');
    return `${y}-${m}-${d}`;
  }

  formatDateTime(date: Date): string {
    const y = date.getFullYear();
    const m = String(date.getMonth() + 1).padStart(2, '0');
    const d = String(date.getDate()).padStart(2, '0');
    const h = String(date.getHours()).padStart(2, '0');
    const min = String(date.getMinutes()).padStart(2, '0');
    const s = String(date.getSeconds()).padStart(2, '0');
    return `${y}-${m}-${d} ${h}:${min}:${s}`;
  }
}
