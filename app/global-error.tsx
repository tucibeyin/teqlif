'use client';

import logger from '@/lib/logger';

interface GlobalErrorProps {
    error: Error & { digest?: string };
    reset: () => void;
}

/**
 * Next.js Global Error Boundary for App Router.
 * Catches unhandled Server Component render errors.
 * Logs the error + Digest to nextjs_errors.log on the VPS.
 */
export default function GlobalError({ error, reset }: GlobalErrorProps) {
    // Log the error server-side via a fetch call
    // (global-error.tsx runs on client, so we fire and forget to the log endpoint)
    if (typeof window !== 'undefined') {
        try {
            fetch('/api/log-error', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    page: window.location.pathname,
                    message: `SSR Error | digest:${error.digest || 'N/A'} | ${error.message}`,
                    stack: error.stack,
                    userAgent: navigator.userAgent,
                }),
            }).catch(() => { });
        } catch { }
    }

    return (
        <html>
            <body style={{
                display: 'flex',
                flexDirection: 'column',
                alignItems: 'center',
                justifyContent: 'center',
                minHeight: '100vh',
                fontFamily: 'system-ui, sans-serif',
                background: '#f0fdfa',
                color: '#0f766e',
                gap: '1rem',
                padding: '2rem',
                textAlign: 'center',
            }}>
                <div style={{ fontSize: '3rem' }}>⚠️</div>
                <h1 style={{ fontSize: '1.5rem', fontWeight: 700, margin: 0 }}>
                    Bir Hata Oluştu
                </h1>
                <p style={{ color: '#374151', maxWidth: '400px', margin: 0 }}>
                    Sayfa yüklenirken beklenmedik bir hata oluştu. Lütfen tekrar deneyin.
                </p>
                {error.digest && (
                    <code style={{ fontSize: '0.75rem', color: '#6b7280', background: '#f3f4f6', padding: '4px 8px', borderRadius: '4px' }}>
                        Hata Kodu: {error.digest}
                    </code>
                )}
                <button
                    onClick={reset}
                    style={{
                        marginTop: '0.5rem',
                        padding: '10px 24px',
                        background: '#0d9488',
                        color: 'white',
                        border: 'none',
                        borderRadius: '8px',
                        fontWeight: 600,
                        cursor: 'pointer',
                        fontSize: '0.95rem',
                    }}
                >
                    Tekrar Dene
                </button>
            </body>
        </html>
    );
}
