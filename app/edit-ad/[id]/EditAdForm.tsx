"use client";
import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import { provinces, allDistricts } from "@/lib/locations";
import { categories } from "@/lib/categories";

export default function EditAdForm({ ad }: { ad: any }) {
    const router = useRouter();
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState("");
    const [selectedProvince, setSelectedProvince] = useState(ad.provinceId);
    const [districts, setDistricts] = useState<{ id: string; name: string }[]>([]);
    const [displayPrice, setDisplayPrice] = useState(() => new Intl.NumberFormat("tr-TR").format(ad.price));
    const [displayMinBidStep, setDisplayMinBidStep] = useState(() => new Intl.NumberFormat("tr-TR").format(ad.minBidStep || 100));
    const [displayBuyItNowPrice, setDisplayBuyItNowPrice] = useState(() => ad.buyItNowPrice ? new Intl.NumberFormat("tr-TR").format(ad.buyItNowPrice) : "");
    const [existingImages, setExistingImages] = useState<string[]>(ad.images || []);
    const [isFixedPrice, setIsFixedPrice] = useState(ad.isFixedPrice || false);
    const [showPhone, setShowPhone] = useState(ad.showPhone || false);

    useEffect(() => {
        let isMounted = true;
        if (selectedProvince) {
            const syncDistricts = async () => {
                if (isMounted) setDistricts(allDistricts[selectedProvince] ?? []);
            };
            syncDistricts();
        }
        return () => { isMounted = false; };
    }, [selectedProvince]);

    async function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
        e.preventDefault();
        setLoading(true);
        setError("");
        const fd = new FormData(e.currentTarget);

        const finalImages = [...existingImages];
        const fileInput = document.getElementById("images") as HTMLInputElement;

        if (fileInput && fileInput.files && fileInput.files.length > 0) {
            for (let i = 0; i < fileInput.files.length; i++) {
                const fileForm = new FormData();
                fileForm.append("file", fileInput.files[i]);

                try {
                    const uploadRes = await fetch("/api/upload", {
                        method: "POST",
                        body: fileForm,
                    });

                    if (uploadRes.ok) {
                        const upData = await uploadRes.json();
                        if (upData.url) {
                            finalImages.push(upData.url);
                        }
                    }
                } catch (err) {
                    console.error("Upload error:", err);
                }
            }
        }

        const rawStartingBid = document.getElementById("actualStartingBid") ? (document.getElementById("actualStartingBid") as HTMLInputElement).value : "";
        const parsedStartingBid = rawStartingBid ? Number(rawStartingBid) : null;

        const res = await fetch(`/api/ads/${ad.id}`, {
            method: "PUT",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                title: fd.get("title"),
                description: fd.get("description"),
                price: Number(fd.get("price")),
                isFixedPrice,
                startingBid: parsedStartingBid,
                minBidStep: Number(fd.get("minBidStep")),
                buyItNowPrice: document.getElementById("buyItNowInput") && (document.getElementById("actualBuyItNowPrice") as HTMLInputElement).value
                    ? Number((document.getElementById("actualBuyItNowPrice") as HTMLInputElement).value)
                    : null,
                showPhone,
                categorySlug: fd.get("categorySlug"),
                provinceId: fd.get("provinceId"),
                districtId: fd.get("districtId"),
                images: finalImages,
            }),
        });

        const data = await res.json();
        setLoading(false);

        if (!res.ok) {
            setError(data.error || "İlan güncellenirken hata oluştu.");
            return;
        }

        router.push(`/ad/${data.id}`);
    }

    const removeImage = (indexToRemove: number) => {
        setExistingImages(existingImages.filter((_, i) => i !== indexToRemove));
    };

    return (
        <div className="post-ad-page">
            <div className="container">
                <div className="post-ad-card">
                    <h1 className="form-title">✏️ İlanı Düzenle</h1>

                    <form onSubmit={handleSubmit}>
                        {error && <div className="error-msg" style={{ marginBottom: "1rem" }}>{error}</div>}

                        {/* Başlık & Kategori */}
                        <div className="form-section">
                            <h3 style={{ color: "var(--text-secondary)", fontSize: "0.8125rem", fontWeight: 600, textTransform: "uppercase", letterSpacing: "0.05em" }}>
                                İlan Bilgileri
                            </h3>
                            <div className="form-group">
                                <label htmlFor="title">İlan Başlığı *</label>
                                <input id="title" name="title" type="text" className="input" defaultValue={ad.title} required maxLength={100} />
                            </div>
                            <div className="form-group">
                                <label htmlFor="categorySlug">Kategori *</label>
                                <select id="categorySlug" name="categorySlug" className="input" required defaultValue={ad.category.slug}>
                                    <option value="" disabled>Kategori seçin</option>
                                    {categories.map((cat) => (
                                        <option key={cat.slug} value={cat.slug}>
                                            {cat.icon} {cat.name}
                                        </option>
                                    ))}
                                </select>
                            </div>
                            <div className="form-group">
                                <label htmlFor="description">Açıklama *</label>
                                <textarea id="description" name="description" className="input" defaultValue={ad.description} rows={5} required />
                            </div>
                        </div>

                        {/* Fiyat & Teklif Tipi */}
                        <div className="form-section">
                            <h3 style={{ color: "var(--text-secondary)", fontSize: "0.8125rem", fontWeight: 600, textTransform: "uppercase", letterSpacing: "0.05em" }}>
                                Fiyat ve Teklif Kuralları
                            </h3>

                            <div className="form-group" style={{ marginBottom: "1.5rem" }}>
                                <label style={{ display: "block", marginBottom: "0.5rem", fontWeight: 600 }}>İlan Tipi Seçin</label>
                                <div style={{ display: "flex", gap: "1rem", flexDirection: "column" }}>
                                    <label style={{ display: "flex", alignItems: "center", gap: "0.5rem", cursor: "pointer", background: "var(--bg-secondary)", padding: "1rem", borderRadius: "var(--radius-md)", border: "1px solid var(--border)" }}>
                                        <input type="radio" name="mainAdStyle" value="auction" checked={!isFixedPrice} onChange={() => setIsFixedPrice(false)} />
                                        <span>
                                            <strong style={{ display: "block", marginBottom: "0.25rem" }}>Açık Artırma İlanı</strong>
                                            <span style={{ fontSize: "0.875rem", color: "var(--text-muted)" }}>İlanınız tekliflere açık olur ve ürün en yüksek teklifi verene satılır.</span>
                                        </span>
                                    </label>
                                    <label style={{ display: "flex", alignItems: "center", gap: "0.5rem", cursor: "pointer", background: "var(--bg-secondary)", padding: "1rem", borderRadius: "var(--radius-md)", border: "1px solid var(--border)" }}>
                                        <input type="radio" name="mainAdStyle" value="fixed" checked={isFixedPrice} onChange={() => setIsFixedPrice(true)} />
                                        <span>
                                            <strong style={{ display: "block", marginBottom: "0.25rem" }}>Sabit Fiyatlı İlan</strong>
                                            <span style={{ fontSize: "0.875rem", color: "var(--text-muted)" }}>Tekliflere kapalıdır, doğrudan belirlediğiniz fiyattan listeleyip satabilirsiniz.</span>
                                        </span>
                                    </label>
                                </div>
                            </div>

                            {!isFixedPrice && (
                                <div className="form-group" style={{ marginBottom: "1.5rem" }}>
                                    <div style={{ fontSize: "0.875rem", color: "var(--text-muted)", background: "var(--bg-secondary)", padding: "1rem", borderRadius: "var(--radius-md)", border: "1px solid var(--border)" }}>
                                        <strong>Nasıl İşler?</strong> İlanınıza teklif verilebilir durumdadır. İster bir başlangıç teklifi belirleyebilir (Örn: 5000 ₺), isterseniz boş bırakarak serbest pazar fiyatlamasına (1 ₺'den başlar) izin verebilirsiniz.
                                    </div>
                                </div>
                            )}

                            <div className="form-row">
                                <div className="form-group">
                                    <label htmlFor="price">{isFixedPrice ? "Satış Fiyatı (₺) *" : "Piyasa Fiyatı / Değeri (₺) *"}</label>
                                    <div style={{ position: "relative", display: "flex", alignItems: "center" }}>
                                        <input
                                            type="text"
                                            className="input"
                                            placeholder="0"
                                            value={displayPrice}
                                            onChange={(e) => {
                                                const val = e.target.value.replace(/[^0-9]/g, "");
                                                if (!val) setDisplayPrice("");
                                                else setDisplayPrice(new Intl.NumberFormat("tr-TR").format(parseInt(val, 10)));
                                            }}
                                            required
                                            style={{ paddingRight: "3rem" }}
                                        />
                                        <span style={{ position: "absolute", right: "1rem", color: "var(--text-muted)", pointerEvents: "none" }}>,00</span>
                                    </div>
                                    <input type="hidden" name="price" value={displayPrice.replace(/\./g, "")} />
                                </div>

                                <div className="form-group" id="startingBidWrapper" style={{ display: isFixedPrice ? "none" : "block" }}>
                                    <label htmlFor="startingBid">Açılış Teklifi (₺) <span className="text-muted">(İsteğe Bağlı)</span></label>
                                    <div style={{ position: "relative", display: "flex", alignItems: "center" }}>
                                        <input
                                            type="text"
                                            className="input"
                                            name="startingBidDummy" // Sadece frontend UI için
                                            id="startingBidInput"
                                            defaultValue={ad.startingBid !== null ? new Intl.NumberFormat("tr-TR").format(ad.startingBid) : ""}
                                            placeholder="Örn: 5000"
                                            onChange={(e) => {
                                                const val = e.target.value.replace(/[^0-9]/g, "");
                                                if (!val) e.target.value = "";
                                                else e.target.value = new Intl.NumberFormat("tr-TR").format(parseInt(val, 10));
                                                document.getElementById("actualStartingBid")!.setAttribute("value", val);
                                            }}
                                            style={{ paddingRight: "3rem" }}
                                        />
                                        <span style={{ position: "absolute", right: "1rem", color: "var(--text-muted)", pointerEvents: "none" }}>,00</span>
                                    </div>
                                    <input type="hidden" name="startingBid" id="actualStartingBid" value={ad.startingBid !== null ? ad.startingBid.toString() : ""} />
                                </div>
                            </div>

                            {!isFixedPrice && (
                                <>
                                    <div className="form-group" style={{ marginTop: "1rem" }}>
                                        <label htmlFor="minBidStepInput">Pey Aralığı (Minimum Artış) (₺) *</label>
                                        <div style={{ position: "relative", display: "flex", alignItems: "center" }}>
                                            <input
                                                type="text"
                                                className="input"
                                                name="minBidStepDummy"
                                                id="minBidStepInput"
                                                defaultValue={ad.minBidStep ? new Intl.NumberFormat("tr-TR").format(ad.minBidStep) : "100"}
                                                placeholder="Örn: 100"
                                                onChange={(e) => {
                                                    const val = e.target.value.replace(/[^0-9]/g, "");
                                                    if (!val) {
                                                        setDisplayMinBidStep("");
                                                        e.target.value = "";
                                                    } else {
                                                        const formatted = new Intl.NumberFormat("tr-TR").format(parseInt(val, 10));
                                                        setDisplayMinBidStep(formatted);
                                                        e.target.value = formatted;
                                                    }
                                                }}
                                                required
                                                style={{ paddingRight: "3rem" }}
                                            />
                                            <span style={{ position: "absolute", right: "1rem", color: "var(--text-muted)", pointerEvents: "none" }}>,00</span>
                                        </div>
                                        <input type="hidden" name="minBidStep" value={displayMinBidStep.replace(/\./g, "") || "100"} />
                                        <div style={{ fontSize: "0.8125rem", color: "var(--text-muted)", marginTop: "0.5rem" }}>
                                            Teklif verenlerin tutarı en az bu değer kadar artırması gerekecektir.
                                        </div>
                                    </div>

                                    <div className="form-group" style={{ marginTop: "1.5rem", padding: "1rem", border: "1px dashed var(--border)", borderRadius: "var(--radius-md)", background: "var(--bg-secondary)" }}>
                                        <label htmlFor="buyItNowInput">Hemen Al Fiyatı (₺) <span className="text-muted">(Opsiyonel)</span></label>
                                        <div style={{ position: "relative", display: "flex", alignItems: "center", marginBottom: "0.25rem" }}>
                                            <input
                                                type="text"
                                                className="input"
                                                name="buyItNowDummy"
                                                id="buyItNowInput"
                                                placeholder="Örn: 7500"
                                                value={displayBuyItNowPrice}
                                                onChange={(e) => {
                                                    const val = e.target.value.replace(/[^0-9]/g, "");
                                                    if (!val) setDisplayBuyItNowPrice("");
                                                    else setDisplayBuyItNowPrice(new Intl.NumberFormat("tr-TR").format(parseInt(val, 10)));
                                                    document.getElementById("actualBuyItNowPrice")!.setAttribute("value", val);
                                                }}
                                                style={{ paddingRight: "3rem" }}
                                            />
                                            <span style={{ position: "absolute", right: "1rem", color: "var(--text-muted)", pointerEvents: "none" }}>,00</span>
                                        </div>
                                        <input type="hidden" name="buyItNowPrice" id="actualBuyItNowPrice" value={ad.buyItNowPrice !== null ? ad.buyItNowPrice.toString() : ""} />
                                        <div style={{ fontSize: "0.8125rem", color: "var(--text-muted)" }}>
                                        </div>
                                    </div>
                                </>
                            )}
                        </div>

                        {/* Konum */}
                        <div className="form-section">
                            <h3 style={{ color: "var(--text-secondary)", fontSize: "0.8125rem", fontWeight: 600, textTransform: "uppercase", letterSpacing: "0.05em" }}>
                                Konum
                            </h3>
                            <div className="form-row">
                                <div className="form-group">
                                    <label htmlFor="provinceId">İl *</label>
                                    <select
                                        id="provinceId"
                                        name="provinceId"
                                        className="input"
                                        required
                                        value={selectedProvince}
                                        onChange={(e) => setSelectedProvince(e.target.value)}
                                    >
                                        <option value="" disabled>İl seçin</option>
                                        {provinces.map((p) => (
                                            <option key={p.id} value={p.id}>{p.name}</option>
                                        ))}
                                    </select>
                                </div>
                                <div className="form-group">
                                    <label htmlFor="districtId">İlçe *</label>
                                    <select
                                        id="districtId"
                                        name="districtId"
                                        className="input"
                                        required
                                        defaultValue={ad.districtId}
                                        disabled={!selectedProvince}
                                    >
                                        <option value="" disabled>
                                            {selectedProvince ? "İlçe seçin" : "Önce il seçin"}
                                        </option>
                                        {districts.map((d) => (
                                            <option key={d.id} value={d.id}>{d.name}</option>
                                        ))}
                                    </select>
                                </div>
                            </div>
                        </div>

                        {/* Görsel */}
                        <div className="form-section">
                            <h3 style={{ color: "var(--text-secondary)", fontSize: "0.8125rem", fontWeight: 600, textTransform: "uppercase", letterSpacing: "0.05em" }}>
                                Fotoğraf
                            </h3>

                            {existingImages.length > 0 && (
                                <div style={{ marginBottom: "1rem" }}>
                                    <label style={{ display: "block", marginBottom: "0.5rem", fontSize: "0.875rem", fontWeight: 600 }}>Mevcut Fotoğraflar</label>
                                    <div style={{ display: "flex", gap: "0.5rem", flexWrap: "wrap" }}>
                                        {existingImages.map((img, i) => (
                                            <div key={i} style={{ position: "relative", width: "80px", height: "80px" }}>
                                                <img src={img} alt="Uploaded" style={{ width: "100%", height: "100%", objectFit: "cover", borderRadius: "var(--radius-sm)", border: "1px solid var(--border)" }} />
                                                <button
                                                    type="button"
                                                    onClick={() => removeImage(i)}
                                                    style={{ position: "absolute", top: "-5px", right: "-5px", background: "var(--accent-red)", color: "white", border: "none", borderRadius: "50%", width: "20px", height: "20px", cursor: "pointer", display: "flex", alignItems: "center", justifyContent: "center", fontSize: "10px" }}
                                                >
                                                    ✕
                                                </button>
                                            </div>
                                        ))}
                                    </div>
                                </div>
                            )}

                            <div className="form-group">
                                <label htmlFor="images">Yeni fotoğraf ekle (İsteğe bağlı, birden fazla seçebilirsiniz)</label>
                                <input
                                    id="images"
                                    name="images"
                                    type="file"
                                    multiple
                                    accept="image/*"
                                    className="input"
                                    style={{
                                        padding: "1rem",
                                        background: "white",
                                        border: "2px dashed var(--border)",
                                        cursor: "pointer"
                                    }}
                                />
                            </div>
                        </div>

                        {/* İletişim Tercihleri */}
                        <div className="form-section">
                            <h3 style={{ color: "var(--text-secondary)", fontSize: "0.8125rem", fontWeight: 600, textTransform: "uppercase", letterSpacing: "0.05em" }}>
                                İletişim Tercihleri
                            </h3>
                            <div className="form-group">
                                <label style={{ display: "flex", alignItems: "center", gap: "0.5rem", cursor: "pointer", background: "var(--bg-secondary)", padding: "1rem", borderRadius: "var(--radius-md)", border: "1px solid var(--border)" }}>
                                    <input type="checkbox" name="showPhone" checked={showPhone} onChange={(e) => setShowPhone(e.target.checked)} />
                                    <span>
                                        <strong style={{ display: "block", marginBottom: "0.25rem" }}>Telefon Numaram İlanda Gösterilsin</strong>
                                        <span style={{ fontSize: "0.875rem", color: "var(--text-muted)" }}>İşaretlemezseniz, alıcılar sizinle sadece sistem üzerinden mesajlaşarak iletişim kurabilir.</span>
                                    </span>
                                </label>
                            </div>
                        </div>

                        <button type="submit" className="btn btn-primary btn-full btn-lg" disabled={loading}>
                            {loading ? "Güncelleniyor..." : "💾 Değişiklikleri Kaydet"}
                        </button>
                    </form>
                </div>
            </div>
        </div>
    );
}
