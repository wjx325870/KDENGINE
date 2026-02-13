import { createClient } from '@supabase/supabase-js';
import Busboy from 'busboy';

// 从环境变量读取 Supabase 配置
const supabaseUrl = process.env.SUPABASE_URL;
const supabaseServiceKey = process.env.SUPABASE_SERVICE_KEY; // 使用 service role key（更安全）

export const config = {
  api: {
    bodyParser: false, // 禁用默认解析，由 busboy 处理文件
  },
};

export default async function handler(req, res) {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  // 初始化 Supabase 客户端
  const supabase = createClient(supabaseUrl, supabaseServiceKey);

  // 使用 busboy 解析 multipart/form-data
  const busboy = Busboy({ headers: req.headers });
  const uploadPromises = [];

  busboy.on('file', (fieldname, file, filename, encoding, mimetype) => {
    // 将文件流转换为 Buffer
    const chunks = [];
    file.on('data', (chunk) => chunks.push(chunk));
    file.on('end', async () => {
      const buffer = Buffer.concat(chunks);
      // 上传到 Supabase Storage（存储桶名称为 'mods'）
      const filePath = `pending/${Date.now()}_${filename}`;
      const { data, error } = await supabase.storage
        .from('mods')
        .upload(filePath, buffer, {
          contentType: mimetype,
        });
      if (error) {
        uploadPromises.push(Promise.reject(error));
      } else {
        // 获取公开 URL
        const { data: urlData } = supabase.storage
          .from('mods')
          .getPublicUrl(filePath);
        uploadPromises.push(
          Promise.resolve({
            filename,
            url: urlData.publicUrl,
            path: filePath,
          })
        );
      }
    });
  });

  busboy.on('finish', async () => {
    try {
      const results = await Promise.all(uploadPromises);
      // 可选：将元数据存入 Supabase 数据库表 'mods_metadata'
      // 这里只返回上传结果
      res.status(200).json({ success: true, files: results });
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  });

  req.pipe(busboy);
}
