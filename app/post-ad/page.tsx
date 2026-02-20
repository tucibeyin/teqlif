"use client";
import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import { provinces, allDistricts } from "@/lib/locations";
import { categories } from "@/lib/categories";

export default function PostAdPage() {
    const router = useRouter();
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState("");
    const [selectedProvince, setSelectedProvince] = useState("");
    const [districts, setDistricts] = useState<{ id: string; name: string }[]>([]);

    useEffect(() => {
        if (selectedProvince) {
            setDistricts(allDistricts[selectedProvince] ?? []);
        }
    }, [selectedProvince]);

    async function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
        e.preventDefault();
        setLoading(true);
        setError("");
        const fd = new FormData(e.currentTarget);

        const uploadedImages: string[] = [];
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
                            uploadedImages.push(upData.url);
                        }
                    }
                } catch (err) {
                    console.error("Upload error:", err);
                }
            }
        }

        const res = await fetch("/api/ads", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                title: fd.get("title"),
                description: fd.get("description"),
                price: Number(fd.get("price")),
                categorySlug: fd.get("categorySlug"),
                provinceId: fd.get("provinceId"),
                districtId: fd.get("districtId"),
                images: uploadedImages,
            }),
        });

        const data = await res.json();
        setLoading(false);

        if (!res.ok) {
            setError(data.error || "İlan eklenirken hata oluştu.");
            return;
        }

        router.push(`/ad/${data.id}`);
    }

    return (
        <div className="post-ad-page">
            <div className="container">
                <div className="post-ad-card">
                    <h1 className="form-title">📋 İlan Ver</h1>

                    <form onSubmit={handleSubmit}>
                        {error && <div className="error-msg" style={{ marginBottom: "1rem" }}>{error}</div>}

                        {/* Başlık & Kategori */}
                        <div className="form-section">
                            <h3 style={{ color: "var(--text-secondary)", fontSize: "0.8125rem", fontWeight: 600, textTransform: "uppercase", letterSpacing: "0.05em" }}>
                                İlan Bilgileri
                            </h3>
                            <div className="form-group">
                                <label htmlFor="title">İlan Başlığı *</label>
                                <input id="title" name="title" type="text" className="input"
                                    placeholder="Ör: iPhone 15 Pro 256GB" required maxLength={100} />
                            </div>
                            <div className="form-group">
                                <label htmlFor="categorySlug">Kategori *</label>
                                <select id="categorySlug" name="categorySlug" className="input" required defaultValue="">
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
                                <textarea id="description" name="description" className="input"
                                    placeholder="İlanınızı detaylıca açıklayın..." rows={5} required />
                            </div>
                        </div>

                        {/* Fiyat */}
                        <div className="form-section">
                            <h3 style={{ color: "var(--text-secondary)", fontSize: "0.8125rem", fontWeight: 600, textTransform: "uppercase", letterSpacing: "0.05em" }}>
                                Fiyat
                            </h3>
                            <div className="form-group">
                                <label htmlFor="price">Fiyat (₺) *</label>
                                <input id="price" name="price" type="number" className="input"
                                    placeholder="0" min={1} step={1} required />
                            </div>
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
                                        defaultValue=""
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
                                        defaultValue=""
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
                            <div className="form-group">
                                <label htmlFor="images">İlan fotoğraflarını seçiniz (Birden fazla seçinebilirsiniz)</label>
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

                        <button type="submit" className="btn btn-primary btn-full btn-lg" disabled={loading}>
                            {loading ? "İlan yayınlanıyor..." : "🚀 İlanı Yayınla"}
                        </button>
                    </form>
                </div>
            </div>
        </div>
    );
}
