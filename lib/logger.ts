import fs from 'fs';
import path from 'path';

// Simple in-memory and file-based logger for VPS terminal visibility
type LogEntry = {
    timestamp: string;
    level: 'INFO' | 'WARN' | 'ERROR';
    message: string;
    context?: any;
};

const MAX_LOGS = 100;
let logs: LogEntry[] = [];
const LOG_DIR = path.join(process.cwd(), 'logs');
const LOG_FILE = path.join(LOG_DIR, 'app.log');

// Ensure logs directory exists
if (!fs.existsSync(LOG_DIR)) {
    fs.mkdirSync(LOG_DIR, { recursive: true });
}

export const logger = {
    info(message: string, context?: any) {
        this._log('INFO', message, context);
    },
    warn(message: string, context?: any) {
        this._log('WARN', message, context);
    },
    error(message: string, context?: any) {
        this._log('ERROR', message, context);
    },
    _log(level: LogEntry['level'], message: string, context?: any) {
        const entry: LogEntry = {
            timestamp: new Date().toISOString(),
            level,
            message,
            context
        };

        const logLine = `[${entry.timestamp}] ${level}: ${message}${context ? ' ' + JSON.stringify(context) : ''}\n`;

        // Write to stdout for process managers (like PM2)
        process.stdout.write(logLine);

        // Write to physical file for tail -f
        try {
            fs.appendFileSync(LOG_FILE, logLine);
        } catch (e) {
            console.error('Failed to write to log file', e);
        }

        logs.unshift(entry);
        if (logs.length > MAX_LOGS) {
            logs = logs.slice(0, MAX_LOGS);
        }
    },
    getLogs() {
        return logs;
    },
    clear() {
        logs = [];
        if (fs.existsSync(LOG_FILE)) {
            try {
                fs.writeFileSync(LOG_FILE, '');
            } catch (e) {
                console.error('Failed to clear log file', e);
            }
        }
    }
};
