import { createClient } from '@supabase/supabase-js';

const supabaseUrl = process.env.SUPABASE_URL;
const supabaseAnonKey = process.env.SUPABASE_ANON_KEY;  // 使用 anon key

export default async function handler(req, res) {
  // 只允许 GET 请求
  if (req.method !== 'GET') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  // 初始化 Supabase 客户端（使用 anon key）
  const supabase = createClient(supabaseUrl, supabaseAnonKey);

  // 从 'mods' 表中查询所有公开的模组（按创建时间倒序）
  const { data, error } = await supabase
    .from('mods')
    .select('*')
    .order('created_at', { ascending: false });

  if (error) {
    console.error('Supabase query error:', error);
    return res.status(500).json({ error: 'Database query failed' });
  }

  // 返回 JSON 数组
  res.status(200).json(data);
}
