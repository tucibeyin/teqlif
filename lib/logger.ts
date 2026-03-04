/**
 * STRUCTURED LOGGER
 * Writes structured logs to separate files based on category.
 * - be_errors.log  : Backend API errors (endpoint, method, userId, stack)
 * - fe_errors.log  : Frontend errors sent via /api/log-error
 * - nextjs_errors.log : SSR/Server Component crashes
 * - livekit-error.log : LiveKit specific activity (existing)
 */

const LOG_DIR = '/var/www/teqlif.com/logs';

function writeToFile(filename: string, line: string) {
    try {
        const fs = require('fs');
        const path = require('path');
        const logFile = path.join(LOG_DIR, filename);

        fs.mkdir(LOG_DIR, { recursive: true }, (err: any) => {
            if (!err || err.code === 'EEXIST') {
                fs.appendFile(logFile, line + '\n', () => { });
            }
        });
    } catch (e) {
        // Silence — never crash the app due to logging
    }
}

function formatError(error: any): string {
    if (!error) return '';
    if (typeof error === 'string') return error;
    if (error instanceof Error) {
        return `${error.message}${error.stack ? ' | stack: ' + error.stack.split('\n').slice(0, 3).join(' ') : ''}`;
    }
    try {
        return JSON.stringify(error).substring(0, 800);
    } catch {
        return '[Unserializable Error]';
    }
}

export const logger = {
    info: function (message: string, context?: any) {
        console.log(`[INFO] ${message}`, context || '');
    },

    warn: function (message: string, context?: any) {
        console.warn(`[WARN] ${message}`, context || '');
    },

    /**
     * Log a backend API error.
     * Accepts either:
     *   - logger.error('message', rawError)             ← backward-compatible
     *   - logger.error('message', { endpoint, userId, error }) ← structured
     */
    error: function (
        message: string,
        optsOrError?: unknown
    ) {
        let endpoint = 'unknown';
        let method = 'unknown';
        let userId = 'anonymous';
        let errorVal: any = undefined;

        if (optsOrError !== null && typeof optsOrError === 'object' && !Array.isArray(optsOrError) && !(optsOrError instanceof Error)) {
            // Structured options object
            const opts = optsOrError as { endpoint?: string; method?: string; userId?: string; error?: any };
            endpoint = opts.endpoint || 'unknown';
            method = opts.method || 'unknown';
            userId = opts.userId || 'anonymous';
            errorVal = opts.error;
        } else {
            // Raw error passed directly (backward-compatible)
            errorVal = optsOrError;
        }

        const errorStr = formatError(errorVal);
        const line = `[${new Date().toISOString()}] ERROR | ${method.toUpperCase()} ${endpoint} | user:${userId} | ${message}${errorStr ? ' | ' + errorStr : ''}`;

        console.error(line);
        writeToFile('be_errors.log', line);
    },

    /**
     * Log a frontend error sent from the browser via /api/log-error.
     */
    frontendError: function (opts: {
        page: string;
        message: string;
        stack?: string;
        userAgent?: string;
        userId?: string;
    }) {
        const { page, message, stack, userAgent = 'unknown', userId = 'anonymous' } = opts;
        const line = `[${new Date().toISOString()}] FE ERROR | ${page} | user:${userId} | ${message}${stack ? ' | stack: ' + stack.substring(0, 400) : ''} | ua:${userAgent.substring(0, 100)}`;

        console.error(line);
        writeToFile('fe_errors.log', line);
    },

    /**
     * Log a Next.js SSR/Server Component crash.
     */
    ssrError: function (opts: {
        digest?: string;
        message?: string;
        stack?: string;
        url?: string;
    }) {
        const { digest = 'N/A', message = 'Unknown SSR error', stack, url = 'unknown' } = opts;
        const line = `[${new Date().toISOString()}] SSR ERROR | digest:${digest} | url:${url} | ${message}${stack ? ' | stack: ' + stack.substring(0, 600) : ''}`;

        console.error(line);
        writeToFile('nextjs_errors.log', line);
    },

    /**
     * Dedicated method for LiveKit events (existing, unchanged).
     */
    liveKit: function (level: 'INFO' | 'WARN' | 'ERROR', context: string, message: string, meta?: any) {
        const fullMsg = `[${context}] ${message}`;
        if (level === 'ERROR') {
            console.error(`[ERROR] ${fullMsg}`, meta || '');
        } else {
            console.log(`[${level}] ${fullMsg}`, meta || '');
        }

        let contextStr = '';
        if (meta) {
            try {
                contextStr = typeof meta === 'object' ? JSON.stringify(meta).substring(0, 500) : String(meta);
            } catch {
                contextStr = '[Unserializable Meta]';
            }
        }

        const line = `[${new Date().toISOString()}] ${level}: ${fullMsg}${contextStr ? ' ' + contextStr : ''}`;
        writeToFile('livekit-error.log', line);
    },
};

export default logger;
