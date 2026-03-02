import fs from 'fs';
import path from 'path';

// Logların kaydedileceği dosya yolu. Proje kök dizininde 'logs' klasöründe tutulacak.
const LOG_DIR = path.join(process.cwd(), 'logs');
const LOG_FILE = path.join(LOG_DIR, 'livekit-error.log');

// Klasör yoksa oluştur
if (!fs.existsSync(LOG_DIR)) {
    try {
        fs.mkdirSync(LOG_DIR, { recursive: true });
    } catch (e) {
        console.error("Log klasörü oluşturulamadı:", e);
    }
}

type LogLevel = 'INFO' | 'WARN' | 'ERROR';

/**
 * Merkezi LiveKit Loglama Sistemi
 * Hataları ve önemli olayları VPS üzerindeki fiziksel bir dosyaya yazar.
 */
class LiveKitLogger {
    private static _formatMessage(level: LogLevel, context: string, message: string, meta?: any): string {
        const timestamp = new Date().toISOString();
        let logLine = `[${timestamp}] [${level}] [${context}] ${message}`;
        if (meta) {
            if (meta instanceof Error) {
                logLine += ` \n   -> Error: ${meta.message}\n   -> Stack: ${meta.stack}`;
            } else {
                logLine += ` \n   -> Meta: ${JSON.stringify(meta)}`;
            }
        }
        return logLine + '\n';
    }

    private static _writeToFile(logLine: string) {
        try {
            fs.appendFileSync(LOG_FILE, logLine, 'utf8');
        } catch (e) {
            console.error("Log dosyasına yazılamadı:", e);
        }
    }

    static info(context: string, message: string, meta?: any) {
        const logLine = this._formatMessage('INFO', context, message, meta);
        console.log(logLine.trim());
        this._writeToFile(logLine);
    }

    static warn(context: string, message: string, meta?: any) {
        const logLine = this._formatMessage('WARN', context, message, meta);
        console.warn(logLine.trim());
        this._writeToFile(logLine);
    }

    static error(context: string, message: string, meta?: any) {
        const logLine = this._formatMessage('ERROR', context, message, meta);
        console.error(logLine.trim());
        this._writeToFile(logLine);
    }
}

export const logger = LiveKitLogger;
export default LiveKitLogger;
