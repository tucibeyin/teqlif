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
const LIVEKIT_LOG_FILE = path.join(LOG_DIR, 'livekit-error.log');

// Ensure logs directory exists
if (!fs.existsSync(LOG_DIR)) {
    try {
        fs.mkdirSync(LOG_DIR, { recursive: true });
    } catch (e) {
        console.error('Failed to create log directory', e);
    }
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
    /**
     * LiveKit specific error logging
     */
    liveKit(level: 'INFO' | 'WARN' | 'ERROR', context: string, message: string, meta?: any) {
        const timestamp = new Date().toISOString();
        const logLine = `[${timestamp}] [${level}] [${context}] ${message}${meta ? ' ' + JSON.stringify(meta) : ''}\n`;

        // Write to both general log and livekit specific log
        this._log(level, `[${context}] ${message}`, meta);

        try {
            fs.appendFileSync(LIVEKIT_LOG_FILE, logLine);
        } catch (e) {
            console.error('Failed to write to livekit log file', e);
        }
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
        if (level === 'ERROR') {
            process.stderr.write(logLine);
        } else {
            process.stdout.write(logLine);
        }

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

export default logger;

