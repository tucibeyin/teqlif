// Simple in-memory logger for "live log" visibility
type LogEntry = {
    timestamp: string;
    level: 'INFO' | 'WARN' | 'ERROR';
    message: string;
    context?: any;
};

const MAX_LOGS = 100;
let logs: LogEntry[] = [];

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

        console.log(`[${entry.timestamp}] ${level}: ${message}`, context ? JSON.stringify(context) : '');

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
    }
};
