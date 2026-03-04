'use client';

import { useEffect } from 'react';

/**
 * Installs global window.onerror and unhandledrejection listeners
 * that forward uncaught browser errors to /api/log-error.
 * 
 * Must be a Client Component, placed inside the root layout.
 */
export function GlobalErrorCapture() {
    useEffect(() => {
        function sendError(message: string, stack?: string) {
            try {
                fetch('/api/log-error', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({
                        page: window.location.pathname,
                        message: message.substring(0, 500),
                        stack: stack?.substring(0, 800),
                        userAgent: navigator.userAgent,
                    }),
                }).catch(() => { });
            } catch { }
        }

        const onError = (event: ErrorEvent) => {
            sendError(event.message, event.error?.stack);
        };

        const onUnhandledRejection = (event: PromiseRejectionEvent) => {
            const reason = event.reason;
            const message = reason instanceof Error ? reason.message : String(reason);
            sendError(`UnhandledRejection: ${message}`, reason?.stack);
        };

        window.addEventListener('error', onError);
        window.addEventListener('unhandledrejection', onUnhandledRejection);

        return () => {
            window.removeEventListener('error', onError);
            window.removeEventListener('unhandledrejection', onUnhandledRejection);
        };
    }, []);

    return null;
}
