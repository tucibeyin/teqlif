"use client";

import { useEffect, useState } from "react";
import Image from "next/image";
import Link from "next/link";
import { usePathname } from "next/navigation";

export function MobileGate() {
    const [isMobile, setIsMobile] = useState(false);
    const pathname = usePathname();

    useEffect(() => {
        // Sadece anasayfada bu kısıtlamayı yapmak istiyorsak bunu kullanırız, 
        // ancak tüm sitede mobilde bu ekranın çıkmasını istiyoruz.
        const checkMobile = () => {
            // 768px altı mobil cihaz kabul edilir
            if (window.innerWidth < 768) {
                setIsMobile(true);
                // Arkadaki kaydırmayı engelle
                document.body.style.overflow = 'hidden';
            } else {
                setIsMobile(false);
                document.body.style.overflow = '';
            }
        };

        // İlk yüklemede kontrol et
        checkMobile();

        // Ekran boyutu değiştiğinde kontrol et (örn. cihazı yan çevirme)
        window.addEventListener("resize", checkMobile);
        return () => {
            window.removeEventListener("resize", checkMobile);
            document.body.style.overflow = ''; // Cleanup
        };
    }, [pathname]); // Pathname'i ekleyerek sayfa geçişlerinde de kontrolü sağlarız

    if (!isMobile) return null;

    return (
        <div style={{
            position: "fixed",
            top: 0,
            left: 0,
            right: 0,
            bottom: 0,
            backgroundColor: "rgba(244, 247, 250, 0.70)", // var(--bg) with opacity
            backdropFilter: "blur(16px)",
            WebkitBackdropFilter: "blur(16px)",
            zIndex: 99999, // En üstte olması için
            display: "flex",
            flexDirection: "column",
            justifyContent: "space-between",
            padding: "2rem 1.5rem",
            overflowY: "auto" // İçerik sığmazsa kaydırılabilsin
        }}>
            {/* Logo Alanı */}
            <div style={{ display: "flex", justifyContent: "center", marginTop: "1rem" }}>
                <span style={{
                    fontSize: "2rem",
                    fontWeight: 800,
                    background: "linear-gradient(135deg, var(--primary), var(--primary-light))",
                    WebkitBackgroundClip: "text",
                    WebkitTextFillColor: "transparent"
                }}>
                    teqlif
                </span>
            </div>

            {/* Ana İçerik */}
            <div style={{ textAlign: "center", display: "flex", flexDirection: "column", alignItems: "center", gap: "1rem" }}>
                {/* Görsel/İkon Alanı (Dekoratif) */}
                <div style={{
                    width: "120px",
                    height: "120px",
                    background: "linear-gradient(135deg, rgba(0,188,212,0.1), rgba(0,188,212,0.2))",
                    borderRadius: "30%",
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    marginBottom: "1rem"
                }}>
                    <span style={{ fontSize: "4rem" }}>📱</span>
                </div>

                <h1 style={{
                    fontSize: "2rem",
                    fontWeight: 800,
                    lineHeight: 1.2,
                    color: "var(--text-primary)"
                }}>
                    Türkiye'nin En Büyük<br />
                    <span style={{ color: "var(--primary)" }}>İlan Platformu</span>
                </h1>

                <p style={{
                    fontSize: "1rem",
                    lineHeight: 1.5,
                    color: "var(--text-secondary)",
                    padding: "0 1rem"
                }}>
                    Kategori ve konum seçerek saniyeler içinde ilan ver. Açık artırmaya katıl, en iyi teklifleri ver.
                </p>

                <p style={{
                    fontSize: "0.875rem",
                    fontWeight: 600,
                    color: "var(--text-primary)",
                    marginTop: "1rem",
                    background: "var(--bg-secondary)",
                    padding: "0.5rem 1rem",
                    borderRadius: "100px"
                }}>
                    Deneyime hemen uygulamadan devam edin.
                </p>
            </div>

            {/* İndirme Butonları */}
            <div style={{ display: "flex", flexDirection: "column", gap: "1rem", marginTop: "2rem" }}>
                <a href="#" className="btn" style={{
                    backgroundColor: "#000",
                    color: "#fff",
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    gap: "1rem",
                    padding: "1rem",
                    borderRadius: "var(--radius-lg)",
                    textDecoration: "none"
                }}>
                    <svg viewBox="0 0 384 512" fill="currentColor" style={{ width: "24px", height: "24px" }}>
                        <path d="M318.7 268.7c-.2-36.7 16.4-64.4 50-84.8-18.8-26.9-47.2-41.7-84.1-44.6-35.9-2.8-74.3 22.7-93.1 22.7-18.9 0-46.3-21-76-21-39.2 0-76.3 23-96.6 59.6-41.1 74.6-11.5 185.1 28.5 242.7 19.3 27.6 42 56.6 71.3 55.4 28.2-1.2 39.2-18.3 73-18.3 33.6 0 44.1 18.2 73.1 17.8 30.6-.4 50.1-26.4 69.1-54.8 23.3-34.8 32.8-68.5 33.3-70.3-4.2-2.1-48.4-18.7-48.3-64.4zM263.8 89.2c16.1-19.4 27.2-46.5 24.3-73.4-23.7 1-52.6 15.8-69.3 35.5-14.8 17.5-27.4 45.4-24 71.9 26.2 2 52.8-14.6 69-34z" />
                    </svg>
                    <div style={{ textAlign: "left" }}>
                        <div style={{ fontSize: "0.75rem", opacity: 0.8 }}>Download on the</div>
                        <div style={{ fontSize: "1.25rem", fontWeight: 600 }}>App Store</div>
                    </div>
                </a>
                <a href="#" className="store-btn" style={{ background: "black", color: "white", padding: "0.875rem 1.5rem", borderRadius: "var(--radius-full)", textDecoration: "none", display: "flex", alignItems: "center", gap: "0.75rem", fontWeight: 600, fontSize: "1rem" }}>
                    <Image src="https://upload.wikimedia.org/wikipedia/commons/d/d0/Google_Play_Arrow_logo.svg" alt="Play Store" width={24} height={24} style={{ filter: "brightness(0) invert(1)" }} />
                    <div style={{ textAlign: "left" }}>
                        <div style={{ fontSize: "0.75rem", opacity: 0.8 }}>GET IT ON</div>
                        <div style={{ fontSize: "1.25rem", fontWeight: 600 }}>Google Play</div>
                    </div>
                </a>
            </div>
        </div>
    );
}
