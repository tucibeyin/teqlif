import type { Metadata } from "next";
import "./globals.css";
import { Navbar } from "@/components/Navbar";
import { Providers } from "./providers";
import { GlobalChatWidget } from "@/components/GlobalChatWidget";
import { MobileAppBanner } from "@/components/MobileAppBanner";
import { MobileGate } from "@/components/MobileGate";
import Link from "next/link";

export const metadata: Metadata = {
  title: "teqlif - İlan ve Açık Artırma Platformu",
  description: "Türkiye'nin en büyük ilan ve açık artırma platformu. Kategori ve konum seçerek kolayca ilan ver, teklif al.",
};

export const viewport = {
  width: "device-width",
  initialScale: 1,
  maximumScale: 1,
  userScalable: false,
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="tr">
      <head>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="anonymous" />
      </head>
      <body>
        <Providers>
          <MobileGate />
          <MobileAppBanner />
          <Navbar />
          <main>{children}</main>
          <GlobalChatWidget />
          <footer className="footer">
            <div className="container">
              <div className="footer-premium-app">
                <div className="footer-premium-app-content">
                  <span className="footer-premium-app-badge">Mobil Uygulama</span>
                  <h3 className="footer-premium-app-title">teqlif Cebinizde</h3>
                  <p className="footer-premium-app-desc">
                    Türkiye'nin en gelişmiş ilan uygulaması ile her an her yerde fırsatları yakalayın.
                  </p>
                </div>
                <div className="footer-premium-app-links">
                  <a href="#" className="gate-store-btn" style={{ background: 'white' }}>
                    <svg viewBox="0 0 384 512" fill="currentColor">
                      <path d="M318.7 268.7c-.2-36.7 16.4-64.4 50-84.8-18.8-26.9-47.2-41.7-84.1-44.6-35.9-2.8-74.3 22.7-93.1 22.7-18.9 0-46.3-21-76-21-39.2 0-76.3 23-96.6 59.6-41.1 74.6-11.5 185.1 28.5 242.7 19.3 27.6 42 56.6 71.3 55.4 28.2-1.2 39.2-18.3 73-18.3 33.6 0 44.1 18.2 73.1 17.8 30.6-.4 50.1-26.4 69.1-54.8 23.3-34.8 32.8-68.5 33.3-70.3-4.2-2.1-48.4-18.7-48.3-64.4zM263.8 89.2c16.1-19.4 27.2-46.5 24.3-73.4-23.7 1-52.6 15.8-69.3 35.5-14.8 17.5-27.4 45.4-24 71.9 26.2 2 52.8-14.6 69-34z" />
                    </svg>
                    App Store
                  </a>
                  <a href="#" className="gate-store-btn" style={{ background: 'white' }}>
                    <svg viewBox="0 0 512 512" fill="currentColor">
                      <path d="M325.3 234.3L104.6 13l280.8 161.2-60.1 60.1zM47 0C34 6.8 25.3 19.2 25.3 35.3v441.3c0 16.1 8.7 28.5 21.7 35.3l256.6-256L47 0zm425.2 225.6l-58.9-34.1-65.7 64.5 65.7 64.5 60.1-34.1c18-14.3 18-46.5-1.2-60.8zM104.6 499l280.8-161.2-60.1-60.1L104.6 499z" />
                    </svg>
                    Google Play
                  </a>
                </div>
              </div>

              <div className="footer-bottom">
                <span className="footer-logo">teqlif</span>
                <div className="footer-links" style={{ display: 'flex', gap: '1rem', alignItems: 'center' }}>
                  <Link href="/gizlilik-politikasi" className="text-gray-500 hover:text-cyan-600 text-sm transition-colors">
                    Gizlilik Politikası
                  </Link>
                  <p>© 2026 teqlif. Tüm hakları saklıdır.</p>
                </div>
              </div>
            </div>
          </footer>
        </Providers>
      </body>
    </html>
  );
}
