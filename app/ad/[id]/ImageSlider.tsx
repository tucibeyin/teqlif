"use client";
import { useState } from "react";
import Lightbox from "yet-another-react-lightbox";
import Zoom from "yet-another-react-lightbox/plugins/zoom";
import "yet-another-react-lightbox/styles.css";

export default function ImageSlider({ images, title }: { images: string[], title: string }) {
    const [currentIndex, setCurrentIndex] = useState(0);
    const [lightboxOpen, setLightboxOpen] = useState(false);

    if (!images || images.length === 0) return null;

    const slides = images.map((src) => ({ src }));

    const nextImage = () => {
        setCurrentIndex((prev) => (prev + 1) % images.length);
    };

    const prevImage = () => {
        setCurrentIndex((prev) => (prev === 0 ? images.length - 1 : prev - 1));
    };

    return (
        <div style={{ display: "flex", flexDirection: "column", gap: "1rem" }}>
            <div style={{ position: "relative", width: "100%", height: "400px", borderRadius: "var(--radius-lg)", overflow: "hidden", background: "var(--bg-secondary)", border: "1px solid var(--border)", boxShadow: "var(--shadow-sm)" }}>
                <img
                    src={images[currentIndex]}
                    alt={`${title} - Görsel ${currentIndex + 1}`}
                    onClick={() => setLightboxOpen(true)}
                    style={{ width: "100%", height: "100%", objectFit: "contain", background: "#f8fafb", cursor: "zoom-in" }}
                />

                {images.length > 1 && (
                    <>
                        <button
                            onClick={prevImage}
                            style={{ position: "absolute", left: "10px", top: "50%", transform: "translateY(-50%)", background: "rgba(255,255,255,0.8)", color: "var(--text-primary)", border: "1px solid var(--border)", borderRadius: "50%", width: "40px", height: "40px", cursor: "pointer", display: "flex", alignItems: "center", justifyContent: "center", fontSize: "1.2rem", boxShadow: "var(--shadow-md)", transition: "var(--transition)" }}
                            onMouseOver={(e) => e.currentTarget.style.background = "white"}
                            onMouseOut={(e) => e.currentTarget.style.background = "rgba(255,255,255,0.8)"}
                        >
                            ❮
                        </button>
                        <button
                            onClick={nextImage}
                            style={{ position: "absolute", right: "10px", top: "50%", transform: "translateY(-50%)", background: "rgba(255,255,255,0.8)", color: "var(--text-primary)", border: "1px solid var(--border)", borderRadius: "50%", width: "40px", height: "40px", cursor: "pointer", display: "flex", alignItems: "center", justifyContent: "center", fontSize: "1.2rem", boxShadow: "var(--shadow-md)", transition: "var(--transition)" }}
                            onMouseOver={(e) => e.currentTarget.style.background = "white"}
                            onMouseOut={(e) => e.currentTarget.style.background = "rgba(255,255,255,0.8)"}
                        >
                            ❯
                        </button>
                    </>
                )}
            </div>

            {images.length > 1 && (
                <div style={{ display: "flex", gap: "0.5rem", overflowX: "auto", paddingBottom: "0.5rem" }}>
                    {images.map((img, i) => (
                        <img
                            key={i}
                            src={img}
                            alt={`Küçük Resim ${i + 1}`}
                            onClick={() => setCurrentIndex(i)}
                            style={{
                                width: "80px",
                                height: "80px",
                                objectFit: "cover",
                                borderRadius: "var(--radius-sm)",
                                cursor: "pointer",
                                border: i === currentIndex ? "2.5px solid var(--primary)" : "1px solid var(--border)",
                                opacity: i === currentIndex ? 1 : 0.6,
                                transition: "var(--transition)"
                            }}
                        />
                    ))}
                </div>
            )}

            <Lightbox
                open={lightboxOpen}
                close={() => setLightboxOpen(false)}
                index={currentIndex}
                slides={slides}
                plugins={[Zoom]}
                on={{ view: ({ index: i }) => setCurrentIndex(i) }}
                zoom={{
                    maxZoomPixelRatio: 3,
                    zoomInMultiplier: 2,
                    doubleTapDelay: 300,
                    doubleClickDelay: 300,
                    doubleClickMaxStops: 2,
                    keyboardMoveDistance: 50,
                    wheelZoomDistanceFactor: 100,
                    pinchZoomDistanceFactor: 100,
                    scrollToZoom: false,
                }}
                carousel={{
                    finite: images.length <= 1,
                }}
            />
        </div>
    );
}
