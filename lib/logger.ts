/**
 * ULTRA-SIMPLE NON-BLOCKING LOGGER
 * Designed to be as safe as possible for VPS environments.
 */
export const logger = {
    info: (m: string, c?: any) => {
        console.log(`[INFO] ${m}`, c || '');
    },

    warn: (m: string, c?: any) => {
        console.warn(`[WARN] ${m}`, c || '');
    },

    error: (m: string, c?: any) => {
        console.error(`[ERROR] ${m}`, c || '');

        // Asynchronous and safe file logging (only for errors)
        try {
            const fs = require('fs');
            const path = require('path');
            const logDir = path.join(process.cwd(), 'logs');
            const logFile = path.join(logDir, 'livekit-error.log');

            // Extract a simple message from error objects if present
            let contextStr = '';
            if (c) {
                try {
                    contextStr = typeof c === 'object' ? JSON.stringify(c).substring(0, 500) : String(c);
                } catch (e) {
                    contextStr = '[Unserializable Context]';
                }
            }

            const logLine = `[${new Date().toISOString()}] ERROR: ${m} ${contextStr}\n`;

            // Use async mkdir and append to prevent blocking the event loop
            fs.mkdir(logDir, { recursive: true }, (err: any) => {
                if (!err || err.code === 'EEXIST') {
                    fs.appendFile(logFile, logLine, () => { });
                }
            });
        } catch (e) {
            // Absolute silence on logger failure to prevent loops
        }
    },

    liveKit: function (level: 'INFO' | 'WARN' | 'ERROR', context: string, message: string, meta?: any) {
        if (level === 'ERROR') {
            this.error(`[${context}] ${message}`, meta);
        } else {
            this.info(`[${context}] ${message}`, meta);
        }
    }
};

export default logger;
