import type { Metadata } from "next";
import "./globals.css";
import { Navbar } from "@/components/Navbar";
import { Providers } from "./providers";
import { GlobalChatWidget } from "@/components/GlobalChatWidget";

export const metadata: Metadata = {
  title: "teqlif - İlan ve Açık Artırma Platformu",
  description: "Türkiye'nin en büyük ilan ve açık artırma platformu. Kategori ve konum seçerek kolayca ilan ver, teklif al.",
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
          <Navbar />
          <main>{children}</main>
          <GlobalChatWidget />
          <footer className="footer">
            <div className="container">
              <span className="footer-logo">teqlif</span>
              <p>© 2026 teqlif. Tüm hakları saklıdır.</p>
            </div>
          </footer>
        </Providers>
      </body>
    </html>
  );
}
