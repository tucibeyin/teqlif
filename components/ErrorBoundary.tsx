'use client';

import React from 'react';

interface Props {
    children: React.ReactNode;
}

interface State {
    hasError: boolean;
}

export class ErrorBoundary extends React.Component<Props, State> {
    constructor(props: Props) {
        super(props);
        this.state = { hasError: false };
    }

    static getDerivedStateFromError(): State {
        return { hasError: true };
    }

    componentDidCatch(error: Error, info: React.ErrorInfo) {
        // Send to log-error endpoint (fire-and-forget)
        try {
            fetch('/api/log-error', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    page: typeof window !== 'undefined' ? window.location.pathname : 'unknown',
                    message: error.message,
                    stack: error.stack,
                    userAgent: navigator.userAgent,
                }),
            }).catch(() => { });
        } catch { }
    }

    render() {
        if (this.state.hasError) {
            // Let Next.js handle the error UI — don't override
            throw new Error('ErrorBoundary caught a render error');
        }
        return this.props.children;
    }
}
