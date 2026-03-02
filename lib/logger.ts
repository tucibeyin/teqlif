/**
 * ULTRA-SIMPLE NON-BLOCKING LOGGER
 * Designed to be as safe as possible for VPS environments.
 */
export const logger = {
    info: function (m: string, c?: any) {
        console.log(`[INFO] ${m}`, c || '');
    },

    warn: function (m: string, c?: any) {
        console.warn(`[WARN] ${m}`, c || '');
    },

    error: function (m: string, c?: any) {
        console.error(`[ERROR] ${m}`, c || '');
        this._writeFile('ERROR', m, c);
    },

    /**
     * Dedicated method for LiveKit events.
     * Writes ALL levels (INFO/ERROR) to the physical log file for visibility.
     */
    liveKit: function (level: 'INFO' | 'WARN' | 'ERROR', context: string, message: string, meta?: any) {
        const fullMsg = `[${context}] ${message}`;
        if (level === 'ERROR') {
            console.error(`[ERROR] ${fullMsg}`, meta || '');
        } else {
            console.log(`[${level}] ${fullMsg}`, meta || '');
        }

        // Write LiveKit activity to file regardless of level for monitoring
        this._writeFile(level, fullMsg, meta);
    },

    /**
     * Internal safe file writer (Async/Non-blocking)
     */
    _writeFile: function (level: string, m: string, c?: any) {
        try {
            const fs = require('fs');
            const path = require('path');
            const logDir = path.join(process.cwd(), 'logs');
            const logFile = path.join(logDir, 'livekit-error.log');

            let contextStr = '';
            if (c) {
                try {
                    contextStr = typeof c === 'object' ? JSON.stringify(c).substring(0, 500) : String(c);
                } catch (e) {
                    contextStr = '[Unserializable Context]';
                }
            }

            const logLine = `[${new Date().toISOString()}] ${level}: ${m} ${contextStr}\n`;

            fs.mkdir(logDir, { recursive: true }, (err: any) => {
                if (!err || err.code === 'EEXIST') {
                    fs.appendFile(logFile, logLine, () => { });
                }
            });
        } catch (e) {
            // Silence
        }
    }
};

export default logger;
