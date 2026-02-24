'use client';

import { useState, useEffect } from 'react';

export function MobileAppBanner() {
    const [isVisible, setIsVisible] = useState(false);

    useEffect(() => {
        // Sadece client side'da çalışsın
        if (typeof window === 'undefined') return;

        // Kullanıcı daha önce kapatmış mı?
        const isDismissed = localStorage.getItem('appBannerDismissed');
        if (isDismissed) return;

        // Basit bir mobil tarayıcı kontrolü (User Agent)
        const userAgent = navigator.userAgent || navigator.vendor || (window as any).opera;
        const isMobile = /android|ipad|playbook|silk/i.test(userAgent) || /iphone|ipod/i.test(userAgent) || /windows phone/i.test(userAgent);

        if (isMobile) {
            setIsVisible(true);
        }
    }, []);

    if (!isVisible) return null;

    const handleDismiss = () => {
        setIsVisible(false);
        localStorage.setItem('appBannerDismissed', 'true');
    };

    return (
        <div className="fixed top-0 left-0 right-0 z-50 bg-gradient-to-r from-teal-500 to-cyan-500 text-white px-4 py-3 flex items-center shadow-md">
            <button
                onClick={handleDismiss}
                className="mr-3 p-1 rounded-full hover:bg-white/20 transition-colors"
                aria-label="Kapat"
            >
                <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
                </svg>
            </button>

            <div className="flex-1 flex items-center min-w-0">
                <div className="w-10 h-10 bg-white rounded-lg flex items-center justify-center mr-3 flex-shrink-0 text-cyan-600 font-bold text-xl shadow-sm">
                    t
                </div>
                <div className="flex flex-col min-w-0">
                    <span className="font-semibold text-sm truncate">teqlif uygulamasını indir</span>
                    <span className="text-xs text-teal-100 truncate">Daha iyi bir deneyim için</span>
                </div>
            </div>

            <div className="flex flex-col gap-2 ml-3 flex-shrink-0">
                <a
                    href="#"
                    className="bg-white text-cyan-600 rounded-md shadow-sm flex items-center justify-center w-8 h-8 hover:bg-teal-50 transition-colors"
                    aria-label="App Store'dan İndir"
                >
                    <svg viewBox="0 0 384 512" fill="currentColor" className="w-5 h-5">
                        <path d="M318.7 268.7c-.2-36.7 16.4-64.4 50-84.8-18.8-26.9-47.2-41.7-84.1-44.6-35.9-2.8-74.3 22.7-93.1 22.7-18.9 0-46.3-21-76-21-39.2 0-76.3 23-96.6 59.6-41.1 74.6-11.5 185.1 28.5 242.7 19.3 27.6 42 56.6 71.3 55.4 28.2-1.2 39.2-18.3 73-18.3 33.6 0 44.1 18.2 73.1 17.8 30.6-.4 50.1-26.4 69.1-54.8 23.3-34.8 32.8-68.5 33.3-70.3-4.2-2.1-48.4-18.7-48.3-64.4zM263.8 89.2c16.1-19.4 27.2-46.5 24.3-73.4-23.7 1-52.6 15.8-69.3 35.5-14.8 17.5-27.4 45.4-24 71.9 26.2 2 52.8-14.6 69-34z" />
                    </svg>
                </a>
                <a
                    href="#"
                    className="bg-white text-cyan-600 rounded-md shadow-sm flex items-center justify-center w-8 h-8 hover:bg-teal-50 transition-colors"
                    aria-label="Google Play'den Edinin"
                >
                    <svg viewBox="0 0 512 512" fill="currentColor" className="w-4 h-4">
                        <path d="M325.3 234.3L104.6 13l280.8 161.2-60.1 60.1zM47 0C34 6.8 25.3 19.2 25.3 35.3v441.3c0 16.1 8.7 28.5 21.7 35.3l256.6-256L47 0zm425.2 225.6l-58.9-34.1-65.7 64.5 65.7 64.5 60.1-34.1c18-14.3 18-46.5-1.2-60.8zM104.6 499l280.8-161.2-60.1-60.1L104.6 499z" />
                    </svg>
                </a>
            </div>
        </div>
    );
}
