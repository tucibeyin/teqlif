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

            <div className="flex flex-col gap-1 ml-3 flex-shrink-0">
                <a
                    href="#"
                    className="bg-white text-cyan-600 text-[10px] font-bold py-1 px-3 rounded-md shadow-sm text-center hover:bg-teal-50 transition-colors"
                >
                    App Store
                </a>
                <a
                    href="#"
                    className="bg-white text-cyan-600 text-[10px] font-bold py-1 px-3 rounded-md shadow-sm text-center hover:bg-teal-50 transition-colors"
                >
                    Google Play
                </a>
            </div>
        </div>
    );
}
