import { validateUpload, saveFile, MAX_UPLOAD_BYTES } from './storage';
import * as fs from 'fs';
import * as path from 'path';

describe('Storage service hardening', () => {
  it('rejects empty payloads', () => {
    const res = validateUpload(Buffer.alloc(0), 'image/jpeg');
    expect(res.valid).toBe(false);
    expect(res.error).toMatch(/Empty file/i);
  });

  it('rejects files exceeding the maximum size limit (10MB)', () => {
    const oversized = Buffer.alloc(MAX_UPLOAD_BYTES + 1024);
    const res = validateUpload(oversized, 'image/jpeg');
    expect(res.valid).toBe(false);
    expect(res.error).toMatch(/exceeds maximum limit/i);
  });

  it('rejects forbidden/executable MIME types', () => {
    const buf = Buffer.from('console.log("malicious")');
    const res = validateUpload(buf, 'application/javascript');
    expect(res.valid).toBe(false);
    expect(res.error).toMatch(/Unsupported MIME type/i);
  });

  it('accepts valid emergency image attachments and saves locally in fallback mode', async () => {
    const dummyImage = Buffer.from('FAKE_JPEG_IMAGE_CONTENT');
    const result = await saveFile(dummyImage, 'image/jpeg', 'test-incident.jpg');

    expect(result).toBeDefined();
    expect(result.sizeBytes).toBe(dummyImage.length);
    expect(result.mimeType).toBe('image/jpeg');
    expect(result.url).toMatch(/^\/uploads\/[0-9a-f-]+\.jpg$/i);

    // Verify local file exists
    const uploadsDir = path.resolve(process.cwd(), 'uploads');
    const filePath = path.join(uploadsDir, result.storageKey);
    expect(fs.existsSync(filePath)).toBe(true);

    // Clean up test file
    try {
      fs.unlinkSync(filePath);
    } catch {}
  });
});
