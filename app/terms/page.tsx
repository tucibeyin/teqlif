import { Shield, FileText, AlertTriangle, AlertCircle, Users, BellOff } from "lucide-react";
import Link from "next/link";

export default function TermsPage() {
    return (
        <div className="flex-1 w-full pb-16">
            <section className="hero">
                <div className="container">
                    <div style={{ padding: "1rem", display: "inline-flex", background: "var(--bg-card)", borderRadius: "var(--radius-xl)", boxShadow: "var(--shadow-sm)", marginBottom: "1.5rem" }}>
                        <FileText size={48} className="text-cyan-500" />
                    </div>
                    <h1 className="hero-title">
                        Kullanım <span style={{ color: "var(--primary)" }}>Koşulları</span>
                    </h1>
                    <p className="hero-subtitle">
                        Son Kullanıcı Lisans Sözleşmesi (EULA)<br />
                        <span style={{ fontSize: "0.85rem", opacity: 0.8 }}>Son Güncelleme: {new Date().toLocaleDateString('tr-TR')}</span>
                    </p>
                </div>
            </section>

            <div className="container" style={{ marginTop: "-2rem", position: "relative", zIndex: 10 }}>
                <div className="card mx-auto" style={{ maxWidth: "800px" }}>
                    <div className="card-body" style={{ padding: "2rem sm:3rem" }}>

                        <div className="prose prose-gray max-w-none text-gray-600 space-y-10">

                            {/* Zero Tolerance Callout */}
                            <div style={{ background: "#fef2f2", borderLeft: "4px solid #ef4444", borderRight: "1px solid #fecaca", borderTop: "1px solid #fecaca", borderBottom: "1px solid #fecaca", padding: "1.5rem", borderRadius: "0 var(--radius-lg) var(--radius-lg) 0", display: "flex", gap: "1rem" }}>
                                <AlertTriangle size={32} style={{ color: "#ef4444", flexShrink: 0 }} />
                                <div>
                                    <h3 style={{ fontSize: "1.125rem", fontWeight: 700, color: "#991b1b", marginBottom: "0.5rem", marginTop: 0 }}>Önemli Bildirim: Sıfır Tolerans Politikası (UGC)</h3>
                                    <p style={{ margin: 0, color: "#b91c1c", lineHeight: 1.6, fontSize: "0.95rem" }}>
                                        teqlif platformu ("Uygulama"), Kullanıcı Tarafından Oluşturulan İçeriklerde (UGC) ve platform içi iletişimlerde
                                        <strong> sakıncalı içeriğe, nefret söylemine, zorbalığa ve tacize karşı SIFIR TOLERANS </strong>
                                        politikası uygulamaktadır. Bu kuralı ihlal eden kullanıcıların hesapları hiçbir uyarı yapılmaksızın
                                        <strong style={{ background: "rgba(239, 68, 68, 0.2)", padding: "0 0.25rem", borderRadius: "4px" }}> 24 saat içerisinde kalıcı olarak kapatılacaktır.</strong>
                                    </p>
                                </div>
                            </div>

                            {/* Section 1 */}
                            <section>
                                <h2 style={{ fontSize: "1.5rem", fontWeight: 700, color: "var(--text-primary)", marginBottom: "1rem", display: "flex", alignItems: "center", gap: "0.75rem" }}>
                                    <div style={{ width: "40px", height: "40px", background: "var(--primary-50)", color: "var(--primary)", borderRadius: "var(--radius-md)", display: "flex", alignItems: "center", justifyContent: "center" }}>
                                        <Shield size={20} />
                                    </div>
                                    1. Kabul Edilemez Davranışlar ve İçerikler
                                </h2>
                                <div style={{ background: "var(--bg-secondary)", border: "1px solid var(--border)", borderRadius: "var(--radius-lg)", padding: "1.5rem" }}>
                                    <p style={{ marginBottom: "1rem", fontWeight: 500, color: "var(--text-primary)" }}>Aşağıda belirtilen içeriklerin Uygulama içerisinde yayınlanması, mesajlaşma yoluyla iletilmesi veya herhangi bir şekilde paylaşılması kesinlikle yasaktır:</p>
                                    <ul style={{ listStyleType: "none", padding: 0, margin: 0, display: "flex", flexDirection: "column", gap: "0.75rem" }}>
                                        {[
                                            "Irk, din, cinsiyet, cinsel yönelim veya diğer kişisel özelliklere yönelik nefret söylemleri ve aşağılayıcı ifadeler.",
                                            "Diğer kullanıcıları tehdit eden, taciz eden veya zorbalık içeren davranışlar.",
                                            "Müstehcen, pornografik veya cinsel olarak açık içerikler.",
                                            "Yasadışı faaliyetleri teşvik eden veya destekleyen içerikler.",
                                            "Spam, yanıltıcı bilgiler veya dolandırıcılık amaçlı paylaşımlar."
                                        ].map((item, idx) => (
                                            <li key={idx} style={{ display: "flex", alignItems: "flex-start", gap: "0.75rem" }}>
                                                <span style={{ width: "6px", height: "6px", borderRadius: "50%", background: "var(--primary)", marginTop: "0.5rem", flexShrink: 0 }} />
                                                <span>{item}</span>
                                            </li>
                                        ))}
                                    </ul>
                                </div>
                            </section>

                            {/* Section 2 */}
                            <section>
                                <h2 style={{ fontSize: "1.5rem", fontWeight: 700, color: "var(--text-primary)", marginBottom: "1rem", display: "flex", alignItems: "center", gap: "0.75rem" }}>
                                    <div style={{ width: "40px", height: "40px", background: "var(--primary-50)", color: "var(--primary)", borderRadius: "var(--radius-md)", display: "flex", alignItems: "center", justifyContent: "center" }}>
                                        <AlertCircle size={20} />
                                    </div>
                                    2. Raporlama ve Şikayet Mekanizması
                                </h2>
                                <div style={{ display: "flex", flexDirection: "column", gap: "1rem" }}>
                                    <p>
                                        teqlif, kullanıcılar tarafından oluşturulan içeriği denetleme hakkını saklı tutar ve kullanıcıların topluluk standartlarına uygun bir ortamda kalmasını sağlamak için
                                        Kullanıcı Tarafından Oluşturulan İçerikleri (UGC) aktif olarak izler veya izlememesine bakılmaksızın kullanıcı geri bildirimlerini son derece ciddiye alır.
                                    </p>
                                    <div style={{ background: "#f0fdf4", border: "1px solid #bbf7d0", padding: "1.25rem", borderRadius: "var(--radius-lg)", color: "#166534", display: "flex", gap: "1rem", alignItems: "flex-start" }}>
                                        <Users style={{ color: "#16a34a", marginTop: "0.25rem", flexShrink: 0 }} size={24} />
                                        <p style={{ margin: 0, fontSize: "0.95rem" }}>
                                            Platformdaki tüm ilan sayfalarında ve kullanıcı profillerinde <strong style={{ fontWeight: 700 }}>"Şikayet Et"</strong> butonu bulunmaktadır. Şikayetleriniz destek ekibimiz tarafından
                                            en geç 24 saat içerisinde incelenir. İnceleme sonucunda ihlal tespit edilen içerikler derhal kaldırılır ve ihlali gerçekleştiren
                                            kullanıcı hesabı askıya alınır veya kalıcı olarak silinir.
                                        </p>
                                    </div>
                                </div>
                            </section>

                            {/* Section 3 */}
                            <section>
                                <h2 style={{ fontSize: "1.5rem", fontWeight: 700, color: "var(--text-primary)", marginBottom: "1rem", display: "flex", alignItems: "center", gap: "0.75rem" }}>
                                    <div style={{ width: "40px", height: "40px", background: "var(--primary-50)", color: "var(--primary)", borderRadius: "var(--radius-md)", display: "flex", alignItems: "center", justifyContent: "center" }}>
                                        <BellOff size={20} />
                                    </div>
                                    3. Engelleme (Block) Özelliği
                                </h2>
                                <p>
                                    Anında müdahale hakkınız çerçevesinde, sizi rahatsız eden veya kuralları ihlal ettiğini düşündüğünüz kullanıcıları <strong style={{ background: "var(--bg-secondary)", padding: "0.1rem 0.3rem", borderRadius: "4px", color: "var(--text-primary)" }}>"Kullanıcıyı Engelle"</strong>
                                    seçeneği ile anında engelleyebilirsiniz. Engellenen kullanıcılar sizinle bir daha iletişim kuramaz, ilanlarınızı göremez
                                    ve aktif sohbetleriniz anında sonlandırılır.
                                </p>
                            </section>

                            {/* Footer Note */}
                            <div style={{ marginTop: "3rem", padding: "2rem", background: "var(--bg-secondary)", borderRadius: "var(--radius-xl)", textAlign: "center", border: "1px solid var(--border)", color: "var(--text-secondary)" }}>
                                <p style={{ marginBottom: "1rem" }}>
                                    Kullanım koşulları hakkında sorularınız veya herhangi bir şikayetiniz için <Link href="/support" style={{ color: "var(--primary)", fontWeight: 600, textDecoration: "none" }}>destek sayfamızdan</Link> veya doğrudan
                                    <a href="mailto:destek@teqlif.com" style={{ fontWeight: 700, color: "var(--text-primary)", marginLeft: "4px", textDecoration: "none" }}>destek@teqlif.com</a> adresinden bizimle iletişime geçebilirsiniz.
                                </p>
                                <div style={{ width: "48px", height: "1px", background: "var(--border)", margin: "1.5rem auto" }}></div>
                                <p style={{ fontSize: "0.85rem", margin: 0, opacity: 0.8 }}>
                                    Uygulamamızı kullanarak, yukarıdaki kuralları içeren Son Kullanıcı Lisans Sözleşmesi'ni (EULA) tamamen okuduğunuzu, anladığınızı ve koşulsuz olarak kabul ettiğinizi beyan etmiş olursunuz.
                                </p>
                            </div>

                        </div>
                    </div>
                </div>
            </div>
        </div>
    );
}
