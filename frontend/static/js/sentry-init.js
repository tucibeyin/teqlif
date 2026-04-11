if (typeof Sentry !== 'undefined') {
    Sentry.init({
        dsn: "https://98dfdd738860420a9c221abf4ddf35cb@o4511052861538304.ingest.us.sentry.io/4511053913391104",
        integrations: [
            Sentry.browserTracingIntegration(),
        ],
        tracesSampleRate: 1.0,
    });
}
